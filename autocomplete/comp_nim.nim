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
import ../buffer, ../utils

type
  CaseStyle = enum CaseUnknown, CaseCamel, CaseSnake, CasePascal

  CompCallback = proc (comps: seq[Completion])
  DefsCallback = proc (defs: seq[Definition])

  JobKind = enum JobDefs, JobComp, JobTrack
  
  Job = object
    path: string
    data: string
    chan: ptr Channel[(bool, string)]
    thread: Thread[(ptr Channel[(bool, string)], string, Port)]
    buffer: Buffer  
    case kind: JobKind:
      of JobDefs:
        defs_callback: DefsCallback
      of JobComp:
        pos: int
        case_style: CaseStyle
        comp_callback: CompCallback
      of JobTrack: discard
    
  Context = ref ContextObj
  ContextObj = object of Autocompleter
    gen: Rand

    nimsuggest: Process
    port: Port
    when not defined(windows):
      stdout_selector: Selector[pointer]
    
    jobs: seq[Job]
    waiting: Deque[Job]

    folder: string
    tracked: HashSet[Buffer]
    case_styles: Table[Buffer, CaseStyle]

proc hash(buffer: Buffer): Hash =
  return buffer.file_path.hash()

proc case_style(name: seq[Rune]): CaseStyle =
  for it, chr in name:
    if chr == '_':
      return CaseSnake
    elif chr.is_upper():
      if it == 0:
        return CasePascal
      else:
        return CaseCamel
  return CaseUnknown

proc convert_case(name: seq[Rune], from_style, to_style: CaseStyle): seq[Rune] =
  if from_style == to_style:
    return name

  var parts: seq[seq[Rune]] = @[]
  case from_style:
    of CaseUnknown:
      return name
    of CaseSnake:
      parts = name.split('_')
    of CaseCamel, CasePascal:
      parts.add(@[])
      for it, chr in name:
        if chr.is_upper():
          if it == 0:
            parts[^1].add(chr.to_lower())
          else:
            parts.add(@[chr.to_lower()])
        else:
          parts[^1].add(chr)
  
  case to_style:
    of CaseUnknown:
      return name
    of CaseSnake:
      return parts.join('_')
    of CaseCamel:
      return (@[parts[0]] & parts[1..^1].map(part => part.capitalize)).join()
    of CasePascal:
      return parts.map(part => part.capitalize).join()

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
      Rune('.'), Rune('('), Rune('[')
    ],
    finish: @[
      Rune(' '), Rune('\n'), Rune('\r'), Rune('\t'),
      Rune('+'), Rune('-'), Rune('*'), Rune('/'),
      Rune(','), Rune(';'),
      Rune('='), Rune('>'), Rune('<'),
      Rune('@'),
      Rune(')'), Rune('}'), Rune(']'), Rune('{')
    ],
    nimsuggest: nil,
    gen: init_rand(get_time().to_unix()),
    min_word_len: 5
  )
  when not defined(windows):
    result.stdout_selector = new_selector[pointer]()
  result.folder = create_temp_folder(result.gen)

proc find_nimsuggest(): string =
  return find_exe("nimsuggest")

proc restart_nimsuggest(ctx: Context) =
  let path = find_nimsuggest()
  if path.len == 0:
    return
  if ctx.tracked.len == 0:
    return
  let buffer = ctx.tracked.pop()
  ctx.nimsuggest = start_process(path, args=[
    "--address:127.0.0.1", "--autobind", buffer.file_path
  ], options={poInteractive})
  
  for buf in ctx.tracked:
    ctx.waiting.add_first(Job(
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
    socket.close()
    if not ctx.nimsuggest.running:
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
    except OSError:
      echo "OSError"

  remove_dir(ctx.folder)

proc handle(job: Job) =
  case job.kind:
    of JobComp:
      var comps: seq[Completion] = @[]
      for line in job.data.split('\n'):
        if line.len == 0:
          continue
        let values = line.split('\t')
        if values.len < 3:
          continue
        var text = values[2].split('.')[^1].to_runes()
        let text_case = text.case_style()
        if text_case == CaseSnake or text_case == CaseCamel:
          text = text.convert_case(text_case, job.case_style)
        comps.add(Completion(
          text: text,
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

proc read(args: (ptr Channel[(bool, string)], string, Port)) =
  let socket = new_socket()
  try:
    socket.connect("localhost", args[2])
    socket.send(args[1])
  except OSError:
    socket.close()
    args[0][].send((false, ""))
    return
  var data = ""
  while true:
    var packet: string
    try:
      packet = socket.recv(512)
    except OSError:
      break
    if packet.len == 0:
      break
    data &= packet
  args[0][].send((true, data))
  socket.close()

proc execute(ctx: Context, job: Job) =
  case job.kind:
    of JobTrack:
      let sock = ctx.send_command("mod " & job.buffer.file_path)
      if sock != nil:
        sock.close()
    of JobComp, JobDefs:
      let tmp_path = ctx.save_temp(job.buffer)
      if tmp_path.len == 0:
        return
  
      var command: string
      case job.kind:
        of JobComp:
          let index = job.buffer.to_2d(job.pos)
          command = "sug " & job.buffer.file_name & ";" & tmp_path & ":" & $(index.y + 1) & ":" & $(index.x)
        of JobDefs:
          command = "outline " & job.buffer.file_name & ";" & tmp_path
        else: discard
      command &= "\n"
      
      ctx.jobs.add(job)
      ctx.jobs[^1].path = tmp_path
      let chan = cast[ptr Channel[(bool, string)]](
        alloc_shared0(sizeof Channel[(bool, string)])
      )
      chan[].open()
      ctx.jobs[^1].chan = chan
      create_thread(ctx.jobs[^1].thread, read, (ctx.jobs[^1].chan, command, ctx.port))

method poll(ctx: Context) =
  if ctx.nimsuggest == nil:
    ctx.restart_nimsuggest()
    return
  
  if ctx.port == Port(0):
    when defined(windows):
      if not ctx.nimsuggest.has_data():
        return
    else:
      let handle = ctx.nimsuggest.output_handle.int
      ctx.stdout_selector.register_handle(handle, {Read}, nil)
      let selected = ctx.stdout_selector.select(0)
      ctx.stdout_selector.unregister(handle)
      if selected.len == 0:
        return
    try:
      ctx.port = Port(ctx.nimsuggest.output_stream().read_line().parse_int())
    except IOError, ValueError:
      ctx.nimsuggest.close()
      ctx.nimsuggest = nil
      ctx.port = Port(0)
      ctx.restart_nimsuggest()
      return
    for job in ctx.waiting:
      ctx.execute(job)
    ctx.waiting = init_deque[Job]()
    return
  
  var it = 0
  while it < ctx.jobs.len:
    var  
      (has_msg, message) = ctx.jobs[it].chan[].try_recv()
      (success, data) = message
    if not has_msg:
      it += 1
      continue
    if success:
      ctx.jobs[it].data = data
      handle(ctx.jobs[it])
      
    if ctx.jobs[it].thread.running:
      ctx.jobs[it].thread.join_thread()
    ctx.jobs[it].chan[].close()
    dealloc_shared(ctx.jobs[it].chan)
    
    if not success and not ctx.nimsuggest.running:
      ctx.nimsuggest.close()
      ctx.nimsuggest = nil
      ctx.port = Port(0)
      ctx.restart_nimsuggest()
      for job in ctx.jobs:
        ctx.waiting.add_last(job)
      ctx.jobs = @[]
      break

    ctx.jobs.del(it)

proc add_waiting(ctx: Context, job: Job) =
  if ctx.nimsuggest == nil:
    ctx.waiting.add_last(job)
    ctx.restart_nimsuggest()
  elif ctx.port == Port(0):
    ctx.waiting.add_last(job)
  else:
    ctx.poll()
    ctx.execute(job)

method track(ctx: Context, buffer: Buffer) =
  ctx.tracked.incl(buffer)
  if ctx.nimsuggest == nil:
    ctx.restart_nimsuggest()
  else:
    ctx.poll()
    ctx.add_waiting(Job(kind: JobTrack, buffer: buffer))
  ctx.add_waiting(Job(kind: JobDefs,
    buffer: buffer,
    defs_callback: proc (defs: seq[Definition]) =
      var style_counts: array[CaseStyle, int]
      for def in defs:
         style_counts[def.name.split('.')[^1].case_style()] += 1
      if style_counts[CaseCamel] < style_counts[CaseSnake]:
        ctx.case_styles[buffer] = CaseSnake
      else:
        ctx.case_styles[buffer] = CaseCamel
  ))

proc get_case_style(ctx: Context, buffer: Buffer): CaseStyle =
  result = CaseUnknown
  if buffer in ctx.case_styles:
    result = ctx.case_styles[buffer]

method complete(ctx: Context,
                buffer: Buffer,
                pos: int,
                trigger: Rune,
                callback: CompCallback) =
  ctx.add_waiting(Job(kind: JobComp,
    buffer: buffer,
    pos: pos,
    comp_callback: callback,
    case_style: ctx.get_case_style(buffer)
  ))

method list_defs(ctx: Context,
                 buffer: Buffer,
                 callback: DefsCallback) =
  ctx.add_waiting(Job(kind: JobDefs,
    buffer: buffer,
    defs_callback: callback
  ))

method buffer_info(ctx: Context, buffer: Buffer): seq[string] =
  case ctx.case_styles[buffer]:
    of CaseUnknown: return @["Unknown Case"]
    of CaseCamel: return @["Camel Case"]
    of CaseSnake: return @["Snake Case"]
    of CasePascal: return @["Pascal Case"]

proc make_nim_autocompleter*(): Autocompleter =
  return make_context()
