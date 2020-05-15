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

import unicode, ../highlight/highlight
import ../buffer, ../utils

type
  Context = ref object of Autocompleter

method track(ctx: Context, buffer: Buffer) =
  discard

method complete*(ctx: Context,
                 buffer: Buffer,
                 pos: int,
                 trigger: Rune,
                 callback: proc (comps: seq[Completion])) =
  callback(@[])

method poll*(ctx: Context) = discard

method list_defs*(ctx: Context,
                  buffer: Buffer,
                  callback: proc (defs: seq[Definition])) =
  buffer.update_tokens()
  var defs: seq[Definition] = @[]
  for token in buffer.tokens:
    if token.kind != TokenHeading:
      continue
    defs.add(Definition(
      kind: DefHeading,
      name: buffer.text[token.start..(token.stop - 1)],
      pos: buffer.to_2d(token.start)
    ))
  callback(defs)

proc new_markdown_autocompleter*(): Autocompleter =
  Context()
