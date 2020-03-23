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

import osproc, unicode, strutils, sequtils, sugar
import net, times, os, streams, random, selectors, tables
import "../buffer", "../utils"

type
  CompCallback = proc (comps: seq[Completion])

  Job = object
    callback: CompCallback
    path: string
    socket: Socket
    data: string

  Context = ref ContextObj
  ContextObj = object of Autocompleter
    nimsuggest: Process
    port: Port
    gen: Rand
    selector: Selector[pointer]
    proc_selector: Selector[pointer]
    jobs: Table[int, Job]
    folder: string

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
    gen: init_rand(get_time().to_unix()),
  )
  result.folder = create_temp_folder(result.gen)

proc send_command(ctx: Context, command: string) =
  try:
    let socket = new_socket()
    socket.connect("localhost", ctx.port)
    socket.send(command & "\n")
  except OSError:
    discard

method close(ctx: Context) =
  ctx.poll()
  
  try:
    ctx.send_command("quit")
    discard ctx.nimsuggest.wait_for_exit(timeout=1000)
    ctx.nimsuggest.close()
  except OSError as e:
    echo "OSError"

  remove_dir(ctx.folder)

proc find_nimsuggest(): string =
  let nimble_path = get_home_dir() / ".nimble" / "bin" / "nimsuggest"
  if file_exists(nimble_path):  
    return nimble_path

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

proc execute(job: Job) =
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
  
  job.callback(comps)
  remove_file(job.path)

method poll(ctx: Context) =
  if ctx.proc_selector.select(0).len > 0 and ctx.port == Port(0):
    ctx.port = Port(ctx.nimsuggest.output_stream().read_line().parse_int())

  while true:
    let fds = ctx.selector.select(0)
    if fds.len == 0:
      break
    for fd in fds:
      let job = ctx.jobs[fd.fd].addr
      let data = job.socket.recv(512)
      if data == "":
        ctx.selector.unregister(job.socket.get_fd())
        job.socket.close()
        job[].execute()
        ctx.jobs.del(fd.fd)
      job.data &= data

method track(ctx: Context, buffer: Buffer) =
  if ctx.nimsuggest == nil:
    let path = find_nimsuggest()
    if path.len == 0:
      return
    ctx.nimsuggest = start_process(path, args=["--address:127.0.0.1", "--autobind", buffer.file_path])
    ctx.proc_selector = new_selector[pointer]()
    ctx.proc_selector.register(ctx.nimsuggest.output_handle.int, {Event.Read}, nil)
  else:
    ctx.poll()
    ctx.send_command("mod " & buffer.file_path)

method complete(ctx: Context,
                buffer: Buffer,
                pos: int,
                trigger: Rune,
                callback: CompCallback) =
  if ctx.nimsuggest == nil:
    discard
  
  ctx.poll()
  
  var tmp_path: string
  try:
    let 
      file_name = $get_time().to_unix() & "_" & $ctx.gen.next() & ".nim"
    tmp_path = ctx.folder / file_name
    write_file(tmp_path, $buffer.text)
  except IOError:
    return
  
  let
    index = buffer.to_2d(pos)
    cmd = "sug " & buffer.file_name & ";" & tmp_path & ":" & $(index.y + 1) & ":" & $(index.x)

  let socket = new_socket()
  try:
    socket.connect("localhost", ctx.port)
    socket.send(cmd & "\n")
  except OSError:
    discard

  ctx.jobs[socket.get_fd().int] = Job(
    callback: callback,
    path: tmp_path,
    socket: socket
  )
  ctx.selector.register_handle(socket.get_fd(), {Event.Read}, nil)
  

proc make_nim_autocompleter*(): Autocompleter = make_context()
