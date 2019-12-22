# MIT License
# 
# Copyright (c) 2019 pseudo-random <josh.leh.2018@gmail.com>
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

import utils, highlight, strutils

type
  Buffer* = ref object
    file_path*: string
    text*: string
    lines*: seq[int]
    changed*: bool
    tokens*: seq[Token]
    tokens_done*: bool
    language*: Language

proc update_tokens*(buffer: Buffer) =
  buffer.tokens = @[]
  buffer.tokens_done = true
  
  if buffer.language == nil:
    return
  
  var iter = buffer.language.highlighter(buffer.text, 0)
  for token in iter():
    buffer.tokens.add(token)
  

proc delete_tokens*(buffer: Buffer, start: int) =
  while buffer.tokens.len > 0 and
        buffer.tokens[buffer.tokens.len - 1].stop >= start:
    discard buffer.tokens.pop()
  buffer.tokens_done = false
  
proc get_token*(buffer: Buffer, index: int): Token =
  if index < buffer.tokens.len:
    return buffer.tokens[index]  
  
  if buffer.tokens_done or buffer.language == nil:
    return Token(kind: TokenNone, start: -1, stop: -1)

  var initial = 0  
  if buffer.tokens.len > 0:
    initial = buffer.tokens[buffer.tokens.len - 1].stop
  
  var
    iter = buffer.language.highlighter(buffer.text, initial)
    it = 0

  for token in iter():
    buffer.tokens.add(token)
    if it == index:
      return token
    it += 1
  
  return Token(kind: TokenNone, start: -1, stop: -1)

proc index_lines*(text: string): seq[int] =
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

proc to_index*(buffer: Buffer, pos: Index2d): int =
  result = pos.x + buffer.lines[pos.y]
  
  if pos.y + 1 >= buffer.lines.len:
    return max(buffer.text.len, result)
  
  if result >= buffer.lines[pos.y + 1]:
    result = buffer.lines[pos.y + 1] - 1

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

proc display_file_name*(buffer: Buffer): string =
  if buffer.file_name == "":
    return "*Untitled file*"
  
  result = buffer.file_name

  if buffer.changed:
    result &= "*"
    
  if buffer.language != nil:
    result &= " (" & buffer.language.name & ")"
  else:
    result &= " (Text)"

proc save*(buffer: Buffer) =
  write_file(buffer.file_path, buffer.text)
  buffer.changed = false

proc indentation*(buffer: Buffer, pos: int): int =
  var it = pos - 1
  while it >= 0 and buffer.text[it] != '\n':
    it -= 1
  result = 0
  it += 1
  while it < buffer.text.len and
        buffer.text[it] == ' ' and
        it < pos:
    result += 1
    it += 1

proc insert*(buffer: Buffer, pos: int, chr: char) =
  let
    before = buffer.text.substr(0, pos - 1)
    after = buffer.text.substr(pos)
  buffer.text = before & chr & after
  buffer.update_line_indices(pos + 1, 1)
  buffer.delete_tokens(pos)
  buffer.changed = true

proc insert*(buffer: Buffer, pos: int, str: string) =
  let
    before = buffer.text.substr(0, pos - 1)
    after = buffer.text.substr(pos)
  buffer.text = before & str & after
  buffer.reindex_lines()
  buffer.delete_tokens(pos)
  buffer.changed = true

proc insert_newline*(buffer: Buffer, pos: int) =
  let
    before = buffer.text.substr(0, pos - 1)
    after = buffer.text.substr(pos)
  buffer.text = before & '\n' & after
  buffer.reindex_lines()
  buffer.delete_tokens(pos)
  buffer.changed = true

proc skip*(buffer: Buffer, pos: int, dir: int): int =
  result = pos.max(0).min(buffer.text.len - 1)
  
  let v = buffer.text[result].is_alpha_numeric()
  while result >= 0 and
        result < buffer.text.len and
        buffer.text[result].is_alpha_numeric() == v:
    result += dir

proc make_buffer*(): Buffer =
  return Buffer(
    file_path: "",
    text: "",
    lines: @[0],
    changed: false,
    tokens: @[],
    tokens_done: false,
    language: nil,
  )
  
proc make_buffer*(path: string, lang: Language = nil): Buffer =
  let text = path.read_file()
  return Buffer(
    file_path: path,
    text: text,
    lines: text.index_lines(),
    changed: false,
    tokens: @[],
    tokens_done: false,
    language: lang,
  )

proc make_buffer*(path: string, langs: seq[Language]): Buffer =
  let lang = langs.detect_language(path)
  return make_buffer(path, lang = lang)
