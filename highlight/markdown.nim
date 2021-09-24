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

import strutils, sequtils, sugar
import unicode except is_whitespace
import ../utils, highlight

type
  State = ref object of HighlightState
    it: int
    is_newline: bool
    is_italic: bool
    is_bold: bool

proc token_kind(state: State): TokenKind =
  if state.is_bold:
    return TokenBold
  elif state.is_italic:
    return TokenItalic
  return TokenUnknown

method next(state: State, text: seq[Rune]): Token =
  let start = text.skip_whitespace(state.it)
  if start >= text.len:
    return Token(kind: TokenNone)  
  let chr = text[start]
  
  template skip_char() =
    let state = State(it: start + 1, is_bold: state.is_bold, is_italic: state.is_italic)
    return Token(kind: state.token_kind(), start: start, stop: start + 1, state: state) 

  case chr:
    of '#':
      var cur = start
      while cur < text.len and text[cur] != '\n':
        cur += 1
      let state = State(it: cur)
      return Token(kind: TokenHeading, start: start, stop: cur, state: state)
    of '>':
      var cur = start
      while cur < text.len and text[cur] != '\n':
        cur += 1
      let state = State(it: cur)
      return Token(kind: TokenComment, start: start, stop: cur, state: state)
    of '`':
      var cur = start + 1
      while cur < text.len and text[cur] != '`':
        cur += 1
      let state = State(it: cur + 1)
      return Token(kind: TokenCode, start: start, stop: cur + 1, state: state)
    of '\n':
      let state = State(it: start + 1, is_newline: true)
      return Token(kind: TokenUnknown, start: start, stop: start + 1, state: state, can_stop: true) 
    of '-':
      if not state.is_newline:
        skip_char()
      if start + 2 < text.len and text[start + 1] == '-' and text[start + 2] == '-':
        let state = State(it: start + 3)
        return Token(kind: TokenFormatting, start: start, stop: start + 3, state: state)
      elif start + 1 < text.len and text[start + 1] == ' ':
        let state = State(it: start + 2)
        return Token(kind: TokenFormatting, start: start, stop: start + 2, state: state)
      else:
        skip_char()
    of '*', '_':
      if state.is_newline and chr == '*':
        if start + 1 < text.len and text[start + 1] == ' ':
          return Token(
            kind: TokenList,
            start: start,
            stop: start + 1,
            state: State(it: start + 1)
          )
        elif start + 4 < text.len and
             text[start + 1] == chr and
             text[start + 2] == chr and
             text[start + 3] == '\n':
          return Token(
            kind: TokenList,
            start: start,
            stop: start + 4,
            state: State(it: start + 4, is_newline: true)
          )
      
      let new_state = State(it: start + 1, is_bold: state.is_bold, is_italic: state.is_italic)
      var stop = start + 1
      if start + 1 < text.len and text[start + 1] == chr:
        new_state.is_bold = not new_state.is_bold
        stop = start + 2
      else:
        new_state.is_italic = not new_state.is_italic
      new_state.it = stop
      return Token(kind: TokenUnknown, start: start, stop: stop, state: new_state)
    of '[':
      var cur = start + 1
      while cur < text.len and text[cur] != ']':
        if text[cur] == '\n':
          skip_char()
        cur += 1
      cur += 1
      while cur < text.len and text[cur] != '(':
        if not text[cur].is_whitespace or text[cur] == '\n':
          skip_char()
        cur += 1
      if cur >= text.len:
        skip_char()
      let link_start = cur + 1
      while cur < text.len and text[cur] != ')':
        if text[cur] == '\n':
          skip_char()
        cur += 1
      let new_state = State(it: cur + 1, is_bold: state.is_bold, is_italic: state.is_italic)
      return Token(kind: TokenLink, start: link_start, stop: cur, state: new_state)
    else:
      skip_char()

proc new_markdown_highlighter*(): HighlightState =
  State()
