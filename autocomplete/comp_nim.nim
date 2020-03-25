# MIT License
#
# Copyright (c) 2019 - 2020 pseudo-random <josh.leh.2018@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import osproc, unicode, strutils, sequtils, sugar, sets, deques
import net, times, os, streams, random, selectors, tables, hashes
import "../buffer", "../utils"

type
  CompCallback = proc (comps: seq[Completion])
  DefsCallback = proc (defs: seq[Definition])

  JobKind = enum JobDefs, JobComp, JobTrack
  
  WaitingJob = object
    buffer: Buffer
    case kind: JobKind:
      of JobTrack: discard
      of JobComp:
        pos: int
        comp_callback: CompCallback
      of JobDefs:
        defs_callback: DefsCallback
  
  Job = object
    path: string
    socket: Socket
    data: string
    case kind: JobKind:
      of JobDefs: defs_callback: DefsCallback
      of JobComp: comp_callback: CompCallback
      else: discard
    
  Context = ref ContextObj
  ContextObj = object of Autocompleter
    nimsuggest: Process
    port: Port
    gen: Rand
    selector: Selector[pointer]
    proc_selector: Selector[pointer]
    jobs: Table[int, Job]
    folder: string
    waiting: Deque[WaitingJob]
    tracked: HashSet[Buffer]

proc hash(buffer: Buffer): Hash =
  return buffer.file_path.hash()

proc to_comp_kind(str: string): CompKind =
  case str:
    of "skUnknown": return CompUnknown
    of "skProc": return CompProc
    of "skMethod": return CompMethod
    of "skIterator": return CompIterator
    of "skTemplate": return CompTemplate
    of "skVar": return CompVar
    of "skLet": return CompLet
    of "skConst": return CompConst
    of "skType": return CompType
    of "skField": return CompField
    of "skMacro": return CompMacro
    of "skConverter": return CompConverter
    of "skEnumField": return CompEnum
    of "skFunc": return CompFunc
    else: return CompUnknown

proc to_def_kind(str: string): DefKind =
  case str:
    of "skUnknown": return DefUnknown
    of "skProc": return DefProc
    of "skMethod": return DefMethod
    of "skIterator": return DefIterator
    of "skTemplate": return DefTemplate
    of "skVar": return DefVar
    of "skLet": return DefLet
    of "skConst": return DefConst
    of "skType": return DefType
    of "skField": return DefField
    of "skMacro": return DefMacro
    of "skConverter": return DefConverter
    of "skFunc": return DefFunc
    else: return DefUnknown

proc create_temp_folder(gen: var Rand): string =
  var name = ".temp" & $gen.next()
  while exists_dir(name):
    name &= $get_time().to_unix()
  create_dir(name)
  return name

proc make_context(): Context =
  result = Context(
    triggers: @[
      Rune('.'), Rune('(')
    ],
    finish: @[
      Rune(' '), Rune('\n'), Rune('\r'), Rune('\t'),
      Rune('+'), Rune('-'), Rune('*'), Rune('/'),
      Rune(','), Rune(';'),
      Rune('='), Rune('>'), Rune('<'),
      Rune('@'),
      Rune(')'), Rune('}'), Rune('['), Rune(']'), Rune('{')
    ],
    nimsuggest: nil,
    selector: new_selector[pointer](),
    proc_selector: new_selector[pointer](),
    gen: init_rand(get_time().to_unix()),
  )
  result.folder = create_temp_folder(result.gen)

proc find_nimsuggest(): string =
  let nimble_path = get_home_dir() / ".nimble" / "bin" / "nimsuggest"
  if file_exists(nimble_path):  
    return nimble_path

proc restart_nimsuggest(ctx: Context) =
  let path = find_nimsuggest()
  if path.len == 0:
    return
  if ctx.tracked.len == 0:
    return
  let buffer = ctx.tracked.pop()
  ctx.nimsuggest = start_process(path, args=["--address:127.0.0.1", "--autobind", buffer.file_path])
  ctx.proc_selector = new_selector[pointer]()
  ctx.proc_selector.register(ctx.nimsuggest.output_handle.int, {Event.Read}, nil)
  
  for buf in ctx.tracked:
    ctx.waiting.add_first(WaitingJob(
      kind: JobTrack,
      buffer: buf
    ))
  
  ctx.tracked.incl(buffer)

proc send_command(ctx: Context, command: string): Socket =
  let socket = new_socket()
  try:
    socket.connect("localhost", ctx.port)
    socket.send(command & "\n")
    return socket
  except OSError:
    if not ctx.nimsuggest.running:
      ctx.proc_selector.unregister(ctx.nimsuggest.output_handle.int)
      ctx.nimsuggest.close()
      ctx.nimsuggest = nil
      ctx.port = Port(0)
      ctx.restart_nimsuggest()
    return nil

method close(ctx: Context) =
  ctx.poll()
  
  if ctx.nimsuggest != nil:
    try:
      discard ctx.send_command("quit")
      discard ctx.nimsuggest.wait_for_exit(timeout=1000)
      ctx.nimsuggest.close()
    except OSError as e:
      echo "OSError"

  remove_dir(ctx.folder)

proc execute(job: Job) =
  case job.kind:
    of JobComp:
      var comps: seq[Completion] = @[]
      for line in job.data.split('\n'):
        if line.len == 0:
          continue
        let values = line.split('\t')
        if values.len < 3:
          continue
        comps.add(Completion(
          text: values[2].split('.')[^1].to_runes(),
          kind: values[1].to_comp_kind()
        ))
      
      job.comp_callback(comps)
    of JobDefs:
      var defs: seq[Definition] = @[]
      for line in job.data.split('\n'):
        if line.len == 0:
          continue
        let values = line.split('\t')
        if values.len < 7:
          continue
        
        try:
          defs.add(Definition(
            kind: to_def_kind(values[1]),
            name: to_runes(values[2].split('.')[1.. ^1].join(".")),
            pos: Index2d(
              x: values[6].parse_int(),
              y: values[5].parse_int() - 1
            )
          ))
        except ValueError:
          discard
      job.defs_callback(defs)
    else: discard
  remove_file(job.path)

proc save_temp(ctx: Context, buffer: Buffer): string =
  try:
    let 
      file_name = $get_time().to_unix() & "_" & $ctx.gen.next() & ".nim"
      tmp_path = ctx.folder / file_name
    write_file(tmp_path, $buffer.text)
    return tmp_path
  except IOError:
    return

proc execute(ctx: Context, job: WaitingJob) =
  case job.kind:
    of JobTrack:
      discard ctx.send_command("mod " & job.buffer.file_path)
    of JobComp:
      let tmp_path = ctx.save_temp(job.buffer)
      if tmp_path.len == 0:
        return
  
      let
        index = job.buffer.to_2d(job.pos)
        socket = ctx.send_command(
          "sug " & job.buffer.file_name & ";" & tmp_path & ":" & $(index.y + 1) & ":" & $(index.x)
        )
      if socket == nil:
        ctx.waiting.add_last(job)
        return
      
      ctx.jobs[socket.get_fd().int] = Job(kind: JobComp,
        comp_callback: job.comp_callback,
        path: tmp_path,
        socket: socket
      )
      ctx.selector.register_handle(socket.get_fd(), {Event.Read}, nil)
    of JobDefs:
      let tmp_path = ctx.save_temp(job.buffer)
      if tmp_path.len == 0:
        return
      
      let socket = ctx.send_command(
        "outline " & job.buffer.file_name & ";" & tmp_path
      )
      if socket == nil:
        ctx.waiting.add_last(job)
        return
    
      ctx.jobs[socket.get_fd().int] = Job(kind: JobDefs,
        defs_callback: job.defs_callback,
        path: tmp_path,
        socket: socket
      )
      ctx.selector.register_handle(socket.get_fd(), {Event.Read}, nil)

method poll(ctx: Context) =
  if ctx.nimsuggest != nil:
    if ctx.proc_selector.select(0).len > 0 and ctx.port == Port(0):
      try:
        ctx.port = Port(ctx.nimsuggest.output_stream().read_line().parse_int())
      except IOError:
        ctx.nimsuggest.close()
        ctx.nimsuggest = nil
        ctx.port = Port(0)
        ctx.restart_nimsuggest()
        return
      var jobs = ctx.waiting
      for job in jobs:
        ctx.execute(job)

  while true:
    let fds = ctx.selector.select(0)
    if fds.len == 0:
      break
    for fd in fds:
      let job = ctx.jobs[fd.fd].addr
      var data = ""
      try:
        data = job.socket.recv(512)
      except OSError:
        discard
      if data == "":
        ctx.selector.unregister(job.socket.get_fd())
        job.socket.close()
        job[].execute()
        ctx.jobs.del(fd.fd)
      job.data &= data

proc try_execute(ctx: Context, job: WaitingJob) =
  if ctx.nimsuggest == nil:
    ctx.waiting.add_last(job)
    ctx.restart_nimsuggest()
    return
  elif ctx.port == Port(0):
    ctx.waiting.add_last(job)
  
  ctx.poll()
  ctx.execute(job)

method track(ctx: Context, buffer: Buffer) =
  ctx.tracked.incl(buffer)
  if ctx.nimsuggest == nil:
    ctx.restart_nimsuggest()
  else:
    ctx.poll()
    ctx.execute(WaitingJob(kind: JobTrack, buffer: buffer))

method complete(ctx: Context,
                buffer: Buffer,
                pos: int,
                trigger: Rune,
                callback: CompCallback) =
  ctx.try_execute(WaitingJob(kind: JobComp,
    buffer: buffer,
    pos: pos,
    comp_callback: callback
  ))

method list_defs(ctx: Context,
                 buffer: Buffer,
                 callback: DefsCallback) =
  ctx.try_execute(WaitingJob(kind: JobDefs,
    buffer: buffer,
    defs_callback: callback
  ))

proc make_nim_autocompleter*(): Autocompleter = make_context()
