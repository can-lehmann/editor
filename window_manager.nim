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

import strutils, tables, unicode, sequtils, sugar
import utils, ui_utils, highlight/highlight, termdiff, buffer

type
  Window* = ref object of RootObj

  Command* = object
    name*: string
    shortcut*: seq[Key]
    cmd*: proc () {.closure.}

  PaneKind* = enum PaneWindow, PaneSplitH, PaneSplitV
  Pane* = ref PaneObj
  PaneObj* = object
   case kind*: PaneKind:
    of PaneWindow:
      is_dragging*: bool
      window*: Window
    of PaneSplitH, PaneSplitV:
      factor*: float64
      pane_a*: Pane
      pane_b*: Pane
      selected*: bool

  Launcher* = ref object of Window
    app: App
    list: List
  
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
method process_mouse*(window: Window, mouse: Mouse): bool {.base.} = discard
method render*(window: Window, box: Box, ren: var TermRenderer) {.base.} = quit "Not implemented"
method close*(window: Window) {.base.} = discard
method list_commands*(window: Window): seq[Command] {.base.} = discard

# Launcher
proc make_launcher(app: App): Window =
  return Launcher(app: app, list: make_list(app.window_constructors.map(c => c.name)))

proc open_window*(pane: Pane, window: Window)

proc open_selected(launcher: Launcher) =
  let
    selected = launcher.list.selected
    window = launcher.app.window_constructors[selected].make(launcher.app)
  launcher.app.root_pane.open_window(window)

method process_key(launcher: Launcher, key: Key) =
  case key.kind:
    of KeyArrowDown, KeyArrowUp:
      launcher.list.process_key(key)
    of KeyReturn:
      launcher.open_selected()
    else: discard

method process_mouse(launcher: Launcher, mouse: Mouse): bool =
  if mouse.x == 0 and mouse.y == 0:
    return true

  var mouse_rel = mouse
  mouse_rel.x -= 2
  mouse_rel.y -= 1

  case mouse.kind:
    of MouseUp:
      if launcher.list.process_mouse(mouse_rel):
        launcher.open_selected()
    else:
      discard launcher.list.process_mouse(mouse_rel)

method render(launcher: Launcher, box: Box, ren: var TermRenderer) =
  render_border("Launcher", 1, box, ren)
  launcher.list.render(Box(min: box.min + Index2d(x: 2, y: 1), max: box.max), ren)

proc make_window*(app: App): Window =
  return app.window_constructors[0].make(app)

proc make_window_constructor*(name: string, make: proc (app: App): Window): WindowConstructor =
  WindowConstructor(name: name, make: make)

# Command Search
type
  CommandSearch = ref object of Window
    app: App
    prev_window: Window
    list: List
    entry: Entry
    commands: seq[Command]
    shown_commands: seq[Command]

proc display(cmd: Command): string =
  if cmd.shortcut.len == 0:
    return cmd.name
  return cmd.name & " (" & $cmd.shortcut & ")"

proc update_list(cmd_search: CommandSearch) =
  cmd_search.shown_commands = cmd_search.commands
    .filter(cmd => to_lower($cmd_search.entry.text) in cmd.name.to_lower())

  cmd_search.list.items = cmd_search.shown_commands
    .map(cmd => to_runes(cmd.display()))

  if cmd_search.list.selected >= cmd_search.list.items.len:
    cmd_search.list.selected = cmd_search.list.items.len - 1

  if cmd_search.list.selected < 0:
    cmd_search.list.selected = 0

proc make_command_search(app: App, prev_window: Window): Window =
  let cmd_search = CommandSearch(
    app: app,
    prev_window: prev_window,
    list: make_list(@[""]),
    entry: make_entry(app.copy_buffer),
    commands: prev_window.list_commands()
  )
  cmd_search.update_list()
  return cmd_search

proc run_command(cmd_search: CommandSearch) =
  let selected = cmd_search.list.selected
  if selected < 0 or selected >= cmd_search.shown_commands.len:
    return
  cmd_search.app.root_pane.open_window(cmd_search.prev_window)
  cmd_search.shown_commands[selected].cmd()

method process_mouse(cmd_search: CommandSearch, mouse: Mouse): bool =
  if mouse.x < len("Search:") and mouse.y == 0:
    return true

  var mouse_rel = mouse
  mouse_rel.x -= 2
  mouse_rel.y -= 2

  case mouse.kind:
    of MouseUp:
      if cmd_search.list.process_mouse(mouse_rel):
        cmd_search.run_command()
    else:
      discard cmd_search.list.process_mouse(mouse_rel)

method process_key(cmd_search: CommandSearch, key: Key) =
  case key.kind:
    of KeyEscape:
      cmd_search.app.root_pane.open_window(cmd_search.prev_window)
    of KeyReturn:
      cmd_search.run_command()
    of KeyArrowUp, KeyArrowDown:
      cmd_search.list.process_key(key)
    else:
      cmd_search.entry.process_key(key)
      cmd_search.update_list()

method render(cmd_search: CommandSearch, box: Box, ren: var TermRenderer) =
  let sidebar_width = len("Search:")
  render_border("Command Search", sidebar_width, box, ren)
  ren.move_to(box.min + Index2d(y: 1))
  ren.put("Search:", fg=Color(base: ColorBlack), bg=Color(base: ColorWhite))
  ren.move_to(box.min + Index2d(y: 1, x: sidebar_width + 1))
  cmd_search.entry.render(ren)
  cmd_search.list.render(Box(min: box.min + Index2d(x: sidebar_width + 1, y: 2), max: box.max), ren)

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
            factor: 0.5,
            pane_a: Pane(kind: PaneWindow, window: if dir == DirUp: app.make_window() else: pane.window),
            pane_b: Pane(kind: PaneWindow, window: if dir == DirDown: app.make_window() else: pane.window),
            selected: dir == DirDown
          )
        of DirLeft, DirRight:
          pane[] = PaneObj(
            kind: PaneSplitH,
            factor: 0.5,
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

proc active_window*(pane: Pane): Window =  
  case pane.kind:
    of PaneWindow:
      return pane.window
    else:
      if pane.selected:
        return pane.pane_b.active_window()
      else:
        return pane.pane_a.active_window()

proc process_mouse*(pane: Pane, mouse: Mouse, box: Box): (int, int) =
  case pane.kind:
    of PaneWindow:
      if pane.is_dragging:
        if mouse.kind == MouseUp:
          pane.is_dragging = false
        return (0, 0)
      else:
        var mouse_rel = mouse
        mouse_rel.x -= box.min.x
        mouse_rel.y -= box.min.y
        if pane.window.process_mouse(mouse_rel) and mouse.kind == MouseDown:
          pane.is_dragging = true
        return (-1, -1)
    of PaneSplitH:
      let
        split = int(float64(box.size.x) * pane.factor) + box.min.x
        right = Box(min: Index2d(x: split, y: box.min.y), max: box.max)
        left = Box(min: box.min, max: Index2d(x: split, y: box.max.y))
      var res = (-1, -1)
      if mouse.kind == MouseDown or mouse.kind == MouseScroll:
        if left.is_inside(mouse.pos):
          if mouse.kind == MouseDown:
            pane.selected = false
          res = pane.pane_a.process_mouse(mouse, left)
        else:
          if mouse.kind == MouseDown:
            pane.selected = true
          res = pane.pane_b.process_mouse(mouse, right)
          if res[0] != -1:
            res[0] += 1
      else:
        if pane.selected:
          res = pane.pane_b.process_mouse(mouse, right)
          if res[0] != -1:
            res[0] += 1
        else:
          res = pane.pane_a.process_mouse(mouse, left)
      if res[0] == 1:
        pane.factor = (mouse.x - box.min.x) / box.size.x
        pane.factor = pane.factor.max(0).min(1)
        return (-1, res[1])
      return res
    of PaneSplitV:
      let
        split = int(float64(box.size.y) * pane.factor) + box.min.y
        bottom = Box(min: Index2d(x: box.min.x, y: split), max: box.max)
        top = Box(min: box.min, max: Index2d(x: box.max.x, y: split))
      var res = (-1, -1)
      if mouse.kind == MouseDown or mouse.kind == MouseScroll:
        if top.is_inside(mouse.pos):
          if mouse.kind == MouseDown:
            pane.selected = false
          res = pane.pane_a.process_mouse(mouse, top)
        else:
          if mouse.kind == MouseDown:
            pane.selected = true
          res = pane.pane_b.process_mouse(mouse, bottom)
          if res[1] != -1:
            res[1] += 1
      else:
        if pane.selected:
          res = pane.pane_b.process_mouse(mouse, bottom)
          if res[1] != -1:
            res[1] += 1
        else:
          res = pane.pane_a.process_mouse(mouse, top)
      if res[1] == 1:
        pane.factor = (mouse.y - box.min.y) / box.size.y
        pane.factor = pane.factor.max(0).min(1)
        return (res[0], -1)
      return res

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
      let split = int(float64(box.size.x) * pane.factor) + box.min.x
      pane.pane_a.render(Box(min: box.min, max: Index2d(x: split, y: box.max.y)), ren)
      pane.pane_b.render(Box(min: Index2d(x: split, y: box.min.y), max: box.max), ren)
    of PaneSplitV:
      let split = int(float64(box.size.y) * pane.factor) + box.min.y
      pane.pane_a.render(Box(min: box.min, max: Index2d(x: box.max.x, y: split)), ren)
      pane.pane_b.render(Box(min: Index2d(x: box.min.x, y: split), max: box.max), ren)

proc render*(pane: Pane, ren: var TermRenderer) = 
  pane.render(Box(
    min: Index2d(x: 0, y: 0),
    max: Index2d(x: ren.screen.width, y: ren.screen.height)
  ), ren)

# App
proc open_launcher(app: App) =
  app.root_pane.open_window(app.make_launcher())

proc open_command_search(app: App) =
  app.root_pane.open_window(app.make_command_search(app.root_pane.active_window()))

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
  discard app.root_pane.process_mouse(mouse, Box(
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
        of KeyQuit:
          return true
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
        of KeyFn:
          if key.fn == 1:
            app.open_command_search()
            return
        else: discard
      app.root_pane.process_key(key)
      return false

proc render*(app: App, ren: var TermRenderer) =
  app.root_pane.render(ren)

proc quit_app*() {.noconv.} =
  reset_term()
