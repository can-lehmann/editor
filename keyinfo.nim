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

import strutils, unicode, utils, window_manager, termdiff

type
  KeyInfo* = ref object of Window
    app: App
    keys: seq[Key]

method process_key*(key_info: KeyInfo, key: Key) =
  key_info.keys.add(key)

method render*(key_info: KeyInfo, box: Box, ren: var TermRenderer) =
  let title = "  " & strutils.align_left("Key Info", box.size.x - 2)
  ren.move_to(box.min)
  ren.put(title, fg=Color(base: ColorBlack), bg=Color(base: ColorWhite, bright: true))
  
  for y in 0..<(box.size.y - 1):
    ren.move_to(box.min.x, box.min.y + 1 + y)
    ren.put(" ", fg=Color(base: ColorBlack), bg=Color(base: ColorWhite, bright: true))
  
  for y in 0..<(box.size.y - 1):
    let it = max(key_info.keys.len - (box.size.y - 1), 0) + y
    if it >= key_info.keys.len or it < 0:
      break
    ren.move_to(box.min.x + 2, box.min.y + 1 + y)
    let key = key_info.keys[it]
    if key.kind == KeyChar:
      ren.put($int(key.chr))
      ren.put(Rune(228))
    
proc make_key_info*(app: App): Window =
  return KeyInfo(app: app, keys: @[])
