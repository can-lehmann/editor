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

import unicode, strutils, sequtils, sugar, math, times
import utils, ui_utils, window_manager, termdiff, log

type
  Viewer = ref object of Window
    app: App
    scroll: int
    page_height: int
    attach_end: bool

method process_mouse(viewer: Viewer, mouse: Mouse): bool =
  let sidebar_width = len($viewer.app.log.history.len) + 1
  if mouse.y == 0 and mouse.x < sidebar_width:
    return true

proc display(time: Time): string =
  align($time.local().hour, 2, '0') & ":" &
  align($time.local().minute, 2, '0') & ":" &
  align($time.local().second, 2, '0')

const LOG_NAMES: array[LogLevel, string] = ["info", "warning", "error"]

proc `$`(entry: LogEntry): string =
  result = "[" & display(entry.time) & "]"
  result &= "[" & LOG_NAMES[entry.level] & "]"
  result &= "[" & entry.module & "] " & entry.message

proc limit_scroll(viewer: Viewer) =
  viewer.scroll = min(viewer.scroll, viewer.app.log.history.len - 1)
  viewer.scroll = max(viewer.scroll, 0)

proc goto_end(viewer: Viewer) =
  viewer.scroll = viewer.app.log.history.len - viewer.page_height + 1
  viewer.limit_scroll()

method process_key(viewer: Viewer, key: Key) =
  var detach_end = true
  case key.kind:
    of KeyArrowDown:
      viewer.scroll += 1
    of KeyArrowUp:
      viewer.scroll -= 1
    of KeyPageDown:
      viewer.scroll += viewer.page_height
    of KeyPageUp:
      viewer.scroll -= viewer.page_height
    of KeyEnd:
      viewer.attach_end = true
      detach_end = false
    of KeyHome:
      viewer.scroll = 0
    of KeyChar:
      case key.chr:
        of 'c':
          if key.ctrl:
            var lines: seq[string]
            for entry in viewer.app.log.history:
              lines.add($entry)
            viewer.app.copy_buffer.copy(lines.join("\n").to_runes())
          else:
            viewer.app.log.clear()
        of 'e': viewer.app.log.enable()
        of 'd': viewer.app.log.disable()
        else: discard
      detach_end = false
    else: detach_end = false
  
  if detach_end:
    viewer.attach_end = false
  if viewer.attach_end:
    viewer.goto_end()
  viewer.limit_scroll()

const LOG_COLORS: array[LogLevel, Color] = [
  Color(base: ColorDefault),
  Color(base: ColorYellow),
  Color(base: ColorRed, bright: true)
]

proc display(entry: LogEntry): string =
  return "[" & entry.module & "] " & entry.message

method render(viewer: Viewer, box: Box, ren: var TermRenderer) =
  if viewer.attach_end:
    viewer.goto_end()
  
  viewer.page_height = box.size.y
  let sidebar_width = len($viewer.app.log.history.len) + 1
  var log_status = "Logging Disabled"
  if viewer.app.log.enabled:
    log_status = "Logging Enabled"
  render_border("Log Viewer (" & log_status & ")", sidebar_width, box, ren)
  var
    it = viewer.scroll
    y = 1
  while it < viewer.app.log.history.len and y < box.size.y:
    ren.move_to(box.min + Index2d(y: y))
    ren.put(strutils.align($it, sidebar_width),
      fg=Color(base: ColorBlack),
      bg=Color(base: ColorWhite)
    )
    ren.move_to(box.min + Index2d(x: sidebar_width + 1, y: y))
    let entry = viewer.app.log.history[it]
    ren.put(display(entry), fg = LOG_COLORS[entry.level])
    let time_str = display(entry.time)
    ren.move_to(box.min + Index2d(x: box.size.x - len(time_str), y: y))
    ren.put(time_str)
    y += 1
    it += 1

proc new_log_viewer*(app: App): Window =
  Viewer(app: app, attach_end: true)
