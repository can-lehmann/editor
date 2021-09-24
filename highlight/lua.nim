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

import unicode, strutils
import ../utils, highlight

type State = ref object of HighlightState
  it: int

const
  KEYWORDS = [
    "if", "then", "elseif", "else", "end", "for", "in",
    "do", "while", "function", "return", "break", "goto",
    "local", "require"
  ]

proc token_kind(name: seq[Rune]): TokenKind =
  if $name in KEYWORDS:
    return TokenKeyword
  elif name.is_int or name.is_float:
    return TokenLiteral
  elif ($name).starts_with("::") and ($name).ends_with("::"):
    return TokenLiteral
  return TokenName

method next*(state: State, text: seq[Rune]): Token =
  var start = text.skip_whitespace(state.it)
  if start >= text.len:
    return Token(kind: TokenNone)

  if text.pattern_at("--", start):
    var it = start + 2
    while it < text.len and text[it] != '\n':
      it += 1
    return Token(kind: TokenComment, start: start, stop: it, state: State(it: it + 1))
  
  let chr = text[start]
  case chr:
    of '\"', '\'':
      let
        it = text.skip_string_like(start + 1, end_char = text[start])
        state = State(it: it + 1)
      return Token(kind: TokenString, start: start, stop: it + 1, state: state)
    else:
      var
        it = start
        name: seq[Rune]
      while it < text.len:
        let chr = text[it]
        case chr:
          of ' ', '\n', '\t', '(', ')', '[', ']', '{', '}',
             '+', '-', '*', '/', '=', '.', ',', ';', '#':
            break
          else:
            name.add(chr)
            it += 1
      if name.len == 0:
        return Token(kind: TokenUnknown, start: start, stop: it + 1, state: State(it: it + 1))
      return Token(kind: name.token_kind, start: start, stop: it, state: State(it: it + 1))

proc new_lua_highlighter*(): HighlightState = State()
