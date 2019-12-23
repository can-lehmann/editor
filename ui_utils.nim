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
  CursorKind* = enum CursorInsert, CursorSelection
  
  Cursor* = object
    case kind*: CursorKind:
      of CursorInsert:
        pos*: int
      of CursorSelection:
        start*: int
        stop*: int

proc sort*(cursor: Cursor): Cursor =
  case cursor.kind:
    of CursorInsert: return cursor
    of CursorSelection:
      if cursor.start < cursor.stop:
        return cursor
      else:
        return Cursor(kind: CursorSelection, start: cursor.stop, stop: cursor.start)

proc move*(cursor: var Cursor, delta: int, max_pos: int) =
  case cursor.kind:
    of CursorInsert:
      cursor.pos += delta
      cursor.pos = cursor.pos.max(0).min(max_pos)
    of CursorSelection:
      cursor.start += delta
      cursor.stop += delta
      
      cursor.start = cursor.start.max(0).min(max_pos)
      cursor.stop = cursor.stop.max(0).min(max_pos)

proc get_pos*(cursor: Cursor): int =
  case cursor.kind:
    of CursorInsert: return cursor.pos
    of CursorSelection: return cursor.stop

proc is_under*(cursor: Cursor, pos: int): bool =
  case cursor.kind:
    of CursorInsert:
      return pos == cursor.pos
    of CursorSelection:
      return (pos >= cursor.start and pos < cursor.stop) or
             (pos >= cursor.stop and pos < cursor.start)

type
  Entry* = object
    text*: string
    cursor*: Cursor
    copy_buffer*: CopyBuffer

proc delete_selected(entry: var Entry) =
  if entry.cursor.kind != CursorSelection:
    return
  let
    cur = entry.cursor.sort()
    before = entry.text.substr(0, cur.start - 1)
    after = entry.text.substr(cur.stop)
  entry.text = before & after
  entry.cursor = Cursor(kind: CursorInsert, pos: cur.start)

proc update(cursor: var Cursor, dir, max_pos: int, select: bool) =
  case cursor.kind:
    of CursorInsert:
      let p = (cursor.pos + dir).max(0).min(max_pos)
      if select:
        cursor = Cursor(kind: CursorSelection, start: cursor.pos, stop: p)
      else:
        cursor.pos = p
    of CursorSelection:
      if select:
        cursor.stop = (cursor.stop + dir).max(0).min(max_pos)
      else:
        let cur = cursor.sort()
        if dir < 0:
          cursor = Cursor(kind: CursorInsert, pos: cur.start)
        else:
          cursor = Cursor(kind: CursorInsert, pos: cur.stop)

proc process_key*(entry: var Entry, key: Key) =
  case key.kind:
    of KeyArrowLeft:
      entry.cursor.update(-1, entry.text.len, key.shift)
    of KeyArrowRight:
      entry.cursor.update(1, entry.text.len, key.shift)
    of KeyBackspace:
      case entry.cursor.kind:
        of CursorInsert:
          if entry.cursor.pos == 0:
            return
          entry.text = entry.text.substr(0, entry.cursor.pos - 2) & entry.text.substr(entry.cursor.pos)
          entry.cursor.pos -= 1
        of CursorSelection:
          entry.delete_selected()
    of KeyDelete:
      case entry.cursor.kind:
        of CursorInsert:
          entry.text = entry.text.substr(0, entry.cursor.pos - 1) & entry.text.substr(entry.cursor.pos + 1)
        of CursorSelection:
          entry.delete_selected()
    of KeyChar:
      if key.ctrl:
        case key.chr:
          of 'a':
            entry.cursor = Cursor(kind: CursorSelection, start: 0, stop: entry.text.len)
          of 'v':
            entry.delete_selected()
            if entry.copy_buffer == nil:
              return
            let 
              before = entry.text.substr(0, entry.cursor.pos - 1)
              after = entry.text.substr(entry.cursor.pos)
              paste = entry.copy_buffer.paste()
            entry.text = before & paste & after
            entry.cursor.pos += paste.len
          of 'c', 'x':
            if entry.cursor.kind == CursorSelection:
              let cur = entry.cursor.sort()
              entry.copy_buffer.copy(entry.text.substr(cur.start, cur.stop - 1))
              if key.chr == 'x':
                entry.delete_selected()
          else: discard
      else:
        entry.delete_selected()
        let
          before = entry.text.substr(0, entry.cursor.pos - 1)
          after = entry.text.substr(entry.cursor.pos)
        entry.text = before & key.chr & after
        entry.cursor.pos += 1 
    else:
      discard

proc render*(entry: Entry, ren: var TermRenderer) =
  case entry.cursor.kind:
    of CursorInsert:
      ren.put(entry.text.substr(0, entry.cursor.pos - 1))
      if entry.cursor.pos < entry.text.len:
        ren.put(entry.text[entry.cursor.pos], reverse=true)
        ren.put(entry.text.substr(entry.cursor.pos + 1))
      else:
        ren.put(" ", reverse=true)
    of CursorSelection:
      let cur = entry.cursor.sort()
      ren.put(entry.text.substr(0, cur.start - 1))
      ren.put(entry.text.substr(cur.start, cur.stop - 1), reverse=true)
      ren.put(entry.text.substr(cur.stop))
      
proc make_entry*(copy_buffer: CopyBuffer = nil): owned Entry =
  return Entry(text: "", cursor: Cursor(kind: CursorInsert, pos: 0), copy_buffer: copy_buffer)
