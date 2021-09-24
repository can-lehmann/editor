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
import highlight, ../utils

type
  Mode = enum ModeRules, ModeProperties
  State = ref object of HighlightState
    it: int
    mode: Mode

proc is_unit(name: seq[Rune], unit: string): bool =
  ends_with($name, unit) and is_float(name[0..^(1 + unit.len)])

proc is_unit(name: seq[Rune], units: openArray[string]): bool =
  for unit in units:
    if name.is_unit(unit):
      return true

proc is_color(name: seq[Rune]): bool =
  if name.len == 0 or name[0] != '#':
    return false
  for it in 1..<name.len:
    if name[it] notin '0'..'9' and
       name[it] notin 'a'..'f' and
       name[it] notin 'A'..'F':
      return false
  return true

const UNITS = ["px", "%", "em", "rem", "vw", "vh", "mm", "cm", "in", "pt", "s"]

proc token_kind(name: seq[Rune], mode: Mode): TokenKind =
  case mode:
    of ModeRules:
      if starts_with($name, '.'):
        return TokenClass
      elif starts_with($name, '#'):
        return TokenId
      return TokenTag
    of ModeProperties:
      if name.is_float() or is_unit(name, UNITS):
        return TokenLiteral
      elif name.is_color():
        return TokenLiteral
      return TokenName

method next(state: State, text: seq[Rune]): Token =
  var start = text.skip_whitespace(state.it)
  if start >= text.len:
    return Token(kind: TokenNone)
  
  template char_token(new_state) =
    return Token(kind: TokenUnknown,
      start: start, stop: start + 1, state: new_state, can_stop: true
    )
  
  template skip_token() =
    char_token(State(mode: state.mode, it: start + 1))
  
  let chr = text[start]
  case chr:
    of '{':
      if state.mode == ModeRules:
        char_token(State(it: start + 1, mode: ModeProperties))
      else:
        skip_token()
    of '}':
      if state.mode == ModeProperties:
        char_token(State(it: start + 1, mode: ModeRules))
      else:
        skip_token()
    of '\"', '\'':
      let
        it = text.skip_string_like(start + 1, end_char = text[start])
        state = State(it: it + 1, mode: state.mode)
      return Token(kind: TokenString, start: start, stop: it + 1, state: state)
    else:
      var
        name: seq[Rune]
        it = start
      while it < text.len:
        case text[it]:
          of ' ', '\n', '\t', '\r', '{', '}', '(', ')', '<', '>', ';', ',':
            break
          of ':':
            if state.mode == ModeProperties or name.len > 0:
              break
          of '.':
            if name.len > 0 and state.mode == ModeRules:
              break
          else: discard
        name.add(text[it])
        it += 1
      if name.len == 0:
        skip_token()
      return Token(kind: token_kind(name, state.mode),
        start: start, stop: it,
        state: State(mode: state.mode, it: it)
      )

proc new_css_highlighter*(): HighlightState = State()
