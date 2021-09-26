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

import strutils, tables, unicode, sequtils, sugar
import hashes, times, algorithm, asyncdispatch
import utils, ui_utils, termdiff, buffer, log

type
  Window* = ref object of RootObj

  Command* = object
    name*: string
    shortcut*: seq[Key]
    cmd*: proc () {.closure.}
  
  Launcher* = ref object of Window
    app: App
    list: List
  
  WindowConstructor* = object
    name: string
    make: proc (app: App): Window
  
  AppMode* = enum AppModeNone, AppModePane, AppModeNewPane
  
  Panes*[T] = object
    axis: Axis
    selected*: int
    sizes*: seq[float64]
    children*: seq[T]
  
  App* = ref object
    columns*: Panes[Panes[Window]]
    copy_buffer*: CopyBuffer
    languages*: seq[Language]
    window_constructors*: seq[WindowConstructor]
    mode*: AppMode
    buffers*: Table[string, Buffer]
    autocompleters*: Table[int, Autocompleter]
    log*: Log

method process_key*(window: Window, key: Key) {.base.} = quit "Not implemented: process_key"
method process_mouse*(window: Window, mouse: Mouse): bool {.base.} = discard
method render*(window: Window, box: Box, ren: var TermRenderer) {.base.} = quit "Not implemented: render"
method close*(window: Window) {.base.} = discard
method list_commands*(window: Window): seq[Command] {.base.} = discard

# Launcher
proc new_launcher(app: App): Window =
  return Launcher(app: app, list: make_list(app.window_constructors.map(c => c.name)))

proc open_window*[T](panes: var Panes[T], window: Window)

proc open_selected(launcher: Launcher) =
  let
    selected = launcher.list.selected
    window = launcher.app.window_constructors[selected].make(launcher.app)
  launcher.app.columns.open_window(window)

method process_key(launcher: Launcher, key: Key) =
  case key.kind:
    of LIST_KEYS:
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

proc init_window_constructor*(name: string, make: proc (app: App): Window): WindowConstructor =
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

proc new_command_search(app: App, prev_window: Window): Window =
  let cmd_search = CommandSearch(
    app: app,
    prev_window: prev_window,
    list: make_list(@[""]),
    entry: make_entry(app.copy_buffer),
    commands: prev_window.list_commands()
  )
  cmd_search.commands.sort(proc (a, b: Command): int =
    cmp(a.name.to_lower(), b.name.to_lower()))
  cmd_search.update_list()
  return cmd_search

proc run_command(cmd_search: CommandSearch) =
  let selected = cmd_search.list.selected
  if selected < 0 or selected >= cmd_search.shown_commands.len:
    return
  cmd_search.app.columns.open_window(cmd_search.prev_window)
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
  if key.kind == KeyEscape or
     (key.kind == KeyChar and key.chr == 'e' and key.ctrl):
    cmd_search.app.columns.open_window(cmd_search.prev_window)
    return
  
  case key.kind:
    of KeyReturn:
      cmd_search.run_command()
    of LIST_KEYS:
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

# Panes

proc init_panes*[T](axis: Axis, children: seq[T]): Panes[T] =
  result = Panes[T](
    axis: axis,
    children: children,
    sizes: new_seq[float64](children.len)
  )
  for it in 0..<children.len:
    result.sizes[it] = 1.0

proc open_window*(panes: var Panes[Window], window: Window) =
  panes.children[panes.selected] = window

proc open_window*[T](panes: var Panes[T], window: Window) =
  panes.children[panes.selected].open_window(window)

proc active_window*(window: Window): Window = window

proc active_window*[T](panes: Panes[T]): Window =  
  result = panes.children[panes.selected].active_window()

proc adjust_sizes*[T](panes: var Panes[T]) =
  var total: float64 = 0.0
  for size in panes.sizes:
    total += size
  for size in panes.sizes.mitems:
    size /= total

proc constrain_selected*[T](panes: var Panes[T]) =
  panes.selected = panes.selected.min(panes.children.len - 1).max(0)

proc close_active_window*(panes: var Panes[Panes[Window]]) =
  template active_column: var Panes[Window] = panes.children[panes.selected]
  if panes.children.len == 1 and
     active_column.children.len == 1:
    return
  active_column.children.delete(active_column.selected)
  active_column.sizes.delete(active_column.selected)
  active_column.adjust_sizes()
  active_column.constrain_selected()
  if active_column.children.len == 0:
    panes.children.delete(panes.selected)
    panes.sizes.delete(panes.selected)
    panes.adjust_sizes()
    panes.constrain_selected()

proc process_mouse*(window: Window, mouse: Mouse, box: Box) =
  var mouse_rel = mouse
  mouse_rel.x -= box.min.x
  mouse_rel.y -= box.min.y
  discard window.process_mouse(mouse_rel)

iterator iter_layout[T](panes: Panes[T], box: Box): (int, Box, T) =
  var offset = 0
  for it, child in panes.children:
    let space = int(panes.sizes[it] * float64(box.size[panes.axis]))
    var child_box = Box()
    child_box.min[not panes.axis] = box.min[not panes.axis]
    child_box.max[not panes.axis] = box.max[not panes.axis]
    child_box.min[panes.axis] = offset + box.min[panes.axis]
    child_box.max[panes.axis] = offset + space + box.min[panes.axis]
    if it == panes.children.len - 1:
      child_box.max[panes.axis] = box.max[panes.axis]
    yield (it, child_box, child)
    offset += space

proc process_mouse*[T](panes: var Panes[T], mouse: Mouse, box: Box) =
  for it, child_box, child in panes.iter_layout(box):
    if child_box.is_inside(mouse.pos):
      if mouse.kind == MouseDown:
        panes.selected = it
      panes.children[it].process_mouse(mouse, child_box)
      break

proc process_key*[T](panes: Panes[T], key: Key) =
  panes.children[panes.selected].process_key(key)

proc render*[T](panes: Panes[T], box: Box, ren: var TermRenderer) =
  for it, child_box, child in panes.iter_layout(box):
    child.render(child_box, ren)

proc add*[T](panes: var Panes[T], child: T, size: float64 = 1) =
  panes.children.add(child)
  panes.sizes.add(size)

proc select*[T](panes: var Panes[T], dir: Direction) =
  if panes.axis == dir.to_axis():
    panes.selected += dir.on_axis()
    panes.constrain_selected()
  else:
    when T isnot Window:
      panes.children[panes.selected].select(dir)

proc split*[T](panes: var Panes[T], child: T, index: int) =
  panes.children.insert(child, index)
  panes.sizes.insert(0.0, index)
  for size in panes.sizes.mitems:
    size = 1 / panes.sizes.len

proc split*(panes: var Panes[Window], dir: Direction, app: App) =
  let offset = (dir.on_axis() + 1) div 2
  panes.split(app.make_window(), panes.selected + offset)
  panes.selected += offset

proc split*(panes: var Panes[Panes[Window]], dir: Direction, app: App) =
  if panes.axis == dir.to_axis():
    let offset = (dir.on_axis() + 1) div 2
    let child = init_panes(not panes.axis, @[app.make_window()])
    panes.split(child, panes.selected + offset)
    panes.selected += offset
  else:
    panes.children[panes.selected].split(dir, app)

# App
proc open_launcher(app: App) =
  app.columns.open_window(app.new_launcher())

proc open_command_search(app: App) =
  app.columns.open_window(app.new_command_search(app.columns.active_window()))

proc new_app*(languages: seq[Language], window_constructors: seq[WindowConstructor]): owned App =
  for it, lang in languages.pairs:
    lang.id = it
  result = App(
    copy_buffer: new_copy_buffer(),
    columns: Panes[Panes[Window]](axis: AxisX),
    languages: languages,
    window_constructors: window_constructors,
    buffers: init_table[string, Buffer](),
    log: new_log()
  )

proc get_autocompleter*(app: App, language: Language): Autocompleter =
  if language.is_nil:
    return nil
  if language.make_autocompleter.is_nil:
    return nil
  if language.id notin app.autocompleters:
    let autocompleter = language.make_autocompleter(app.log)
    if autocompleter.is_nil:
      return nil
    app.autocompleters[language.id] = autocompleter
  return app.autocompleters[language.id]

proc new_buffer*(app: App, path: string): Buffer =
  if app.buffers.has_key(path):
    return app.buffers[path]
  result = new_buffer(path, app.languages)
  app.buffers[path] = result
  
  let comp = app.get_autocompleter(result.language)
  if not comp.is_nil:
    comp.track(result)

proc is_changed*(app: App, path: string): bool =
  if not app.buffers.has_key(path):
    return false
  return app.buffers[path].changed

proc list_changed*(app: App): seq[string] =
  for path in app.buffers.keys:
    if app.buffers[path].changed:
      result.add(path)

proc process_mouse*(app: App, mouse: Mouse, size: Index2d) =
  app.columns.process_mouse(mouse, Box(max: size))

proc close*(app: App) =
  for comp in app.autocompleters.values:
    comp.close()

proc process_key*(app: App, key: Key): bool =
  if has_pending_operations():
    try:
      let start = get_time()
      drain(1)
      let diff = get_time() - start
      app.log.add_info("window_manager", "Call to drain took " & $diff)
    except OSError as err:
      app.log.add_error("window_manager", err.msg)
  
  defer:
    if result:
      app.close()
  
  case app.mode:
    of AppModeNewPane:
      case key.kind:
        of KeyArrowDown:
          app.columns.split(DirDown, app)
        of KeyArrowUp:
          app.columns.split(DirUp, app)
        of KeyArrowLeft:
          app.columns.split(DirLeft, app)
        of KeyArrowRight:
          app.columns.split(DirRight, app)
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
        of KeyArrowUp: app.columns.select(DirUp)
        of KeyArrowDown: app.columns.select(DirDown)
        of KeyArrowLeft: app.columns.select(DirLeft)
        of KeyArrowRight: app.columns.select(DirRight)
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
                app.columns.close_active_window()
                return
              of Rune('p'):
                app.mode = AppModePane
                return
              else:  discard
        of KeyArrowDown:
          if key.alt and not key.shift and not key.ctrl:
            app.columns.select(DirDown)
            return
        of KeyArrowUp: 
          if key.alt and not key.shift and not key.ctrl:
            app.columns.select(DirUp)
            return
        of KeyArrowLeft:
          if key.alt and not key.shift and not key.ctrl:
            app.columns.select(DirLeft)
            return
        of KeyArrowRight:
          if key.alt and not key.shift and not key.ctrl:
            app.columns.select(DirRight)
            return
        of KeyFn:
          if key.fn == 1:
            app.open_command_search()
            return
        else: discard
      app.columns.process_key(key)
      return false

proc render*(app: App, ren: var TermRenderer) =
  ren.clear()
  app.columns.render(Box(max: ren.screen.size), ren)
