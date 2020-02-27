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

import utils, ui_utils, highlight, termdiff, buffer, strutils, tables, unicode

type
  Window* = ref object of RootObj

  PaneKind* = enum PaneWindow, PaneSplitH, PaneSplitV
  Pane* = ref PaneObj
  PaneObj* = object
   case kind*: PaneKind:
    of PaneWindow:
      window*: Window
    of PaneSplitH, PaneSplitV:
      pane_a*: Pane
      pane_b*: Pane
      selected*: bool

  Launcher* = ref object of Window
    app: App
    selected: int
  
  WindowConstructor* = object
    name: string
    make: proc (app: App): Window

  AppMode* = enum AppModeNone, AppModePane, AppModeNewPane
      
  App* = ref object
    root_pane*: Pane
    copy_buffer*: CopyBuffer
    languages*: seq[Language]
    window_constructors*: seq[WindowConstructor]
    mode*: AppMode
    buffers*: Table[string, Buffer]

method process_key*(window: Window, key: Key) {.base.} = quit "Not implemented"
method process_mouse*(window: Window, mouse: Mouse) {.base.} = discard
method render*(window: Window, box: Box, ren: var TermRenderer) {.base.} = quit "Not implemented"
method close*(window: Window) {.base.} = discard

# Launcher
proc make_launcher(app: App): Window =
  return Launcher(app: app, selected: 0)

proc open_window*(pane: Pane, window: Window)

method process_key(launcher: Launcher, key: Key) =
  case key.kind:
    of KeyArrowDown:
      launcher.selected += 1
      if launcher.selected >= launcher.app.window_constructors.len:
        launcher.selected = launcher.app.window_constructors.len - 1
    of KeyArrowUp:
      launcher.selected -= 1
      if launcher.selected < 0:
        launcher.selected = 0
    of KeyReturn:
      let window = launcher.app.window_constructors[launcher.selected].make(launcher.app)
      launcher.app.root_pane.open_window(window)
    else: discard

method render(launcher: Launcher, box: Box, ren: var TermRenderer) =
  let title = "  " & strutils.align_left("Launcher", box.size.x - 2)
  ren.move_to(box.min)
  ren.put(title, fg=Color(base: ColorBlack), bg=Color(base: ColorWhite, bright: true))
  
  for y in 0..<(box.size.y - 1):
    ren.move_to(box.min.x, box.min.y + 1 + y)
    ren.put(" ", fg=Color(base: ColorBlack), bg=Color(base: ColorWhite, bright: true))

  for it, constructor in launcher.app.window_constructors:
    if it + 1 >= box.size.y:
      break
    ren.move_to(box.min.x + 2, box.min.y + 1 + it)
    if it == launcher.selected:
      ren.put(constructor.name, reverse=true)
    else:
      ren.put(constructor.name)

proc make_window*(app: App): Window =
  return app.window_constructors[0].make(app)

proc make_window_constructor*(name: string, make: proc (app: App): Window): WindowConstructor =
  WindowConstructor(name: name, make: make)

# Pane
proc select_below*(pane: Pane): bool =
  case pane.kind:
    of PaneWindow: return false
    of PaneSplitH:
      if pane.selected:
        return pane.pane_b.select_below()
      else:
        return pane.pane_a.select_below()
    of PaneSplitV:
      if pane.selected:
        return pane.pane_b.select_below()
      else:
        if not pane.pane_a.select_below():
          pane.selected = true
        return true

proc select_above*(pane: Pane): bool =
  case pane.kind:
    of PaneWindow: return false
    of PaneSplitH:
      if pane.selected:
        return pane.pane_b.select_above()
      else:
        return pane.pane_a.select_above()
    of PaneSplitV:
      if pane.selected:
        if not pane.pane_b.select_above():
          pane.selected = false
        return true
      else:
        return pane.pane_a.select_above()

proc select_left*(pane: Pane): bool =
  case pane.kind:
    of PaneWindow: return false
    of PaneSplitV:
      if pane.selected:
        return pane.pane_b.select_left()
      else:
        return pane.pane_a.select_left()
    of PaneSplitH:
      if pane.selected:
        if not pane.pane_b.select_left():
          pane.selected = false
        return true
      else:
        return pane.pane_a.select_left()

proc select_right*(pane: Pane): bool =
  case pane.kind:
    of PaneWindow: return false
    of PaneSplitV:
      if pane.selected:
        return pane.pane_b.select_right()
      else:
        return pane.pane_a.select_right()
    of PaneSplitH:
      if pane.selected:
        return pane.pane_b.select_right()
      else:
        if not pane.pane_a.select_right():
          pane.selected = true
        return true

proc close_active_pane*(pane: Pane) = 
  if pane.kind != PaneSplitH and pane.kind != PaneSplitV:
    return
  
  if pane.selected:
    if pane.pane_b.kind == PaneWindow:
      pane.pane_b.window.close()
      pane[] = pane.pane_a[]
    else:
      pane.pane_b.close_active_pane()
  else:
    if pane.pane_a.kind == PaneWindow:
      pane.pane_a.window.close()
      pane[] = pane.pane_b[]
    else:
      pane.pane_a.close_active_pane()

proc split*(pane: Pane, dir: Direction, app: App) =
  case pane.kind:
    of PaneWindow:
      case dir:
        of DirUp, DirDown:
          pane[] = PaneObj(
            kind: PaneSplitV,
            pane_a: Pane(kind: PaneWindow, window: if dir == DirUp: app.make_window() else: pane.window),
            pane_b: Pane(kind: PaneWindow, window: if dir == DirDown: app.make_window() else: pane.window),
            selected: dir == DirDown
          )
        of DirLeft, DirRight:
          pane[] = PaneObj(
            kind: PaneSplitH,
            pane_a: Pane(kind: PaneWindow, window: if dir == DirLeft: app.make_window() else: pane.window),
            pane_b: Pane(kind: PaneWindow, window: if dir == DirRight: app.make_window() else: pane.window),
            selected: dir == DirRight
          )
    of PaneSplitH, PaneSplitV:
      if pane.selected:
        pane.pane_b.split(dir, app)
      else:
        pane.pane_a.split(dir, app)

proc open_window*(pane: Pane, window: Window) =
  case pane.kind:
    of PaneWindow:
      pane.window = window
    of PaneSplitH, PaneSplitV:
      if pane.selected:
        pane.pane_b.open_window(window)
      else:
        pane.pane_a.open_window(window)
 
proc open_launcher(app: App) =
  app.root_pane.open_window(app.make_launcher())
 
proc process_mouse*(pane: Pane, mouse: Mouse, box: Box) =
  case pane.kind:
    of PaneWindow:
      var mouse_rel = mouse
      mouse_rel.x -= box.min.x
      mouse_rel.y -= box.min.y
      pane.window.process_mouse(mouse_rel)
    of PaneSplitH:
      let
        split = box.size.x div 2 + box.min.x
        right = Box(min: Index2d(x: split, y: box.min.y), max: box.max)
        left = Box(min: box.min, max: Index2d(x: split, y: box.max.y))
      if mouse.kind == MouseUnknown or mouse.kind == MouseNone or mouse.kind == MouseMove:
        if pane.selected:
          pane.pane_b.process_mouse(mouse, right)
        else:
          pane.pane_a.process_mouse(mouse, left)
      else:
        if left.is_inside(mouse.pos):
          pane.selected = false
          pane.pane_a.process_mouse(mouse, left)
        else:
          pane.selected = true
          pane.pane_b.process_mouse(mouse, right)
    of PaneSplitV:
      let
        split = box.size.y div 2 + box.min.y
        bottom = Box(min: Index2d(x: box.min.x, y: split), max: box.max)
        top = Box(min: box.min, max: Index2d(x: box.max.x, y: split))
      if mouse.kind == MouseUnknown or mouse.kind == MouseNone or mouse.kind == MouseMove:
        if pane.selected:
          pane.pane_b.process_mouse(mouse, bottom)
        else:
          pane.pane_a.process_mouse(mouse, top)
      else:
        if top.is_inside(mouse.pos):
          pane.selected = false
          pane.pane_a.process_mouse(mouse, top)
        else:
          pane.selected = true
          pane.pane_b.process_mouse(mouse, bottom)

proc process_key*(pane: Pane, key: Key) =
  case pane.kind:
    of PaneWindow:
      pane.window.process_key(key)
    of PaneSplitH, PaneSplitV:
      if pane.selected:
        pane.pane_b.process_key(key)
      else:
        pane.pane_a.process_key(key)
        
proc render*(pane: Pane, box: Box, ren: var TermRenderer) =
  case pane.kind:
    of PaneWindow:
      ren.clip(box)
      pane.window.render(box, ren)
    of PaneSplitH:
      let split = box.size.x div 2 + box.min.x
      pane.pane_a.render(Box(min: box.min, max: Index2d(x: split, y: box.max.y)), ren)
      pane.pane_b.render(Box(min: Index2d(x: split, y: box.min.y), max: box.max), ren)
    of PaneSplitV:
      let split = box.size.y div 2 + box.min.y
      pane.pane_a.render(Box(min: box.min, max: Index2d(x: box.max.x, y: split)), ren)
      pane.pane_b.render(Box(min: Index2d(x: box.min.x, y: split), max: box.max), ren)

proc render*(pane: Pane, ren: var TermRenderer) = 
  pane.render(Box(
    min: Index2d(x: 0, y: 0),
    max: Index2d(x: ren.screen.width, y: ren.screen.height)
  ), ren)

# App
proc make_app*(languages: seq[Language], window_constructors: seq[WindowConstructor]): owned App =
  return App(
    copy_buffer: make_copy_buffer(),
    root_pane: nil,
    languages: languages,
    window_constructors: window_constructors,
    buffers: init_table[string, Buffer]()
  )

proc make_buffer*(app: App, path: string): Buffer =
  if app.buffers.has_key(path):
    return app.buffers[path]
  result = make_buffer(path, app.languages)
  app.buffers[path] = result

proc is_changed*(app: App, path: string): bool =
  if not app.buffers.has_key(path):
    return false
  return app.buffers[path].changed

proc list_changed*(app: App): seq[string] =
  for path in app.buffers.keys:
    if app.buffers[path].changed:
      result.add(path)

proc process_mouse*(app: App, mouse: Mouse) =
  app.root_pane.process_mouse(mouse, Box(
    min: Index2d(x: 0, y: 0),
    max: Index2d(x: terminal_width(), y: terminal_height())
  ))

proc process_key*(app: App, key: Key): bool =
  case app.mode:
    of AppModeNewPane:
      case key.kind:
        of KeyArrowDown:
          app.root_pane.split(DirDown, app)
        of KeyArrowUp:
          app.root_pane.split(DirUp, app)
        of KeyArrowLeft:
          app.root_pane.split(DirLeft, app)
        of KeyArrowRight:
          app.root_pane.split(DirRight, app)
        of KeyNone:
          return false
        else: discard
      app.mode = AppModeNone
      return
    of AppModePane:
      case key.kind:
        of KeyChar:
          if key.chr == Rune('n'):
            app.mode = AppModeNewPane
            return
          elif key.chr == Rune('a'):
            app.open_launcher()
        of KeyArrowUp: discard app.root_pane.select_above()
        of KeyArrowDown: discard app.root_pane.select_below()
        of KeyArrowLeft: discard app.root_pane.select_left()
        of KeyArrowRight: discard app.root_pane.select_right()
        of KeyNone:
          return false
        else: discard
      app.mode = AppModeNone
      return
    of AppModeNone:
      case key.kind:
        of KeyChar:
          if key.ctrl:
            case key.chr:
              of Rune('q'): return true
              of Rune('w'):
                app.root_pane.close_active_pane()
                return
              of Rune('p'):
                app.mode = AppModePane
                return
              else:  discard
        of KeyArrowDown:
          if key.alt and not key.shift and not key.ctrl:
            discard app.root_pane.select_below()
            return
        of KeyArrowUp: 
          if key.alt and not key.shift and not key.ctrl:
            discard app.root_pane.select_above()
            return
        of KeyArrowLeft:
          if key.alt and not key.shift and not key.ctrl:
            discard app.root_pane.select_left()
            return
        of KeyArrowRight:
          if key.alt and not key.shift and not key.ctrl:
            discard app.root_pane.select_right()
            return
        else: discard
      app.root_pane.process_key(key)
      return false

proc render*(app: App, ren: var TermRenderer) =
  app.root_pane.render(ren)

proc quit_app*() {.noconv.} =
  reset_term()
