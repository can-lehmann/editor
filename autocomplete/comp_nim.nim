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

import unicode, strutils, os, tables, sets, hashes, streams
import sugar, sequtils, times, osproc, deques, nativesockets
import asyncdispatch, asyncnet, asyncfile, selectors
import ../buffer, ../utils, ../log

type
  CaseStyle = enum CaseUnknown, CaseCamel, CaseSnake, CasePascal

  CompCallback = proc (comps: seq[Completion])
  DefsCallback = proc (defs: seq[Definition])
  
  JobKind = enum JobComp, JobDefs
  Job = object  
    buffer: Buffer
    case kind: JobKind:
      of JobComp:
        comp_pos: int
        comp_cb: CompCallback
      of JobDefs:
        defs_cb: DefsCallback

  Context = ref ContextObj
  ContextObj = object of Autocompleter
    log: Log
    folder: string
    file_id: int
    max_completions: int
    
    tracked: HashSet[Buffer]
    case_styles: Table[Buffer, CaseStyle]
    
    waiting: Deque[Job]
    
    nimsuggest: Process
    port: Port
    is_restarting: bool
    
    when not defined(windows):
      stdout_selector: Selector[pointer]

proc peek[T](hash_set: HashSet[T]): T =
  for item in hash_set:
    return item

proc hash(buffer: Buffer): Hash =
  return buffer.file_path.hash()

proc get_case_style(ctx: Context, buffer: Buffer): CaseStyle =
  result = CaseUnknown
  if buffer in ctx.case_styles:
    result = ctx.case_styles[buffer]

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

proc detect_case_style(defs: seq[Definition]): CaseStyle =
  var counts: array[CaseStyle, int]
  for def in defs:
    counts[def.name.case_style()] += 1
  var max_count = 0
  result = CaseCamel
  for style, count in counts:
    if style == CaseUnknown or style == CasePascal:
      continue
    if count > max_count:
      max_count = count
      result = style

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

proc create_temp_folder(): string =
  var id = get_time().to_unix()
  while exists_dir(".temp" & $id):
    id += 1
  create_dir(".temp" & $id)
  return ".temp" & $id

proc save_temp_buffer(ctx: Context, buffer: Buffer): Future[string] {.async.} =
  try:
    let id = ctx.file_id
    ctx.file_id += 1
    result = ctx.folder / ("file" & $id & ".nim")
    if not exists_dir(ctx.folder):
      create_dir(ctx.folder)
    let file = open_async(result, fmWrite)
    await file.write($buffer.text)
    file.close()
  except IOError, FutureError, OSError:
    return ""

proc make_context(log: Log): Context =
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
    min_word_len: 5,
    log: log,
    max_completions: 128
  )
  when not defined(windows):
    result.stdout_selector = new_selector[pointer]()
  result.folder = create_temp_folder()

proc has_nimsuggest(ctx: Context): bool =
  ctx.nimsuggest != nil and
  ctx.port != Port(0) and
  ctx.nimsuggest.running

proc restart_nimsuggest(ctx: Context)

proc recv_lines(socket: AsyncSocket): Future[seq[string]] {.async.} =
  var lines: seq[string]
  while true:
    let line = await socket.recv_line()
    if line.len == 0:
      break
    lines.add(line)
  return lines

proc exec(ctx: Context, job: Job) {.async.} =
  case job.kind:
    of JobDefs:
      let socket = new_async_socket()
      await socket.connect("127.0.0.1", ctx.port)
      await socket.send("outline " & job.buffer.file_path & "\n")
      let lines = await socket.recv_lines()
      socket.close()
      
      var defs: seq[Definition]
      for line in lines:
        let parts = line.strip(chars={'\r', '\n'}).split("\t")
        if parts.len < 7:
          continue
        defs.add(Definition(
          kind: parts[1].to_def_kind(),
          name: to_runes(parts[2].split(".")[1..^1].join(".")),
          pos: Index2d(
            x: parse_int(parts[6]),
            y: parse_int(parts[5]) - 1
          )
        ))
      ctx.log.add_info("comp_nim", "Received " & $defs.len & " definitions")
      job.defs_cb(defs)
      ctx.case_styles[job.buffer] = defs.detect_case_style()
    of JobComp:
      let socket = new_async_socket()
      await socket.connect("127.0.0.1", ctx.port)
      let pos = job.buffer.to_2d(job.comp_pos)
      if job.buffer.len != 0:
        let temp = await ctx.save_temp_buffer(job.buffer)
        await socket.send("sug " & job.buffer.file_path & ";" & temp & ":" & $(pos.y + 1) & ":" & $pos.y & "\n")
      else:
        await socket.send("sug " & job.buffer.file_path & ":" & $(pos.y + 1) & ":" & $pos.y & "\n")
      let lines = await socket.recv_lines()
      socket.close()
      
      var comps: seq[Completion]
      for line in lines:
        if comps.len >= ctx.max_completions:
          if lines.len >= ctx.max_completions:
            ctx.log.add_warning("comp_nim",
              "Received " & $lines.len &
              " completions but the maximum is " & $ctx.max_completions
            )
          break
        let parts = line.strip(chars={'\r', '\n'}).split("\t")
        if parts.len < 3:
          continue
        let
          text = to_runes(parts[2].split(".")[^1])
          style = text.case_style()
        var styled = text
        if style == CaseSnake or style == CaseCamel:
          styled = text.convert_case(style, ctx.get_case_style(job.buffer))
        comps.add(Completion(
          kind: to_comp_kind(parts[1]),
          text: styled
        ))
      ctx.log.add_info("comp_nim", "Completion count: " & $comps.len)
      job.comp_cb(comps)

proc enqueue(ctx: Context, job: Job) =
  if ctx.has_nimsuggest():
    async_check ctx.exec(job)
    return
  ctx.waiting.add_last(job)
  ctx.restart_nimsuggest()

proc read_port(ctx: Context) =
  let line = ctx.nimsuggest.output_stream.read_line()
  ctx.port = Port(parse_int(line))
  ctx.is_restarting = false

proc restart_nimsuggest(ctx: Context) =
  if ctx.is_restarting and ctx.nimsuggest.running:
    return
  ctx.log.add_warning("comp_nim", "Restarting nimsuggest process")
  
  if ctx.nimsuggest != nil:
    ctx.nimsuggest.close()
    ctx.port = Port(0)
    ctx.nimsuggest = nil
  if ctx.tracked.len == 0:
    return
  let project_buffer = ctx.tracked.peek()
  ctx.is_restarting = true
  ctx.nimsuggest = start_process(find_exe("nimsuggest"), args=[
    "--autobind", "--address:127.0.0.1", project_buffer.file_path,
    "--maxresults:" & $ctx.max_completions
  ])
  when defined(windows):
    ctx.read_port()

proc send_command(ctx: Context, cmd: string) =
  if not ctx.has_nimsuggest():
    return
  let socket = new_async_socket()
  try:
    wait_for socket.connect("127.0.0.1", ctx.port)
    wait_for socket.send(cmd & "\n")
    socket.close()
  except OSError:
    socket.close()
    if not ctx.has_nimsuggest():
      ctx.restart_nimsuggest()

method close(ctx: Context) =
  if has_pending_operations():
    drain(timeout=4)
    
  if ctx.nimsuggest != nil:
    try:
      ctx.send_command("quit")
      discard ctx.nimsuggest.wait_for_exit(timeout=1000)
    except OSError:
      discard
  
  if exists_dir(ctx.folder):
    remove_dir(ctx.folder)

proc exec_waiting(ctx: Context) {.async.} =
  while ctx.waiting.len > 0 and ctx.has_nimsuggest():
    await ctx.exec(ctx.waiting.pop_first())

method poll(ctx: Context) =
  if has_pending_operations():
    try:
      let start = get_time()
      drain(1)
      let diff = get_time() - start
      ctx.log.add_info("comp_nim", "Call to drain took " & $diff)
    except OSError as err:
      ctx.log.add_error("comp_nim", err.msg)
  
  when not defined(windows):
    if ctx.is_restarting and ctx.nimsuggest.running:
      let handle = ctx.nimsuggest.output_handle().int
      ctx.stdout_selector.register_handle(handle, {Read}, nil)
      let count = ctx.stdout_selector.select(0).len
      ctx.stdout_selector.unregister(handle)
      if count > 0:
        ctx.read_port()
  
  if ctx.has_nimsuggest() and ctx.waiting.len > 0:
    async_check ctx.exec_waiting()

method track(ctx: Context, buffer: Buffer) =
  ctx.tracked.incl(buffer)
  ctx.enqueue(Job(kind: JobDefs,
    buffer: buffer,
    defs_cb: proc (defs: seq[Definition]) = discard
  ))

method complete(ctx: Context,
                buffer: Buffer,
                pos: int,
                trigger: Rune,
                callback: CompCallback) =
  ctx.enqueue(Job(kind: JobComp,
    buffer: buffer,
    comp_cb: callback,
    comp_pos: pos
  ))

method list_defs(ctx: Context,
                 buffer: Buffer,
                 callback: DefsCallback) =
  ctx.enqueue(Job(kind: JobDefs,
    buffer: buffer,
    defs_cb: callback
  ))

method buffer_info(ctx: Context, buffer: Buffer): seq[string] =
  case ctx.case_styles[buffer]:
    of CaseUnknown: return @["Unknown Case"]
    of CaseCamel: return @["Camel Case"]
    of CaseSnake: return @["Snake Case"]
    of CasePascal: return @["Pascal Case"]

proc make_nim_autocompleter*(log: Log): Autocompleter =
  if find_exe("nimsuggest") == "":
    log.add_error("comp_nim", "Could not find nimsuggest")
    return nil
  return make_context(log)
