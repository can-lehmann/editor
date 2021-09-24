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

import strutils, unicode
import highlight, ../utils.nim

type
  State = ref object of HighlightState
    it: int

proc token_kind(name: seq[Rune]): TokenKind =
  if $name == "true" or $name == "false" or $name == "null":
    return TokenLiteral
  elif name.is_int() or name.is_float():
    return TokenLiteral
  return TokenUnknown

method next(state: State, text: seq[Rune]): Token =
  let start = text.skip_whitespace(state.it)
  if start >= text.len:
    return Token(kind: TokenNone)
  let chr = text[start]
  case chr:
    of '\"':
      let
        stop = text.skip_string_like(start + 1, end_char = chr)
        state = State(it: stop + 1)
      return Token(kind: TokenString, start: start, stop: stop + 1, state: state)
    of ':', ',', '[', ']', '{', '}', '\n':
      let state = State(it: start + 1)
      return Token(kind: TokenUnknown, start: start, stop: start + 1, state: state, can_stop: true)
    else:
      var
        name: seq[Rune] = @[]
        it = start
      while it < text.len:
        case text[it]:
          of ':', ',', '[', ']', '{', '}', ' ', '\t', '\r', '\n':
            break
          else:
            name.add(text[it])
        it += 1
      let state = State(it: it)
      return Token(kind: token_kind(name), start: start, stop: it, state: state)

proc new_json_highlighter*(): HighlightState = State(it: 0)
