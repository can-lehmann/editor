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
import ../buffer, ../utils, ../highlight/highlight, ../log

type Context = ref object of Autocompleter
  log: Log

method track(ctx: Context, buffer: Buffer) = discard
method poll(ctx: Context) = discard
method close(ctx: Context) = discard
method complete(ctx: Context,
                buffer: Buffer,
                pos: int,
                trigger: Rune,
                callback: proc (comps: seq[Completion])) =
  callback(@[])

method list_defs(ctx: Context,
                 buffer: Buffer,
                 callback: proc(defs: seq[Definition])) =
  buffer.update_tokens()
  var defs: seq[Definition]
  for it in 1..<buffer.tokens.len:
    let
      keyword = buffer.tokens[it - 1]
      name = buffer.tokens[it]
    if keyword.kind == TokenKeyword and
       $buffer.text[keyword.start..<keyword.stop] == "function" and
       name.kind == TokenName:
      defs.add(Definition(
        kind: DefFunc,
        name: buffer.text[name.start..<name.stop],
        pos: buffer.to_2d(keyword.start)
      ))
  callback(defs)

proc new_lua_autocompleter*(log: Log): Autocompleter =
  return Context(log: log)
