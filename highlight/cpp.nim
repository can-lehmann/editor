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

import unicode
import highlight, ../utils

type
  Mode = enum ModeNone, ModePreprocessor

  State = ref object of HighlightState
    it: int
    mode: Mode

const
  CPP_KEYWORDS = [
    "struct", "class", "public", "private", "protected",
    "union", "if", "else", "while", "for", "template",
    "typedef", "typename", "throw", "try", "catch", "finally",
    "extern", "return", "using", "namespace", "inline",
    "static", "new", "operator", "delete"
  ]
  CPP_TYPES = [
    "int", "char", "short", "unsigned", "signed", "bool",
    "long", "void", "auto", "const", "float", "double"
  ]

proc is_constant(str: seq[Rune]): bool =
  for it, chr in str:
    if int(chr) >= ord('A') and int(chr) <= ord('Z'):
      continue
    if chr == '_':
      continue
    return false
  return true

proc token_kind(str: seq[Rune]): TokenKind =
  if $str in CPP_KEYWORDS:
    return TokenKeyword
  elif $str in CPP_TYPES:
    return TokenType
  elif $str in ["true", "false", "nullptr", "NULL"]:
    return TokenLiteral
  elif str.is_int(allow_underscore=false):
    return TokenLiteral
  elif str.is_constant() and str.len > 1:
    return TokenLiteral
  return TokenName

method next(state: State, text: seq[Rune]): Token =
  case state.mode:
    of ModePreprocessor:
      let start = text.skip(state.it, {' ', '\r', '\t'})
      if start >= text.len:
        return Token(kind: TokenNone)  
      let chr = text[start]
      case chr:
        of '\n':
          let state = State(it: start + 1)
          return Token(kind: TokenUnknown, start: start, stop: start + 1, state: state)
        of '\"':
          let
            it = text.skip_string_like(start + 1, end_char='\"')
            state = State(it: it + 1, mode: ModePreprocessor)
          return Token(kind: TokenString, start: start, stop: it + 1, state: state)
        of '<':
          let
            it = text.skip_string_like(start + 1, end_char='>')
            state = State(it: it + 1, mode: ModePreprocessor)
          return Token(kind: TokenString, start: start, stop: it + 1, state: state)
        of ':', '>', '[', ']', '(', ')',
           '{', '}', ',', ';', '=', '`', '.',
           '+', '-', '*', '/', '&',
           ' ', '\t', '\r':
          let state = State(it: start + 1, mode: ModePreprocessor)
          return Token(kind: TokenUnknown, start: start, stop: start + 1, state: state)
        else:
          var
            name: seq[Rune] = @[]
            it = start
          while it < text.len:
            case text[it]:
              of ':', '<', '>', '[', ']', '(', ')',
                 '{', '}', ',', ';', '=', '`', '.',
                 '+', '-', '*', '/', '&',
                 ' ', '\n', '\t', '\r':
                break
              else: name.add(text[it])
            it += 1
          let state = State(it: it, mode: ModePreprocessor)
          return Token(kind: TokenKeyword, start: start, stop: it, state: state)
    of ModeNone:
      let start = text.skip_whitespace(state.it)
      if start >= text.len:
        return Token(kind: TokenNone)  
      let chr = text[start]
      template skip_chr() =
        let state = State(it: start + 1)
        return Token(kind: TokenUnknown, start: start, stop: start + 1, state: state)
      case chr:
        of '\"', '\'':
          let
            it = text.skip_string_like(start + 1, end_char=chr)
            state = State(it: it + 1)
          return Token(kind: TokenString, start: start, stop: it + 1, state: state)
        of '#':
          let state = State(it: start + 1, mode: ModePreprocessor)
          return Token(kind: TokenKeyword, start: start, stop: start + 1, state: state)
        of ':', '<', '>', '[', ']', '(', ')',
           '{', '}', ',', ';', '=', '`', '.',
           '+', '-', '*', '&':
          skip_chr()
        of '/':
          if start + 1 >= text.len:
            skip_chr()
          case text[start + 1]:
            of '/':
              var it = start + 2
              while it < text.len and text[it] != '\n':
                it += 1
              let state = State(it: it + 1)
              return Token(kind: TokenComment, start: start, stop: it + 1, state: state)
            of '*':
              var it = start + 2
              while it + 1 < text.len and
                    (text[it] != '*' or
                     text[it + 1] != '/'):
                it += 1
              let state = State(it: it + 2)
              return Token(kind: TokenComment, start: start, stop: it + 2, state: state)
            else: skip_chr()
        else:
          var
            name: seq[Rune] = @[]
            it = start
          while it < text.len:
            case text[it]:
              of ':', '<', '>', '[', ']', '(', ')',
                 '{', '}', ',', ';', '=', '`', '.',
                 '+', '-', '*', '/', '&',
                 ' ', '\n', '\t', '\r':
                break
              else: name.add(text[it])
            it += 1
          let
            kind = name.token_kind()
            state = State(it: it)
          return Token(kind: kind, start: start, stop: it, state: state)

proc new_cpp_highlighter*(): HighlightState = State()
