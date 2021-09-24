# MIT License
# 
# Copyright (c) 2019 - 2021 Can Joshua Lehmann
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

import strutils, unicode, sequtils, sugar, tables
import utils, highlight/highlight, log

type
  SymbolKind* = enum
    SymNone,
    SymLet, SymConst, SymVar,
    SymProc, SymMethod, SymTemplate, SymFunc,
    SymMacro, SymIterator, SymConverter,
    SymType, SymField, SymEnum,
    SymHeading, SymTag
  
  Symbol* = object
    kind*: SymbolKind
    name*: seq[Rune]
    pos*: Index2d

  Autocompleter* = ref object of RootObj
    triggers*: seq[Rune]
    finish*: seq[Rune]
    min_word_len*: int

  Language* = ref object
    id*: int
    name*: string
    highlighter*: proc (): HighlightState 
    file_exts*: seq[string]
    indent_width*: int
    snippets*: Table[seq[Rune], seq[Rune]]
    make_autocompleter*: proc (log: Log): Autocompleter

  ActionKind* = enum ActionDelete, ActionInsert

  Action* = object
    case kind*: ActionKind:
      of ActionDelete:
        delete_pos*: int
        delete_text*: seq[Rune]
      of ActionInsert:
        insert_pos*: int
        insert_text*: seq[Rune]
  
  IndentStyle* = enum IndentSpaces, IndentTab
  NewlineStyle* = enum NewlineLf, NewlineCrLf
  
  CursorHook* = proc(start: int, delta: int) {.closure.}

  Buffer* = ref object
    file_path*: string
    text*: seq[Rune]
    lines*: seq[int]
    changed*: bool
    tokens*: seq[Token]
    tokens_done*: bool
    language*: Language
    cursor_hooks: Table[int, CursorHook]
    returned_ids: seq[int]
    undo_stack: seq[seq[Action]]
    redo_stack: seq[seq[Action]]
    indent_width*: int
    indent_style*: IndentStyle
    newline_style*: NewlineStyle

# Autocompleter
method track*(ctx: Autocompleter, buffer: Buffer) {.base.} =
  quit "Abstract method known"

method complete*(ctx: Autocompleter,
                 buffer: Buffer,
                 pos: int,
                 trigger: Rune,
                 callback: proc (comps: seq[Symbol])) {.base.} =
  quit "Abstract method complete"

method poll*(ctx: Autocompleter) {.base.} =
  quit "Abstract method poll"

method close*(ctx: Autocompleter) {.base.} =
  quit "Abstract method close"

method list_defs*(ctx: Autocompleter,
                  buffer: Buffer,
                  callback: proc (defs: seq[Symbol])) {.base.} =
  quit "Abstract methods list_defs"

method buffer_info*(ctx: Autocompleter, buffer: Buffer): seq[string] {.base.} = @[]

proc search*(syms: seq[Symbol], query: seq[Rune]): seq[Symbol] =
  syms.filter(sym => sym.name.find(query) != -1)

# Language
proc detect_language*(langs: seq[Language], path: string): Language =
  let
    parts = path.split('.')
    ext = parts[parts.len - 1]
  for lang in langs:
    if ext in lang.file_exts:
      return lang
  return nil

# Buffer
proc len*(buffer: Buffer): int = buffer.text.len
proc `[]`*(buffer: Buffer, index: int): Rune = buffer.text[index]

proc register_hook*(buffer: Buffer, hook: CursorHook): int =
  if buffer.returned_ids.len == 0:
    result = buffer.cursor_hooks.len
  else:
    result = buffer.returned_ids.pop()
  buffer.cursor_hooks[result] = hook

proc unregister_hook*(buffer: Buffer, id: int) =
  buffer.cursor_hooks.del(id)
  buffer.returned_ids.add(id)

proc call_hooks(buffer: Buffer, start, delta: int) =
  for id, hook in buffer.cursor_hooks:
    hook(start, delta)

proc update_tokens*(buffer: Buffer) =
  buffer.tokens = @[]
  buffer.tokens_done = false
  
  if buffer.language == nil or
     buffer.language.highlighter == nil:
    return

  var state = buffer.language.highlighter()
  var tok: Token
  while (tok = state.next(buffer.text); tok.kind != TokenNone):
    buffer.tokens.add(tok)
    state = tok.state

proc delete_tokens*(buffer: Buffer, start: int) =
  var tok: Token = Token(can_stop: true, state: HighlightState())
  while buffer.tokens.len > 0 and
        buffer.tokens[buffer.tokens.len - 1].stop >= start:
    tok = buffer.tokens.pop()
  while not tok.can_stop and buffer.tokens.len > 0:
    tok = buffer.tokens.pop()
  buffer.tokens_done = false
  
proc get_token*(buffer: Buffer, index: int): Token =
  if index < buffer.tokens.len:
    return buffer.tokens[index]  
  
  if buffer.tokens_done or buffer.language == nil:
    return Token(kind: TokenNone, start: -1, stop: -1)

  var state: HighlightState
  if buffer.tokens.len == 0:
    if buffer.language.highlighter == nil:
      return Token(kind: TokenNone, start: -1, stop: -1)
    state = buffer.language.highlighter()
  else:
    state = buffer.tokens[^1].state

  if state == nil:
    return Token(kind: TokenNone, start: -1, stop: -1)
  
  while index >= buffer.tokens.len:
    let token = state.next(buffer.text)
    if token.kind == TokenNone:
      buffer.tokens_done = true
      return Token(kind: TokenNone, start: -1, stop: -1)
    buffer.tokens.add(token)
    state = token.state

  return buffer.tokens[^1]

proc index_lines*(text: seq[Rune]): seq[int] =
  result.add(0)
  for it, chr in text.pairs:
    if chr == '\n':
      result.add(it + 1)

proc reindex_lines*(buffer: Buffer) =
  buffer.lines = buffer.text.index_lines()

proc update_line_indices*(buffer: Buffer, start: int, delta: int) =
  var it = buffer.lines.len - 1
  while it >= 0:
    if buffer.lines[it] < start:
      break
    buffer.lines[it] += delta
    it -= 1

proc to_2d*(buffer: Buffer, index: int): Index2d =
  for it, line_index in buffer.lines:
    if line_index > index:
      return result
    result = Index2d(x: index - line_index, y: it)

proc to_display_2d*(buffer: Buffer, index: int): Index2d =
  let pos = buffer.to_2d(index)
  var
    cur = buffer.lines[pos.y]
    x = 0
  while cur < index and cur < buffer.text.len:
    case buffer.text[cur]:
      of '\t':
        x += buffer.indent_width
      else:
        x += 1
    cur += 1
  return Index2d(x: x, y: pos.y)

proc to_index*(buffer: Buffer, pos: Index2d): int =
  result = pos.x + buffer.lines[pos.y]
  
  if pos.y + 1 >= buffer.lines.len:
    return min(buffer.text.len, result)
  
  if result >= buffer.lines[pos.y + 1]:
    result = buffer.lines[pos.y + 1] - 1

proc display_to_index*(buffer: Buffer, pos: Index2d): int =
  var
    cur = buffer.lines[pos.y]
    cur_x = pos.x
  while cur_x > 0 and cur < buffer.text.len:
    let chr = buffer.text[cur]
    case chr:
      of '\t':
        cur_x -= buffer.indent_width
      of '\n':
        break
      else:
        cur_x -= 1
    cur += 1
  if cur_x < 0:
    cur -= 1
  return cur

proc set_path*(buffer: Buffer, path: string, langs: seq[Language] = @[]) =
  buffer.file_path = path
  if buffer.language == nil:
    buffer.tokens = @[]
    buffer.tokens_done = false
    buffer.language = langs.detect_language(path)

proc file_name*(buffer: Buffer): string =
  let dirs = buffer.file_path.split("/")
  if dirs.len == 0:
    return ""
  return dirs[dirs.len - 1]

proc `$`*(newline_style: NewlineStyle): string =
  case newline_style:
    of NewlineLf: return "Lf"
    of NewlineCrLf: return "CrLf"

proc display_file_name*(buffer: Buffer): string =
  if buffer.file_name == "":
    result = "*Untitled file*"
  else:
    result = buffer.file_name
    if buffer.changed:
      result &= "*"
  
  result &= " ("  
  if buffer.language != nil:
    result &= buffer.language.name
  else:
    result &= "Text"
  result &= ", " & $buffer.indent_width
  result &= ", "
  if buffer.indent_style == IndentSpaces:
    result &= "Spaces"
  elif buffer.indent_style == IndentTab:
    result &= "Tab"
  result &= ", "
  result &= $buffer.newline_style
  result &= ")"

proc save*(buffer: Buffer) =
  write_file(buffer.file_path, $buffer.text)
  buffer.changed = false

proc indent_char*(buffer: Buffer): Rune =
  case buffer.indent_style:
    of IndentTab: return Rune('\t')
    of IndentSpaces: return Rune(' ')

proc make_indent*(buffer: Buffer, level: int): seq[Rune] =
  return sequtils.repeat(buffer.indent_char, level)

proc indentation*(buffer: Buffer, pos: int): int =
  var it = pos - 1
  while it >= 0 and buffer.text[it] != '\n':
    it -= 1
  result = 0
  it += 1
  while it < buffer.text.len and
        buffer.text[it] == buffer.indent_char and
        it < pos:
    result += 1
    it += 1

proc slice*(buffer: Buffer, start, stop: int): seq[Rune] =
  buffer.text.substr(start, stop - 1)

proc delete_no_undo(buffer: Buffer, start, stop: int) =
  buffer.text = buffer.text.substr(0, start - 1) & buffer.text.substr(stop)
  buffer.delete_tokens(start)
  buffer.reindex_lines()
  buffer.changed = true
  for it in countdown(stop - start, 1):
    buffer.call_hooks(start + it, -1)

proc undo_frame(buffer: Buffer): var seq[Action] =
  if buffer.undo_stack.len == 0:
    buffer.undo_stack.add(@[])
  return buffer.undo_stack[buffer.undo_stack.len - 1]

proc delete*(buffer: Buffer, start, stop: int) =
  let text = buffer.slice(start, stop)
  buffer.delete_no_undo(start, stop)
  buffer.undo_frame().add(Action(kind: ActionDelete, delete_pos: start, delete_text: text))
  buffer.redo_stack = @[]

proc insert_no_undo(buffer: Buffer, pos: int, chr: Rune) =
  let
    before = buffer.text.substr(0, pos - 1)
    after = buffer.text.substr(pos)
  buffer.text = before & chr & after
  buffer.update_line_indices(pos + 1, 1)
  buffer.delete_tokens(pos)
  buffer.changed = true
  buffer.call_hooks(pos, 1)

proc insert_no_undo(buffer: Buffer, pos: int, str: seq[Rune]) =
  let
    before = buffer.text.substr(0, pos - 1)
    after = buffer.text.substr(pos)
  buffer.text = before & str & after
  buffer.reindex_lines()
  buffer.delete_tokens(pos)
  buffer.changed = true
  buffer.call_hooks(pos, str.len)

proc insert*(buffer: Buffer, pos: int, chr: Rune) =
  buffer.insert_no_undo(pos, chr)
  buffer.undo_frame().add(Action(kind: ActionInsert, insert_pos: pos, insert_text: @[chr]))
  buffer.redo_stack = @[]
  
proc insert*(buffer: Buffer, pos: int, str: seq[Rune]) =
  buffer.insert_no_undo(pos, str)
  buffer.undo_frame().add(Action(kind: ActionInsert, insert_pos: pos, insert_text: str))
  buffer.redo_stack = @[]

proc replace*(buffer: Buffer, start, stop: int, text: seq[Rune]) =
  let
    deleted_text = buffer.text.substr(start, stop - 1)
    before = buffer.text.substr(0, start - 1)
    after = buffer.text.substr(stop)

  buffer.text = before & text & after  
  buffer.delete_tokens(start)
  buffer.reindex_lines()
  buffer.changed = true

  buffer.call_hooks(stop, text.len - deleted_text.len)
  
  buffer.undo_frame().add(Action(kind: ActionDelete, delete_pos: start, delete_text: deleted_text))
  buffer.undo_frame().add(Action(kind: ActionInsert, insert_pos: start, insert_text: text))

proc insert_newline*(buffer: Buffer, pos: int) =
  let
    before = buffer.text.substr(0, pos - 1)
    after = buffer.text.substr(pos)
  buffer.text = before & '\n' & after
  buffer.reindex_lines()
  buffer.delete_tokens(pos)
  buffer.changed = true
  buffer.call_hooks(pos, 1)

  buffer.undo_frame().add(Action(kind: ActionInsert, insert_pos: pos, insert_text: @[Rune('\n')]))
  buffer.redo_stack = @[]

proc range_lines(buffer: Buffer, start, stop: int): seq[int] =
  for it, line in buffer.lines:
    if line >= stop:
      if result.len == 0 and it > 0:
        result.add(it - 1)
      break
    if line >= start:
      if result.len == 0 and it > 0 and start != line: 
        result.add(it - 1)
      result.add(it)

  if result.len == 0 and buffer.lines.len != 0:
    result.add(buffer.lines.len - 1)

proc line_range*(buffer: Buffer, line: int): (int, int) =
  if line < 0 or line >= buffer.lines.len:
    return (-1, -1)
  var it = buffer.lines[line]
  while it < buffer.text.len:
    if buffer.text[it] == '\n':
      it += 1
      break
    it += 1
  return (buffer.lines[line], it)

proc is_indented(buffer: Buffer, pos: int): bool =
  case buffer.indent_style:
    of IndentSpaces:
      if pos + buffer.indent_width - 1 >= buffer.len:
        return false
      
      for it in 0..<buffer.indent_width:
        if buffer.text[it + pos] != ' ':
          return false
      return true
    of IndentTab:
      if pos >= buffer.len:
        return false
      return buffer.text[pos] == '\t'
  
proc unindent_line*(buffer: Buffer, line: int) =
  let pos = buffer.lines[line]
  if not buffer.is_indented(pos):
    return
  case buffer.indent_style:
    of IndentSpaces:
      buffer.delete(pos, pos + buffer.indent_width)
    of IndentTab:
      buffer.delete(pos, pos + 1)

proc unindent*(buffer: Buffer, start, stop: int) =
  for line_index in buffer.range_lines(start, stop):
    buffer.unindent_line(line_index)

proc indent*(buffer: Buffer, pos: int) =
  case buffer.indent_style:
    of IndentSpaces:
      buffer.insert(pos, sequtils.repeat(Rune(' '), buffer.indent_width))
    of IndentTab:
      buffer.insert(pos, Rune('\t'))

proc indent_line(buffer: Buffer, line: int) =
  buffer.indent(buffer.lines[line])

proc indent*(buffer: Buffer, start, stop: int) =
  for line_index in buffer.range_lines(start, stop):
    buffer.indent_line(line_index)

proc match_bracket(buffer: Buffer, pos, delta: int, open_chr, close_chr: Rune): int =
  if pos >= buffer.len:
    return -1
  var
    it = pos
    depth = 0
  while it >= 0 and it < buffer.len:
    if buffer.text[it] == open_chr:
      depth += 1
    elif buffer.text[it] == close_chr:
      depth -= 1
      if depth == 0:
        return it
    it += delta
  return -1
  
proc match_bracket*(buffer: Buffer, pos: int): int = 
  if pos >= buffer.len:
    return -1
  
  let chr = buffer.text[pos]
  case chr:
    of '(': return buffer.match_bracket(pos, 1, '(', ')')
    of ')': return buffer.match_bracket(pos, -1, ')', '(')
    of '{': return buffer.match_bracket(pos, 1, '{', '}')
    of '}': return buffer.match_bracket(pos, -1, '}', '{')
    of '[': return buffer.match_bracket(pos, 1, '[', ']')
    of ']': return buffer.match_bracket(pos, -1, ']', '[')
    else: return -1

proc skip*(buffer: Buffer, pos: int, dir: int): int =
  if buffer.text.len == 0:
    return 0

  result = pos.max(0).min(buffer.text.len - 1)
  
  let v = buffer.text[result].is_alpha_numeric()
  while result >= 0 and
        result < buffer.text.len and
        buffer.text[result].is_alpha_numeric() == v:
    result += dir

proc word_range*(buffer: Buffer, pos: int): (int, int) =
  return (buffer.skip(pos, -1) + 1, buffer.skip(pos, 1))

proc pop_non_empty[T](stack: var seq[seq[T]]): seq[T] =
  while result.len == 0:
    result = stack.pop()

proc redo*(buffer: Buffer) =
  if buffer.redo_stack.len == 0:
    return
  let frame = buffer.redo_stack.pop_non_empty()
  buffer.undo_stack.add(frame)
  for action in frame:
    case action.kind:
      of ActionInsert: 
        buffer.insert_no_undo(action.insert_pos, action.insert_text)
      of ActionDelete:
        buffer.delete_no_undo(
          action.delete_pos,
          action.delete_pos + action.delete_text.len
        )

proc undo*(buffer: Buffer) =
  if buffer.undo_stack.len == 0:
    return
  let frame = buffer.undo_stack.pop_non_empty()
  buffer.redo_stack.add(frame)
  for it in countdown(frame.len - 1, 0):
    let action = frame[it]
    case action.kind:
      of ActionDelete:
        buffer.insert_no_undo(action.delete_pos, action.delete_text)
      of ActionInsert:
        buffer.delete_no_undo(
          action.insert_pos,
          action.insert_pos + action.insert_text.len
        )

proc finish_undo_frame*(buffer: Buffer) =
  if buffer.undo_stack.len == 0:
    return 
  if buffer.undo_stack[buffer.undo_stack.len - 1].len > 0:
    buffer.undo_stack.add(@[])

proc to_runes*(newline_style: NewlineStyle): seq[Rune] =
  case newline_style:
    of NewlineLf: return @[Rune('\n')]
    of NewlineCrLf: return @[Rune('\r'), Rune('\n')]

proc guess_indent_width(text: seq[Rune]): int =
  var
    is_indent = true
    width = 0
    indents = init_table[int, int]()
  for it, chr in text:
    if chr == '\n':
      is_indent = true
      width = 0
      continue
    if chr != ' ':
      is_indent = false
      if width != 0:
        if not indents.has_key(width):
          indents[width] = 0
        indents[width] += 1

    if is_indent:
      width += 1  
  
  var 
    best = 2
    best_score = 0
  for indent_width in [8, 4, 2]:
    var score = 0
    for width, count in indents:
      if width mod indent_width == 0:
        score += count
    if score > best_score:
      best_score = score
      best = indent_width
  return best

proc guess_indent_style(text: seq[Rune]): IndentStyle =
  var
    is_indent = true
    scores: array[IndentStyle, int]
  for chr in text:
    case chr:
      of '\t':
        if is_indent:
          scores[IndentTab] += 1
      of ' ':
        if is_indent:
          scores[IndentSpaces] += 1
      of '\n': is_indent = true
      else: is_indent = false
  
  var max_score = 0
  result = IndentSpaces
  for style, score in scores.pairs:
    if score > max_score:
      result = style
      max_score = score

proc guess_newline_style(text: seq[Rune]): NewlineStyle =
  var
    is_cr = false
    scores: array[NewlineStyle, int]
  for it, chr in text:
    case chr:
      of '\r':
        is_cr = true
        continue
      of '\n':
        if is_cr:
          scores[NewlineCrLf].inc()
        else:  
          scores[NewlineLf].inc()
      else: discard
    is_cr = false
  
  var max_score = 0
  result = NewlineLf
  for style, score in scores.pairs:
    if score > max_score:
      result = style
      max_score = score

proc make_buffer*(): Buffer =
  return Buffer(
    file_path: "",
    text: @[],
    lines: @[0],
    changed: false,
    tokens: @[],
    tokens_done: false,
    language: nil,
    cursor_hooks: init_table[int, CursorHook](),
    indent_width: 2,
    indent_style: IndentSpaces,
    newline_style: NewlineLf
  )

proc make_buffer*(path: string, lang: Language = nil): Buffer =
  let
    text = to_runes(path.read_file())
    indent_style = text.guess_indent_style()
    newline_style = text.guess_newline_style()
  var indent_width = 2
  if indent_style == IndentSpaces:
    indent_width = text.guess_indent_width()
  elif not lang.is_nil:
    indent_width = lang.indent_width
  return Buffer(
    file_path: path,
    text: text,
    lines: text.index_lines(),
    changed: false,
    tokens: @[],
    tokens_done: false,
    language: lang,
    cursor_hooks: init_table[int, CursorHook](),
    indent_width: indent_width,
    indent_style: indent_style,
    newline_style: newline_style
  )

proc make_buffer*(path: string, langs: seq[Language]): Buffer =
  let lang = langs.detect_language(path)
  return make_buffer(path, lang = lang)
