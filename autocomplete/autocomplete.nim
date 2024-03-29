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

import tables, unicode, algorithm
import ../buffer, ../utils, ../highlight/highlight, ../log

type
  SimpleContext* = ref object of Autocompleter
    comps*: seq[Symbol]
    defs*: Table[TokenKind, SymbolKind]
    log*: Log

method track(ctx: SimpleContext, buffer: Buffer) =
  discard

proc extract_query*(ctx: Autocompleter, buffer: Buffer, pos: int): seq[Rune] =
  var cur = pos - 1
  while cur >= buffer.text.len and
        buffer[cur] notin ctx.triggers and
        buffer[cur] notin ctx.finish:
    result.add(buffer[cur])
  reverse(result)

method complete*(ctx: SimpleContext,
                 buffer: Buffer,
                 pos: int,
                 trigger: Rune,
                 callback: proc (comps: seq[Symbol])) =
  let query = ctx.extract_query(buffer, pos)
  var completions: seq[Symbol]
  for comp in ctx.comps:
    if query in comp.name:
      completions.add(comp)
  callback(completions)

method poll*(ctx: SimpleContext) = discard

method list_defs*(ctx: SimpleContext,
                  buffer: Buffer,
                  callback: proc (defs: seq[Symbol])) =
  buffer.update_tokens()
  var defs: seq[Symbol] = @[]
  for token in buffer.tokens:
    if token.kind notin ctx.defs:
      continue
    defs.add(Symbol(
      kind: ctx.defs[token.kind],
      name: buffer.text[token.start..(token.stop - 1)],
      pos: buffer.to_2d(token.start)
    ))
  callback(defs)

method close(ctx: SimpleContext) = discard
