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

import unicode
import highlight, ../utils

type State = ref object of HighlightState
  it: int
  is_tag: bool
  is_close: bool

method next*(state: State, text: seq[Rune]): Token =
  var start = text.skip_whitespace(state.it)
  if start >= text.len:
    return Token(kind: TokenNone)  
  let chr = text[start]
  case chr:
    of '\n':
      let state = State(it: start + 1, is_tag: state.is_tag, is_close: state.is_close)
      return Token(kind: TokenUnknown, start: start, stop: start + 1, state: state, can_stop: true)
    of '\"':
      let
        it = text.skip_string_like(start + 1)
        state = State(it: it + 1)
      return Token(kind: TokenString, start: start, stop: it + 1, state: state)
    of '<', '>', '/', '=':
      var
        is_tag = false
        is_close = false
      case chr:
        of '<': is_tag = true
        of '/':
          is_tag = state.is_tag
          is_close = true
        else: discard
      let state = State(it: start + 1, is_tag: is_tag, is_close: is_close)
      return Token(kind: TokenUnknown, start: start, stop: start + 1, state: state)
    else:
      var
        name: seq[Rune] = @[]
        it = start
      while it < text.len:
        let chr = text[it]
        case chr:
          of ' ', '\t', '\n', '\r', '<', '>', '/', '=':
            break
          else:
            name.add(chr)
        it += 1
      var kind = TokenName
      if state.is_tag:
        if state.is_close:
          kind = TokenTagClose
        else:
          kind = TokenTag
      return Token(kind: kind, start: start, stop: it, state: State(it: it))

proc new_html_highlighter*(): HighlightState = State()
