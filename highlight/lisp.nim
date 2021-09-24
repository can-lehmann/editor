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
  is_call: bool
  is_quote: bool
  depth: int
  quote_depths: seq[int]

const
  LISP_KEYWORDS = [
    "let", "fn", "if", "cond", "case",
    "recur", "quote", "lambda", "import",
    "use", "require", "set!", "let*", "letrec",
    "begin", "progn", "do", "and", "or", "not",
    "throw", "try", "catch"
  ]

proc token_kind(name: seq[Rune], is_call: bool, is_quote: bool): TokenKind =
  if is_quote:
    return TokenLiteral
  elif name.is_int or name.is_float:
    return TokenLiteral
  elif $name in ["true", "false", "nil"]:
    return TokenLiteral
  elif startswith($name, "def"):
    return TokenKeyword
  elif $name in LISP_KEYWORDS:
    return TokenKeyword
  elif is_call:
    return TokenFunc
  return TokenName

method next*(state: State, text: seq[Rune]): Token =
  var start = text.skip_whitespace(state.it)
  if start >= text.len:
    return Token(kind: TokenNone)
  let chr = text[start]
  case chr:
    of '\n':
      let new_state = State(it: start + 1, depth: state.depth, quote_depths: state.quote_depths)
      return Token(kind: TokenUnknown, start: start, stop: start + 1, state: new_state, can_stop: true)
    of ';':
      var it = start + 1
      while it < text.len and text[it] != '\n':
        it += 1
      let new_state = State(it: it + 1, depth: state.depth, quote_depths: state.quote_depths)
      return Token(kind: TokenComment, start: start, stop: it + 1, state: new_state, can_stop: true)
    of '\"':
      let
        it = text.skip_string_like(start + 1)
        state = State(it: it + 1, quote_depths: state.quote_depths, depth: state.depth)
      return Token(kind: TokenString, start: start, stop: it + 1, state: state)
    of '\'', ':':
      let new_state = State(it: start + 1, is_quote: true, quote_depths: state.quote_depths, depth: state.depth)
      return Token(kind: TokenLiteral, start: start, stop: start + 1, state: new_state)
    of '(', '[', '{':
      var
        quote_depths = state.quote_depths
        kind = TokenUnknown
      if state.is_quote:
        quote_depths.add(state.depth + 1)
        kind = TokenLiteral
      let new_state = State(
        it: start + 1,
        is_call: true,
        depth: state.depth + 1,
        quote_depths: quote_depths
      )
      return Token(kind: kind, start: start, stop: start + 1, state: new_state)
    of ')', ']', '}':
      var
        quote_depths = state.quote_depths
        kind = TokenUnknown
      if quote_depths.len > 0 and quote_depths[^1] == state.depth:
        discard quote_depths.pop()
        kind = TokenLiteral
      let new_state = State(it: start + 1, depth: state.depth - 1, quote_depths: quote_depths)
      return Token(kind: kind, start: start, stop: start + 1, state: new_state)
    else:
      var
        name: seq[Rune] = @[]
        it = start
      while it < text.len:  
        let chr = text[it]
        case chr:
          of '\n', '\t', '\r', ' ', '(', ')', '\"', '\'', '{', '}', '[', ']':
            break
          else:
            name &= chr
        it += 1
      let
        kind = name.token_kind(state.is_call, state.is_quote)
        new_state = State(it: it, depth: state.depth, quote_depths: state.quote_depths)
      return Token(kind: kind, start: start, stop: it, state: new_state)

proc new_lisp_highlighter*(): HighlightState = State()
