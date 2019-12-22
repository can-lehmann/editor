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


import strutils, deques
import utils, termdiff

type
  CopyBuffer* = ref object
    history*: Deque[string]
    
proc make_copy_buffer*(): owned CopyBuffer =
  return CopyBuffer(history: init_deque[string]())

proc copy*(buffer: CopyBuffer, str: string) =
  buffer.history.add_last(str)

proc paste*(buffer: CopyBuffer): string =
  return buffer.history[buffer.history.len - 1]

type
  Entry* = object
    text*: string
    cursor*: int
    copy_buffer*: CopyBuffer

proc process_key*(entry: var Entry, key: Key) =
  case key.kind:
    of KeyArrowLeft:
      entry.cursor -= 1
      if entry.cursor < 0:
        entry.cursor = 0
    of KeyArrowRight:
      entry.cursor += 1
      if entry.cursor > entry.text.len:
        entry.cursor = entry.text.len
    of KeyBackspace:
      if entry.cursor == 0:
        return
      entry.text = entry.text.substr(0, entry.cursor - 2) & entry.text.substr(entry.cursor)
      entry.cursor -= 1
    of KeyChar:
      if key.ctrl:
        case key.chr:
          of 'v':
            if entry.copy_buffer == nil:
              return
            let 
              before = entry.text.substr(0, entry.cursor - 1)
              after = entry.text.substr(entry.cursor)
              paste = entry.copy_buffer.paste()
            entry.text = before & paste & after
            entry.cursor += paste.len 
          else: discard
      else:
        entry.text = entry.text.substr(0, entry.cursor - 1) & key.chr & entry.text.substr(entry.cursor)
        entry.cursor += 1
    else:
      discard

proc render*(entry: Entry, ren: var TermRenderer) =
  ren.put(entry.text.substr(0, entry.cursor - 1))
  if entry.cursor < entry.text.len:
    ren.put(entry.text[entry.cursor], reverse=true)
    ren.put(entry.text.substr(entry.cursor + 1))
  else:
    ren.put(" ", reverse=true)

proc make_entry*(copy_buffer: CopyBuffer = nil): owned Entry =
  return Entry(text: "", cursor: 0, copy_buffer: copy_buffer)
