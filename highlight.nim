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

import sequtils, strutils, os, sugar, streams, deques, unicode
import utils, termdiff

type
  TokenKind* = enum TokenKeyword, TokenString, TokenChar, TokenLiteral, TokenType, TokenComment, TokenName, TokenNone

  Token* = object
    kind*: TokenKind
    start*: int
    stop*: int
    
  Language* = ref object
    name*: string
    highlighter*: proc (text: seq[Rune], initial: int): (iterator (): Token {.closure.}) 
    file_exts*: seq[string]
    
const
  NIM_KEYWORDS = [
    # Converted from https://nim-lang.org/docs/manual.html
    "addr", "and", "as", "asm", "bind", "block",
    "break", "case", "cast", "concept", "const", "continue",
    "converter", "defer", "discard", "distinct", "div", "do",
    "elif", "else", "end", "enum", "except", "export", "finally",
    "for", "from", "func", "if", "import", "in", "include",
    "interface", "is", "isnot", "iterator", "let", "macro",
    "method", "mixin", "mod", "nil", "not", "notin", "object",
    "of", "or", "out", "proc", "ptr", "raise", "ref", "return",
    "shl", "shr", "static", "template", "try", "tuple", "type",
    "using", "var", "when", "while", "xor", "yield",
    
    "owned", "echo"
  ]
  
  NIM_TYPES = [
    "int", "int8", "int16", "int32", "int64",
    "byte", "uint8", "uint16", "uint32", "uint64",
    "float", "float64", "float32",
    "array", "string", "seq", "set", "tuple",
    "bool", "char", "auto", "pointer",
    "cint", "cshort", "cstring",
    "openArray", "Table", "Deque", "HashSet"
  ]

proc is_int(str: seq[Rune]): bool =
  for it, chr in str:
    if not (char(chr).is_digit or
            chr == '_' or
            (chr == '+' and it == 0 and str.len > 1) or
            (chr == '-' and it == 0 and str.len > 1)):
      return false
  return true

proc is_float(str: seq[Rune]): bool =
  var point = false
  for it, chr in str:
    if not (char(chr).is_digit or
            chr == '_' or
            (chr == '+' and it == 0 and str.len > 1) or
            (chr == '-' and it == 0 and str.len > 1)):
      if chr == '.' and not point:
        point = true
      else:
        return false
  return true

proc token_kind(str: seq[Rune]): TokenKind =
  if $str == "true" or $str == "false":
    return TokenLiteral
  elif $str in NIM_KEYWORDS:
    return TokenKeyword
  elif $str in NIM_TYPES:
    return TokenType
  elif str.is_int or str.is_float:
    return TokenLiteral
  
  return TokenName
      
proc tokenize_nim*(text: seq[Rune], initial: int): (iterator (): Token {.closure.}) =
  return iterator (): Token {.closure.} =
    type
      Mode = enum ModeNone, ModeString, ModeChar, ModeComment, ModeNestedComment 
    
    var
      start = 0
      cur: seq[Rune] = @[]
      mode: Mode = ModeNone
      depth = 0 
      it = initial
    while it < text.len:
      let chr = text[it]
      case mode:
        of ModeString:
          if chr == '\"':
            yield Token(kind: TokenString, start: start, stop: it + 1)
            mode = ModeNone
          elif chr == '\\':
            it += 1
        of ModeNestedComment:
          if chr == ']' and it + 1 < text.len and text[it + 1] == '#':
            it += 1
            depth -= 1
            if depth <= 0:
              yield Token(kind: TokenComment, start: start, stop: it + 1)
              mode = ModeNone
          elif chr == '#' and it + 1 < text.len and text[it + 1] == '[':
            it += 1
            depth += 1 
        of ModeComment:
          if chr == '\n':
            yield Token(kind: TokenComment, start: start, stop: it)
            mode = ModeNone
        of ModeChar:
          if chr == '\'':
            yield Token(kind: TokenChar, start: start, stop: it + 1)
            mode = ModeNone
          elif chr == '\\':
            it += 1
        of ModeNone:
          case chr:
            of ' ', '\t', '\n', '\r', '.', ':', '<', '>', '[', ']', '(', ')', '{', '}', ',', ';', '=', '`', '\"', '#', '\'':
              if cur.len > 0:
                yield Token(kind: token_kind(cur), start: start, stop: it)
                cur = @[]
              case chr:
                of '\"':
                  mode = ModeString
                  start = it
                of '\'':
                  mode = ModeChar
                  start = it
                of '#':
                  start = it
                  if it + 1 < text.len and text[it + 1] == '[':
                    mode = ModeNestedComment
                    depth = 1
                    it += 1
                  else:
                    mode = ModeComment
                else:
                  discard
            else:
              if cur.len == 0:
                start = it
              cur &= chr
      it += 1


    case mode:
      of ModeComment, ModeNestedComment:
        yield Token(kind: TokenComment, start: start, stop: it)
      of ModeChar:
        yield Token(kind: TokenChar, start: start, stop: it)
      of ModeString:
        yield Token(kind: TokenString, start: start, stop: it)
      else:          
        if cur.len > 0:
          yield Token(kind: token_kind(cur), start: start, stop: it)

proc is_inside*(token: Token, index: int): bool =
  index >= token.start and index < token.stop

proc color*(token: Token): Color =
  case token.kind:
    of TokenString, TokenChar: return Color(base: ColorGreen, bright: true)
    of TokenKeyword: return Color(base: ColorRed, bright: true)
    of TokenComment: return Color(base: ColorBlue, bright: false)
    of TokenLiteral: return Color(base: ColorYellow, bright: false)
    of TokenType: return Color(base: ColorCyan, bright: true)
    else: return Color(base: ColorDefault, bright: false)

proc detect_language*(langs: seq[Language], path: string): Language =
  let
    parts = path.split('.')
    ext = parts[parts.len - 1]
  for lang in langs:
    if ext in lang.file_exts:
      return lang
  return nil
