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

import sequtils, strutils, os, sugar, streams, deques, unicode, tables
import "../utils", "../termdiff"

type
  HighlightState* = ref object of RootObj
  
  TokenKind* = enum
    TokenNone,
    TokenString, TokenChar, TokenLiteral,
    TokenType, TokenComment, TokenName, TokenKeyword,
    TokenFunc, TokenUnknown

  Token* = object
    kind*: TokenKind
    start*: int
    stop*: int
    state*: HighlightState

method next*(state: HighlightState, text: seq[Rune]): Token {.base.} = quit "Abstract"

proc is_inside*(token: Token, index: int): bool =
  index >= token.start and index < token.stop

proc is_whitespace*(rune: Rune): bool =
  rune == ' ' or rune == '\t' or rune == '\r' or rune == '\n'

proc skip_whitespace*(text: seq[Rune], pos: int): int =
  result = pos
  while result < text.len and text[result].is_whitespace():
    result += 1

proc skip_string_like*(text: seq[Rune],
                       pos: int,
                       end_char: Rune = '\"',
                       escape_char: Rune = '\\'): int =
  result = pos
  while result < text.len and text[result] != end_char:
    if text[result] == escape_char:
      result += 1 
    result += 1

proc is_int*(str: seq[Rune], allow_underscore: bool = false): bool =
  for it, chr in str:
    if not ((chr.int64 >= 0 and chr.int64 <= 127 and char(chr).is_digit) or
            (chr == '_' and allow_underscore) or
            (chr == '+' and it == 0 and str.len > 1) or
            (chr == '-' and it == 0 and str.len > 1)):
      return false
  return true

proc is_float*(str: seq[Rune], allow_underscore: bool = false): bool =
  var point = false
  for it, chr in str:
    if not ((chr.int64 >= 0 and chr.int64 <= 127 and char(chr).is_digit) or
            (chr == '_' and allow_underscore) or
            (chr == '+' and it == 0 and str.len > 1) or
            (chr == '-' and it == 0 and str.len > 1)):
      if chr == '.' and not point and str.len > 1:
        point = true
      else:
        return false
  return true

proc color*(token: Token): Color =
  case token.kind:
    of TokenString, TokenChar: return Color(base: ColorGreen, bright: true)
    of TokenKeyword: return Color(base: ColorRed, bright: true)
    of TokenComment: return Color(base: ColorBlue, bright: false)
    of TokenLiteral: return Color(base: ColorYellow, bright: false)
    of TokenType: return Color(base: ColorCyan, bright: true)
    else: return Color(base: ColorDefault, bright: false)
