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

import unicode, strutils, os, tables, sets, hashes, streams, sugar, sequtils
import ../buffer, ../utils, ../log, autocomplete, ../highlight/highlight

type Context = ref object of Autocompleter
  log: Log
  max_symbols: int
  symbols: Table[Buffer, seq[Symbol]]

proc hash(buffer: Buffer): Hash = hash(buffer[].addr)

proc parse_defs(buffer: Buffer): seq[Symbol] =
  buffer.update_tokens()
  for it in 1..<buffer.tokens.len:
    if buffer.tokens[it - 1].kind == TokenKeyword and
       buffer.tokens[it].kind == TokenName:
      let
        keyword_token = buffer.tokens[it - 1]
        keyword = $buffer.text[keyword_token.start..<keyword_token.stop]
        name_token = buffer.tokens[it]
        name = buffer.text[name_token.start..<name_token.stop]
        kind = case keyword:
          of "proc": SymProc
          of "method": SymMethod
          of "template": SymTemplate
          of "func": SymFunc
          of "macro": SymMacro
          of "iterator": SymIterator
          of "converter": SymConverter
          else: SymNone
      if kind != SymNone:
        result.add(Symbol(kind: kind,
          name: name,
          pos: buffer.to_2d(name_token.start)
        ))

method track*(ctx: Context, buffer: Buffer) =
  ctx.symbols[buffer] = buffer.parse_defs()

method complete*(ctx: Context,
                 buffer: Buffer,
                 pos: int,
                 trigger: Rune,
                 callback: proc (comps: seq[Symbol])) =
  let query = ctx.extract_query(buffer, pos)
  var comps: seq[Symbol] = @[]
  if buffer in ctx.symbols:
    for symbol in ctx.symbols[buffer]:
      if query in symbol.name:
        comps.add(symbol)
  callback(comps)

method poll*(ctx: Context) =
  discard

method close*(ctx: Context) =
  discard

method list_defs*(ctx: Context,
                  buffer: Buffer,
                  callback: proc (defs: seq[Symbol])) =
  let defs = buffer.parse_defs()
  ctx.symbols[buffer] = defs
  callback(defs)

proc make_nim_autocompleter*(log: Log): Autocompleter =
  Context(
    log: log,
    max_symbols: 2048,
    triggers: @[
      Rune('.'), Rune('('), Rune('[')
    ],
    finish: @[
      Rune(' '), Rune('\n'), Rune('\r'), Rune('\t'),
      Rune('+'), Rune('-'), Rune('*'), Rune('/'),
      Rune(','), Rune(';'),
      Rune('='), Rune('>'), Rune('<'),
      Rune('@'),
      Rune(')'), Rune('}'), Rune(']'), Rune('{')
    ],
    min_word_len: 5,
  )
