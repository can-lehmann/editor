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


import strutils, deques, unicode, hashes, sets, sequtils, sugar
import utils, termdiff

type
  CopyBuffer* = ref object
    history*: Deque[seq[Rune]]
    
proc make_copy_buffer*(): owned CopyBuffer =
  return CopyBuffer(history: init_deque[seq[Rune]]())

proc copy*(buffer: CopyBuffer, str: seq[Rune]) =
  buffer.history.add_last(str)

proc paste*(buffer: CopyBuffer): seq[Rune] =
  if buffer.history.len == 0:
    return @[]
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

proc hash*(cursor: Cursor): Hash =
  case cursor.kind:
    of CursorInsert:
      return !$(cursor.kind.hash() !& cursor.pos.hash())
    of CursorSelection:
      return !$(cursor.kind.hash() !& cursor.start.hash() !& cursor.stop.hash())

proc `==`*(a, b: Cursor): bool =
  if a.kind != b.kind:
    return false
  case a.kind:
    of CursorInsert:
      return a.pos == b.pos
    of CursorSelection:
      return a.start == b.start and a.stop == b.stop

proc merge_cursors*(cursors: seq[Cursor]): seq[Cursor] =
  var yet = init_hash_set[Cursor]()
  result = @[]
  for cursor in cursors:
    if cursor in yet:
      continue
    result.add(cursor)
    yet.incl(cursor)

type
  Entry* = object
    text*: seq[Rune]
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

proc update*(cursor: var Cursor, dir, max_pos: int, select: bool) =
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

proc skip(text: seq[Rune], pos, dir: int): int =
  if text.len == 0:
    return 0
  result = 0
  if pos < 0:
    result = -pos
  elif pos >= text.len:
    result = -(pos - text.len + 1)
  let v = text[pos + result].is_alpha_numeric()
  while pos + result >= 0 and
        pos + result < text.len and
        text[pos + result].is_alpha_numeric() == v:
    result += dir

proc process_key*(entry: var Entry, key: Key) =
  case key.kind:
    of KeyArrowLeft:
      var offset = -1
      if key.ctrl:
        offset = entry.text.skip(entry.cursor.get_pos() - 1, -1)
      entry.cursor.update(offset, entry.text.len, key.shift)
    of KeyArrowRight:
      var offset = 1
      if key.ctrl:
        offset = entry.text.skip(entry.cursor.get_pos(), 1)
      entry.cursor.update(offset, entry.text.len, key.shift)
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
          of Rune('a'):
            entry.cursor = Cursor(kind: CursorSelection, start: 0, stop: entry.text.len)
          of Rune('v'):
            entry.delete_selected()
            if entry.copy_buffer == nil:
              return
            let 
              before = entry.text.substr(0, entry.cursor.pos - 1)
              after = entry.text.substr(entry.cursor.pos)
              paste = entry.copy_buffer.paste()
            entry.text = before & paste & after
            entry.cursor.pos += paste.len
          of Rune('c'), Rune('x'):
            if entry.cursor.kind == CursorSelection:
              let cur = entry.cursor.sort()
              entry.copy_buffer.copy(entry.text.substr(cur.start, cur.stop - 1))
              if key.chr == Rune('x'):
                entry.delete_selected()
          else: discard
      else:
        entry.delete_selected()
        let
          before = entry.text.substr(0, entry.cursor.pos - 1)
          after = entry.text.substr(entry.cursor.pos)
        entry.text = before & Rune(int32(key.chr)) & after
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
  return Entry(text: @[], cursor: Cursor(kind: CursorInsert, pos: 0), copy_buffer: copy_buffer)

proc make_entry*(text: seq[Rune], copy_buffer: CopyBuffer = nil): owned Entry =
  return Entry(text: text, cursor: Cursor(kind: CursorInsert, pos: 0), copy_buffer: copy_buffer)

proc render_border*(title: string, sidebar_width: int, box: Box, ren: var TermRenderer) =
  var shown_title = title
  let padding_len = box.size.x - sidebar_width - 1 - title.len
  if padding_len < 0:
    shown_title = shown_title.substr(0, shown_title.len - 1 + padding_len)
  
  let
    after = strutils.repeat(' ', padding_len.max(0))
    titlebar = strutils.repeat(' ', sidebar_width + 1) & shown_title & after
    
  ren.move_to(box.min)
  ren.put(
    titlebar,
    fg=Color(base: ColorBlack),
    bg=Color(base: ColorWhite)
  )
    
  for y in 1..<box.size.y:
    ren.move_to(box.min.x, box.min.y + y)
    ren.put(
      repeat(' ', sidebar_width),
      fg=Color(base: ColorBlack),
      bg=Color(base: ColorWhite)
    )

type
  List* = object
    items*: seq[seq[Rune]]
    selected*: int
    view*: int
    detached: bool

proc make_list*(items: seq[seq[Rune]]): List =
  List(items: items, view: 0, selected: 0)

proc make_list*(items: seq[string]): List =
  make_list(items.map(to_runes))

proc process_mouse*(list: var List, mouse: Mouse): bool =
  case mouse.kind:
    of MouseScroll:
      list.detached = true
      list.view += mouse.delta * 2
    of MouseDown, MouseMove, MouseUp:
      if mouse.buttons[0] or
         (mouse.kind == MouseUp and mouse.button == 0):
        let selected = mouse.y + list.view
        if selected >= 0 and selected < list.items.len:
          list.selected = selected
          return true
    else: discard

proc process_key*(list: var List, key: Key) =
  list.detached = false
  case key.kind:
    of KeyArrowUp:
      list.selected -= 1
      if list.selected < 0:
        list.selected = 0
    of KeyArrowDown:
      list.selected += 1
      if list.selected >= list.items.len:
        list.selected = list.items.len - 1
    else: discard

proc scroll(list: var List, height: int) =
  if not list.detached:
    while list.selected - list.view >= height - 3:
      list.view += 1
    
    while list.selected - list.view < 3:
      list.view -= 1

  if list.view >= list.items.len:
    list.view = list.items.len - 1
  if list.view < 0:
    list.view = 0

proc render*(list: var List, box: Box, ren: var TermRenderer) =
  let prev_clip = ren.clip_area
  ren.clip(box)
  
  list.scroll(box.size.y)
  for it, item in list.items:
    ren.move_to(box.min.x, box.min.y + it - list.view)
    ren.put(item, reverse=it == list.selected)
    
  ren.clip(prev_clip)

