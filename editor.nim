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

import sequtils, strutils, os, sugar, times
import unicode, tables, algorithm
import utils, ui_utils, termdiff, highlight/highlight
import buffer, window_manager

# Types
type  
  # Editor
  PromptField = object
    title: string
    entry: Entry
  
  PromptKind = enum PromptNone, PromptActive, PromptInactive, PromptInfo
  
  PromptCallbackProc = proc (editor: Editor, inputs: seq[seq[Rune]])
  Prompt = object
    case kind: PromptKind:
      of PromptNone: discard
      of PromptActive, PromptInactive:
        title: string
        fields: seq[PromptField]
        selected_field: int
        callback: PromptCallbackProc
      of PromptInfo:
        lines: seq[string]

  # QuickOpen
  FileEntry = object
    name: string
    path: string
    changed: bool

  QuickOpen = ref object
    entry: Entry
    files: seq[FileEntry]
    shown_files: seq[FileEntry]
    list: List
  
  # FindDef
  FindDef = ref object
    entry: Entry
    shown_symbols: seq[Symbol]
    symbols: seq[Symbol]
    list: List
    editor: Editor
  
  # Dialog
  DialogKind = enum DialogNone, DialogQuickOpen, DialogFindDef
  Dialog = object
    case kind: DialogKind:
      of DialogNone: discard
      of DialogFindDef:
        find_def: FindDef
      of DialogQuickOpen:
        quick_open: QuickOpen
  
  # Editor
  Editor* = ref object of Window
    buffer*: Buffer
    prompt: Prompt
    dialog: Dialog
    app*: App
    scroll: Index2d
    detach_scroll: bool
    cursors*: seq[Cursor]
    jump_stack: seq[int]
    cursor_hook_id: int
    window_size: Index2d
    autocompleter: Autocompleter
    completions: seq[Symbol]
    completion_time: Time
  
  Tool* = object
    name*: string
    callback*: proc (editor: Editor)

var editor_tools*: seq[Tool]

# Dialog / QuickOpen
proc `<`(a, b: FileEntry): bool = a.name < b.name

proc is_hidden(path: string): bool =
  let dirs = path.split("/")
  for dir in dirs[0 ..< ^1]:
    if dir.startswith("."):
      return true
  return false

proc index_files(dir: string): seq[string] =
  for item in walk_dir(dir):
    case item.kind:
      of pcFile: result.add(item.path)
      of pcDir: result &= index_files(item.path)
      else: discard

proc index_project(dir: string): seq[FileEntry] =
  let paths = index_files(dir)
  return paths
    .map(path => FileEntry(
      path: path,
      name: path.relative_path(dir)
    ))
    .filter((entry: FileEntry) => not entry.name.is_hidden())
    .sorted()

proc display_name(entry: FileEntry): string =
  result = entry.name
  if entry.changed:
    result &= "*"

proc index_project(): seq[FileEntry] =
  index_project(get_current_dir())

proc update_list(quick_open: QuickOpen) =
  quick_open.shown_files = quick_open.files
    .filter(entry => ($quick_open.entry.text).to_lower() in entry.name.to_lower())
  quick_open.list.items = quick_open.shown_files
    .map(entry => entry.display_name().to_runes())
  quick_open.list.selected = quick_open.list.selected.max(0).min(quick_open.list.items.len - 1)

proc load_file(editor: Editor, path: string)
proc open_selected(quick_open: QuickOpen, editor: Editor) =
  if quick_open.list.selected < quick_open.shown_files.len and
     quick_open.list.selected >= 0:
    let path = quick_open.shown_files[quick_open.list.selected].path 
    editor.load_file(path)
    editor.dialog = Dialog(kind: DialogNone)

proc process_mouse(quick_open: QuickOpen, editor: Editor, mouse: Mouse): bool =
  var mouse_rel = mouse
  mouse_rel.x -= len("Search: ")
  mouse_rel.y -= 2

  if mouse.y == 1:
    quick_open.entry.process_mouse(mouse_rel)
    return
  elif mouse.y == 0:
    if mouse.x < len("Search:"):
      return true
    return

  case mouse.kind:
    of MouseUp:
      if quick_open.list.process_mouse(mouse_rel):
        quick_open.open_selected(editor)
    else: discard quick_open.list.process_mouse(mouse_rel)

proc process_key(quick_open: QuickOpen, editor: Editor, key: Key) =
  case key.kind:
    of KeyReturn:
      quick_open.open_selected(editor)
    of LIST_KEYS:
      quick_open.list.process_key(key)
    else:
      quick_open.entry.process_key(key)
      quick_open.update_list()

proc render(quick_open: QuickOpen, box: Box, ren: var TermRenderer) =
  ren.move_to(box.min.x, box.min.y)
  let
    label = "Search:"
    title = " ".repeat(label.len + 1) & strutils.align_left("Quick Open", box.size.x - label.len - 1)
  ren.put(title, fg=Color(base: ColorBlack), bg=Color(base: ColorWhite, bright: true))
  ren.move_to(box.min.x, box.min.y + 1)
  ren.put(label, fg=Color(base: ColorBlack), bg=Color(base: ColorWhite, bright: true))
  ren.put(" ")
  quick_open.entry.render(ren)

  for y in 2..<box.size.y:
    ren.move_to(box.min.x, y + box.min.y)
    ren.put(repeat(" ", label.len), fg=Color(base: ColorBlack), bg=Color(base: ColorWhite, bright: true))
    ren.put(" ")

  quick_open.list.render(Box(
    min: box.min + Index2d(x: label.len + 1, y: 2),
    max: box.max
  ), ren)

proc make_quick_open(app: App): owned QuickOpen =
  var
    files = index_project()
      .map(entry => FileEntry(
        path: entry.path,
        name: entry.name,
        changed: app.is_changed(entry.path)
      ))
    known_files: seq[FileEntry] = @[]
    unknown_files: seq[FileEntry] = @[]
    
  for entry in files:
    if app.languages.detect_language(entry.name) == nil:
      unknown_files.add(entry)
    else:
      known_files.add(entry)

  files = known_files & unknown_files

  return QuickOpen(
    entry: make_entry(app.copy_buffer),
    files: files,
    shown_files: files,
    list: make_list(files.map(entry => entry.display_name()))
  )

# Dialog / Find Def
proc matches(sym: Symbol, pattern: string): bool =
  let
    parts = pattern.to_lower().split(" ")
    name = to_lower($sym.name)
  result = true
  for part in parts:
    if part notin name and
       part notin $sym.kind:
      return false

proc format_sym_kind(kind: SymbolKind): string =
  result = ($kind)[len("Sym")..^1].to_lower_ascii()

proc update_list(find_def: FindDef) =
  find_def.shown_symbols = find_def.symbols.filter(def =>
    def.matches($find_def.entry.text))
  
  var kind_width = 0
  for sym in find_def.shown_symbols:
    kind_width = kind_width.max(sym.kind.format_sym_kind().len) 
  
  find_def.list.items = @[]
  for sym in find_def.shown_symbols:
    find_def.list.items.add(to_runes(
      strutils.align_left(sym.kind.format_sym_kind(), kind_width + 1) &
      $sym.name
    )) 
  
  if not find_def.list.detached:
    find_def.list.view = 0
  if find_def.list.selected >= find_def.list.items.len:
    find_def.list.selected = find_def.list.items.len - 1
  if find_def.list.selected < 0:
    find_def.list.selected = 0

proc jump*(editor: Editor, to: int)
proc jump*(editor: Editor, start, stop: int)

proc jump_to_selected(find_def: FindDef, editor: Editor) =
  if find_def.list.selected < 0 or
     find_def.list.selected >= find_def.shown_symbols.len:
    return
  let
    def = find_def.shown_symbols[find_def.list.selected]
    pos = editor.buffer.to_index(def.pos)
  editor.jump(pos)
  editor.dialog = Dialog(kind: DialogNone)

proc process_mouse(find_def: FindDef, editor: Editor, mouse: Mouse): bool =
  let sidebar_width = len("Search:")
  if mouse.x < sidebar_width and mouse.y == 0:  
    return true

  var mouse_rel = mouse
  mouse_rel.x -= sidebar_width + 1
  mouse_rel.y -= 1

  if mouse.y == 1:
    find_def.entry.process_mouse(mouse_rel)
    return
  
  mouse_rel.y -= 1
  case mouse.kind:
    of MouseUp:
      if find_def.list.process_mouse(mouse_rel):
        find_def.jump_to_selected(editor)
    else:
      discard find_def.list.process_mouse(mouse_rel)

proc process_key(find_def: FindDef, editor: Editor, key: Key) =
  case key.kind:
    of LIST_KEYS:
      find_def.list.process_key(key)
    of KeyReturn:
      find_def.jump_to_selected(editor)
    else:
      find_def.entry.process_key(key)
      find_def.update_list()

proc render(find_def: FindDef, box: Box, ren: var TermRenderer) =
  let sidebar_width = len("Search:")
  render_border("Find Definition", sidebar_width, box, ren)
  find_def.list.render(Box(
    min: box.min + Index2d(x: sidebar_width + 1, y: 2),
    max: box.max
  ), ren)
  ren.move_to(box.min + Index2d(y: 1))
  ren.put("Search:",
    fg=Color(base: ColorBlack),
    bg=Color(base: ColorWhite)
  )
  ren.move_to(box.min + Index2d(x: sidebar_width + 1, y: 1))
  find_def.entry.render(ren)

proc set_defs(find_def: FindDef, defs: seq[Symbol]) =
  find_def.symbols = defs
  find_def.update_list()

proc make_find_def(editor: Editor): FindDef =
  let find_def = FindDef(
    entry: editor.app.copy_buffer.make_entry(),
    list: make_list(),
    editor: editor
  )
  if editor.autocompleter != nil:
    editor.autocompleter.list_defs(
      editor.buffer,
      proc (defs: seq[Symbol]) =
        find_def.set_defs(defs)
    )
  return find_def

# Dialog
proc process_key(dialog: Dialog, editor: Editor, key: Key) =
  case dialog.kind:
    of DialogNone: discard
    of DialogQuickOpen: dialog.quick_open.process_key(editor, key)
    of DialogFindDef: dialog.find_def.process_key(editor, key)

proc process_mouse(dialog: Dialog, editor: Editor, mouse: Mouse): bool =
  case dialog.kind:
    of DialogNone: discard
    of DialogQuickOpen:
      return dialog.quick_open.process_mouse(editor, mouse)
    of DialogFinddef:
      return dialog.find_def.process_mouse(editor, mouse)

proc render(dialog: Dialog, box: Box, ren: var TermRenderer) =
  case dialog.kind:
    of DialogNone: discard
    of DialogQuickOpen:
      dialog.quick_open.render(box, ren)
    of DialogFindDef:
      dialog.find_def.render(box, ren)

# Prompt
proc compute_size(prompt: Prompt): int =
  case prompt.kind:
    of PromptNone: return 0
    of PromptActive, PromptInactive: return prompt.fields.len + 1
    of PromptInfo: return prompt.lines.len 

proc process_key(prompt: var Prompt, key: Key) =
  if prompt.kind != PromptActive:
    return
  
  case key.kind:
    of KeyArrowUp:
      prompt.selected_field -= 1
      if prompt.selected_field < 0:
        prompt.selected_field = 0
    of KeyArrowDown:
      prompt.selected_field += 1
      if prompt.selected_field >= prompt.fields.len:
        prompt.selected_field = prompt.fields.len - 1
    else:
      prompt.fields[prompt.selected_field].entry.process_key(key)

# Editor
proc get_inputs(prompt: Prompt): seq[seq[Rune]] =
  prompt.fields.map(field => field.entry.text)

proc show_info*(editor: Editor, lines: seq[string]) =
  editor.prompt = Prompt(kind: PromptInfo, lines: lines) 

proc show_prompt*(editor: Editor,
                  title: string,
                  fields: seq[string], 
                  callback: PromptCallbackProc = nil) =
  editor.prompt = Prompt(
    kind: PromptActive,
    title: title,
    selected_field: 0,
    fields: fields.map(title => PromptField(
      title: title,
      entry: make_entry(editor.app.copy_buffer)
    )),
    callback: callback
  )
  editor.completions = @[]

proc hide_prompt*(editor: Editor) = 
  editor.prompt = Prompt(kind: PromptNone)

proc primary_cursor*(editor: Editor): Cursor = editor.cursors[^1]

proc merge_cursors(editor: Editor) =
  editor.cursors = editor.cursors.merge_cursors()

proc update_cursor(editor: Editor, index: int, pos_raw: int, shift: bool) =
  let pos = max(min(pos_raw, editor.buffer.len), 0)
  case editor.cursors[index].kind:
    of CursorInsert:
      if shift:
        editor.cursors[index] = Cursor(
          kind: CursorSelection,
          start: editor.cursors[index].pos,
          stop: pos
        )
      else:
        editor.cursors[index].pos = pos
    of CursorSelection:
      if shift:
        editor.cursors[index].stop = pos
      else:
        editor.cursors[index] = Cursor(kind: CursorInsert, pos: pos)  
  
proc is_under_cursor(editor: Editor, pos: int): bool =
  for cursor in editor.cursors:
    if cursor.is_under(pos):
      return true
  return false
  
proc make_cursor_hook(editor: Editor): CursorHook =
  return proc (start: int, delta: int) {.closure.} =
    for it, cursor in editor.cursors:
      case cursor.kind:
        of CursorInsert:
          if cursor.pos >= start:
            editor.cursors[it].pos += delta
        of CursorSelection:
          if cursor.start >= start:
            editor.cursors[it].start += delta
          if cursor.stop >= start:
            editor.cursors[it].stop += delta
    
proc update_scroll(editor: Editor, size: Index2d, detach: bool) =
  let pos = editor.buffer.to_2d(editor.primary_cursor().get_pos())
  
  if not detach:
    while (pos.y - editor.scroll.y) < 4:
      editor.scroll.y -= 1
    while (pos.y - editor.scroll.y) >= size.y - 4:
      editor.scroll.y += 1
      
  editor.scroll.y = max(editor.scroll.y, 0).min(editor.buffer.lines.len)

proc jump*(editor: Editor, to: int) =
  editor.jump_stack.add(editor.primary_cursor().get_pos())
  editor.cursors = @[Cursor(kind: CursorInsert, pos: to)]
  editor.completions = @[]
  editor.completion_time = get_time()

proc jump*(editor: Editor, start, stop: int) =
  editor.jump_stack.add(editor.primary_cursor().get_pos())
  editor.cursors = @[Cursor(kind: CursorSelection, start: start, stop: stop)]
  editor.completions = @[]
  editor.completion_time = get_time()

proc goto_line(editor: Editor, inputs: seq[seq[Rune]]) =
  var line: int
  
  try:
    line = parse_int($inputs[0]) - 1
  except ValueError:
    editor.show_info(@["Not a number: " & $inputs[0]])
    return
  
  if line == -1:
    editor.show_info(@["Invalid line: " & $(line + 1)])
    return
  elif line >= editor.buffer.lines.len:
    editor.show_info(@["Invalid line: " & $(line + 1)])
    return

  if line < -1:
    line = editor.buffer.lines.len + line + 1
    
  editor.jump(editor.buffer.lines[line])
  editor.hide_prompt()

proc find_pattern(editor: Editor, inputs: seq[seq[Rune]]) =
  var pos = editor.buffer.text.find(inputs[0], editor.primary_cursor().get_pos + 1)
  if pos == -1:
    pos = editor.buffer.text.find(inputs[0])
  if pos != -1:
    editor.jump(pos)

proc set_indent_width(editor: Editor, inputs: seq[seq[Rune]]) =
  try:
    let width = parse_int($inputs[0])
    if width <= 1:
      editor.show_info(@["Invalid Indent Width: " & $inputs[0]])
      return
    editor.buffer.indent_width = width
    editor.hide_prompt()
  except ValueError:
    editor.show_info(@["Invalid Indent Width: " & $inputs[0]])

proc save_as(editor: Editor, inputs: seq[seq[Rune]]) =
  if inputs[0].len == 0:
    return
  
  let
    path = absolute_path($inputs[0])
    (dir, file) = split_path(path)
  if not exists_dir(dir):
    editor.show_info(@[dir & " does not exist"])
    return
  if editor.buffer.file_path != "" and
     editor.buffer.file_path in editor.app.buffers:
    editor.app.buffers.del(editor.buffer.file_path)
  editor.buffer.set_path(path, editor.app.languages)
  editor.app.buffers[path] = editor.buffer
  try:
    editor.buffer.save()
  except IOError as err:
    editor.show_info(@["Error: " & err.msg])
    return
  editor.hide_prompt()

  let comp = editor.app.get_autocompleter(editor.buffer.language)
  if not comp.is_nil:
    editor.autocompleter = comp
    comp.track(editor.buffer)

proc select_all(editor: Editor) =
  editor.cursors = @[Cursor(
    kind: CursorSelection,
    start: 0,
    stop: editor.buffer.len
  )]

proc delete_selections(editor: Editor) =
  for it, cursor in editor.cursors:
    if cursor.kind != CursorSelection:
      continue
    
    let cur = cursor.sort()
    editor.buffer.delete(cur.start, cur.stop)
    editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.start)
  
proc copy(editor: Editor) =
  for cursor in editor.cursors:
    if cursor.kind == CursorSelection:
      let
        cur = cursor.sort()
        text = editor.buffer.slice(cur.start, cur.stop)
      editor.app.copy_buffer.copy(text)

proc insert(editor: Editor, chr: Rune) =
  for it, cursor in editor.cursors:
    case cursor.kind:
      of CursorInsert:
        editor.buffer.insert(cursor.pos, chr)
      of CursorSelection:
        let cur = cursor.sort()
        editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.start + 1)
        editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.stop)
        editor.buffer.replace(cur.start, cur.stop, @[chr])
        
proc insert(editor: Editor, str: seq[Rune]) =
  for it, cursor in editor.cursors:
    case cursor.kind:
      of CursorInsert:
        editor.buffer.insert(cursor.pos, str)
      of CursorSelection:
        let cur = cursor.sort()
        editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.stop)
        editor.buffer.replace(cur.start, cur.stop, str)
        
proc load_file(editor: Editor, path: string) =
  editor.buffer.unregister_hook(editor.cursor_hook_id)
  editor.buffer = editor.app.new_buffer(path)
  editor.cursor_hook_id = editor.buffer.register_hook(editor.make_cursor_hook())
  editor.hide_prompt()
  editor.cursors = @[Cursor(kind: CursorInsert, pos: 0)]
  editor.autocompleter = editor.app.get_autocompleter(editor.buffer.language)

proc new_buffer(editor: Editor) =
  editor.buffer.unregister_hook(editor.cursor_hook_id)
  editor.buffer = new_buffer()
  editor.cursor_hook_id = editor.buffer.register_hook(editor.make_cursor_hook())
  editor.hide_prompt()
  editor.cursors = @[Cursor(kind: CursorInsert, pos: 0)]
  editor.autocompleter = nil

proc completion_query(editor: Editor): seq[Rune] =
  if editor.autocompleter == nil:
    return
  var pos = editor.primary_cursor().get_pos() - 1
  while pos >= 0 and
        editor.buffer[pos] notin editor.autocompleter.triggers and
        editor.buffer[pos] notin editor.autocompleter.finish:
    result = editor.buffer[pos] & result
    pos -= 1

proc filter_completions(editor: Editor): seq[Symbol] =
  if editor.completions.len == 0:
    return @[]
  let query = editor.completion_query()
  if query.len == 0:
    return editor.completions
  return editor.completions.search(query)

proc compute_line_numbers_width(editor: Editor): int
method process_mouse(editor: Editor, mouse: Mouse): bool =
  if editor.dialog.kind != DialogNone:
    return editor.dialog.process_mouse(editor, mouse)

  editor.detach_scroll = true
  let
    line_numbers_width = editor.compute_line_numbers_width() + 1
    prompt_size = editor.prompt.compute_size()
    pos = editor.scroll + Index2d(x: mouse.x - line_numbers_width - 1, y: mouse.y - 1)
  
  if mouse.y >= editor.window_size.y - prompt_size:
    let field = mouse.y - (editor.window_size.y - prompt_size) - 1
    
    if editor.prompt.kind != PromptActive and
       editor.prompt.kind != PromptInactive:
      return

    case mouse.kind:
      of MouseDown:
        editor.prompt.kind = PromptActive
        if mouse.button == 0:
          if field >= 0 and field < editor.prompt.fields.len:
            editor.prompt.selected_field = field
            var mouse_rel = mouse
            mouse_rel.x = mouse.x - editor.prompt.fields[field].title.len
            mouse_rel.y = 0
            editor.prompt.fields[field].entry.process_mouse(mouse_rel)
      of MouseMove, MouseUp:
        let selected = editor.prompt.selected_field
        var mouse_rel = mouse
        mouse_rel.x = mouse.x - editor.prompt.fields[selected].title.len
        mouse_rel.y = 0
        editor.prompt.fields[selected].entry.process_mouse(mouse_rel)
      else: discard
    return
  elif mouse.y == 0:
    if mouse.x < line_numbers_width:
      return true
    return
  
  case mouse.kind:
    of MouseDown:
      if mouse.button == 0:
        case mouse.clicks:
          of 1:
            editor.jump(editor.buffer.display_to_index(Index2d(
              x: pos.x.max(0),
              y: pos.y.min(editor.buffer.lines.len - 1).max(0)
            )))
          of 2:
            let
              index = editor.buffer.display_to_index(Index2d(
                x: pos.x.max(0),
                y: pos.y.min(editor.buffer.lines.len - 1).max(0)
              ))
              (start, stop) = editor.buffer.word_range(index)
            editor.jump(start, stop)
          of 3:
            let  
              line = pos.y.min(editor.buffer.lines.len - 1).max(0)
              (start, stop) = editor.buffer.line_range(line)
            if start != -1 and stop != -1:
              editor.jump(start, stop)
          else: discard
        
        if editor.prompt.kind == PromptActive:
          editor.prompt.kind = PromptInactive
    of MouseUp, MouseMove:
      if (mouse.kind == MouseUp and
          mouse.button == 0 and
          mouse.clicks == 1) or
         (mouse.kind == MouseMove and mouse.buttons[0]):
        let stop = editor.buffer.display_to_index(Index2d(
          x: pos.x.max(0),
          y: pos.y.min(editor.buffer.lines.len - 1).max(0)
        ))
        case editor.primary_cursor().kind:
          of CursorInsert:
            let start = editor.primary_cursor().pos
            if start != stop:
              editor.cursors = @[Cursor(kind: CursorSelection, start: start, stop: stop)]
          of CursorSelection:
            let start = editor.primary_cursor().start
            editor.cursors = @[Cursor(kind: CursorSelection, start: start, stop: stop)]
    of MouseScroll:
      editor.scroll.y += mouse.delta * 2
    else: discard

proc select_next(editor: Editor) =
  if editor.primary_cursor().kind == CursorSelection:
    let
      cur = editor.primary_cursor().sort()
      text = editor.buffer.slice(cur.start, cur.stop)
    var pos = editor.buffer.text.find(text, cur.stop)
    if pos == -1:
      pos = editor.buffer.text.find(text)
    if pos != -1 and pos != cur.start:
      editor.cursors.add(Cursor(kind: CursorSelection, start: pos, stop: pos + text.len))
      editor.merge_cursors()

proc jump_back(editor: Editor) =
  if editor.jump_stack.len > 0:
    editor.cursors = @[Cursor(kind: CursorInsert, pos: editor.jump_stack.pop())]

proc cut(editor: Editor) =
  editor.copy()
  editor.delete_selections()

proc paste(editor: Editor) =
  editor.delete_selections()
  editor.insert(editor.app.copy_buffer.paste())

proc show_find(editor: Editor) =
  editor.show_prompt("Find", @["Pattern: "], callback=find_pattern)

proc show_goto(editor: Editor) =
  editor.show_prompt("Go to Line", @["Line: "], callback=goto_line)

proc show_set_indent_width(editor: Editor) =
  editor.show_prompt(
    "Set Indent Width",
    @["Width: "],
    callback=set_indent_width
  )

proc show_save_as(editor: Editor) =
  editor.show_prompt(
    "Save As",
    @["File Name:"],
    callback=proc (editor: Editor, inputs: seq[seq[Rune]]) =
      let path = $inputs[0]
      if exists_file(path):
        editor.show_prompt(
          "A file named " & path &
          " already exists. Do you want to replace it?",
          @["Replace (y/n): "],
          callback=proc (editor: Editor, replace_inputs: seq[seq[Rune]]) =
            if to_lower($replace_inputs[0]).starts_with("y"):
              editor.save_as(inputs)
            else:
              editor.hide_prompt()
        )
      else:
        editor.save_as(inputs)
  )

proc save(editor: Editor) =
  if editor.buffer.file_path == "":
    editor.show_save_as()
  else:
    try:
      editor.buffer.save()
    except IOError as err:
      editor.show_info(@["Error: " & err.msg])
      return
    editor.show_info(@["File saved."])

proc show_quick_open(editor: Editor) =
  editor.dialog = Dialog(
    kind: DialogQuickOpen,
    quick_open: make_quick_open(editor.app)
  )

proc show_find_def(editor: Editor) =
  editor.dialog = Dialog(
    kind: DialogFindDef,
    find_def: make_find_def(editor)
  )

proc only_primary_cursor(editor: Editor) =
  var cur = editor.primary_cursor()
  editor.cursors = @[cur]

proc pop_cursor(editor: Editor) =
  if editor.cursors.len > 1:
    discard editor.cursors.pop()

proc jump_to_matching_brackets(editor: Editor, select: bool = false) =
  for cursor in editor.cursors.mitems:
    if cursor.kind != CursorInsert:
      continue
    let match_pos = editor.buffer.match_bracket(cursor.pos)
    if match_pos != -1:
      if select:
        cursor = Cursor(kind: CursorSelection,
          start: cursor.pos, stop: match_pos
        )
        if cursor.start < cursor.stop:
          cursor.stop += 1
        else:
          cursor.start += 1
      else:
        cursor = Cursor(kind: CursorInsert,
          pos: match_pos
        )

proc trigger_autocomplete(editor: Editor, chr: Rune) =
  let 
    pos = editor.primary_cursor().get_pos()
    start_time = get_time()
  editor.autocompleter.complete(
    editor.buffer, pos, chr,
    proc (comps: seq[Symbol]) =
      if editor.completion_time > start_time:
        return
      editor.completions = comps
      editor.completion_time = start_time
  )

method process_key(editor: Editor, key: Key) = 
  if editor.autocompleter != nil:
    editor.autocompleter.poll()

  if key.kind != KeyUnknown and key.kind != KeyNone:
    editor.detach_scroll = false

  if key.kind == KeyChar and key.ctrl and key.chr == Rune('e'):
    if editor.dialog.kind != DialogNone:
      editor.dialog = Dialog(kind: DialogNone)
    elif editor.prompt.kind != PromptNone:
      editor.hide_prompt()
    else:
      editor.completions = @[]
      editor.completion_time = get_time()
    return

  if editor.dialog.kind != DialogNone:
    editor.dialog.process_key(editor, key)
    return
  elif editor.prompt.kind == PromptActive:
    if key.kind == KeyReturn:
      editor.prompt.callback(editor, editor.prompt.get_inputs())
      return
  
    editor.prompt.process_key(key)
    return
  
  defer: editor.buffer.finish_undo_frame()
  
  var clear_completions = true
  case key.kind:
    of KeyArrowLeft:
      for it, cursor in editor.cursors:
        var delta = -1
        if key.ctrl:
          delta = (editor.buffer.skip(cursor.get_pos() - 1, -1) + 1) - cursor.get_pos()
        update(editor.cursors[it], delta, editor.buffer.len, key.shift)
    of KeyArrowRight:
      for it, cursor in editor.cursors:
        var delta = 1
        if key.ctrl:
          delta = (editor.buffer.skip(cursor.get_pos(), 1)) - cursor.get_pos()
        update(editor.cursors[it], delta, editor.buffer.len, key.shift)
    of KeyArrowUp:
      if key.ctrl and key.alt:
        return
      if key.alt and key.shift:
        var index = editor.buffer.to_2d(editor.primary_cursor().get_pos())
        while true:
          index.y -= 1
          if index.y < 0:
            break
          let cursor = Cursor(kind: CursorInsert, pos: editor.buffer.to_index(index))
          if cursor notin editor.cursors:
            editor.cursors.add(cursor)
            break
      else:
        for it, cursor in editor.cursors:
          var index = editor.buffer.to_2d(cursor.get_pos())
          index.y -= 1
          index.y = max(index.y, 0)
          editor.update_cursor(it, editor.buffer.to_index(index), key.shift)
    of KeyArrowDown:
      if key.ctrl and key.alt:
        return
      if key.alt and key.shift:
        var index = editor.buffer.to_2d(editor.primary_cursor().get_pos())
        while true:
          index.y += 1
          if index.y > editor.buffer.lines.len - 1:
            break 
          let cursor = Cursor(kind: CursorInsert, pos: editor.buffer.to_index(index))
          if cursor notin editor.cursors:
            editor.cursors.add(cursor)
            break
      else:
        for it, cursor in editor.cursors:
          var index = editor.buffer.to_2d(cursor.get_pos())
          index.y += 1
          index.y = min(index.y, editor.buffer.lines.len - 1)
          editor.update_cursor(it, editor.buffer.to_index(index), key.shift)
    of KeyReturn:
      for it, cursor in editor.cursors:
        if cursor.kind == CursorSelection:
          continue
        let
          indent_level = editor.buffer.indentation(cursor.pos)
          indent = editor.buffer.make_indent(indent_level)
        editor.buffer.insert(cursor.pos, editor.buffer.newline_style.to_runes() & indent)
    of KeyPageDown:
      for it, cursor in editor.cursors:
        var pos = editor.buffer.to_2d(cursor.get_pos())
        pos.y += editor.window_size.y
        pos.y = pos.y.min(editor.buffer.lines.len - 1)
        editor.update_cursor(it, editor.buffer.to_index(pos), key.shift)
    of KeyPageUp:
      for it, cursor in editor.cursors:
        var pos = editor.buffer.to_2d(cursor.get_pos())
        pos.y -= editor.window_size.y
        pos.y = pos.y.max(0)
        editor.update_cursor(it, editor.buffer.to_index(pos), key.shift)
    of KeyHome:
      for it, cursor in editor.cursors:
        var index = editor.buffer.to_2d(cursor.get_pos())
        index.x = 0
        editor.update_cursor(it, editor.buffer.to_index(index), key.shift)
    of KeyEnd:
      for it, cursor in editor.cursors:
        var index = editor.buffer.to_2d(cursor.get_pos())
        if index.y == editor.buffer.lines.len - 1:
          editor.cursors[it] = Cursor(kind: CursorInsert, pos: editor.buffer.len)  
          continue
        
        index.y += 1
        index.y = min(index.y, editor.buffer.lines.len - 1)
        index.x = 0
        let pos = (editor.buffer.to_index(index) - 1).max(0)
        editor.update_cursor(it, pos, key.shift)
    of KeyBackspace:
      clear_completions = false
      for it, cursor in editor.cursors:
        case cursor.kind
          of CursorSelection:
            let cur = cursor.sort()
            if editor.completions.len > 0 and editor.autocompleter != nil and not clear_completions:
              for chr in editor.buffer.text.substr(cur.start, cur.stop):
                if chr in editor.autocompleter.triggers:
                  clear_completions = true
                  break
            editor.buffer.delete(cur.start, cur.stop)
            editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.start)
          of CursorInsert:
            if cursor.pos > 0:
              if editor.completions.len > 0 and editor.autocompleter != nil and not clear_completions:
                for chr in editor.buffer.text.substr(cursor.pos - 1, cursor.pos):
                  if chr in editor.autocompleter.triggers:
                    clear_completions = true
                    break
              editor.buffer.delete(cursor.pos - 1, cursor.pos)
    of KeyDelete:
      for it, cursor in editor.cursors:
        case cursor.kind:
          of CursorSelection:
            let cur = cursor.sort()
            editor.buffer.delete(cur.start, cur.stop)
            editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.start)
          of CursorInsert:
            if cursor.pos >= editor.buffer.len:
              continue
            editor.buffer.delete(cursor.pos, cursor.pos + 1)
    of KeyEscape:
      editor.only_primary_cursor()
    of KeyPaste:
      editor.insert(key.text)
    of KeyChar:
      if key.ctrl:
        case key.chr:
          of Rune('i'):
            let comps = editor.filter_completions()
            if comps.len > 0:
              let
                text = comps[0].name
                query = editor.completion_query()
              for cursor in editor.cursors:
                if cursor.kind != CursorInsert:
                  continue
                editor.buffer.replace(cursor.pos - query.len, cursor.pos, text)
            else:
              for cursor in editor.cursors:
                case cursor.kind:
                  of CursorInsert:
                    editor.buffer.indent(cursor.pos)
                  of CursorSelection:
                    let cur = cursor.sort()
                    editor.buffer.indent(cur.start, cur.stop)
          of Rune('I'):
            for cursor in editor.cursors:
              case cursor.kind:
                of CursorInsert:  
                  editor.buffer.unindent_line(editor.buffer.to_2d(cursor.pos).y)
                of CursorSelection:
                  let cur = cursor.sort()
                  editor.buffer.unindent(cur.start, cur.stop)
          of Rune('a'): editor.select_all()
          of Rune('t'): editor.show_quick_open()
          of Rune('s'): editor.save()
          of Rune('n'): editor.new_buffer()
          of Rune('r'): editor.show_find_def()
          of Rune('f'): editor.show_find()
          of Rune('g'): editor.show_goto()
          of Rune('v'): editor.paste()
          of Rune('c'): editor.copy()
          of Rune('x'): editor.cut()
          of Rune('b'): editor.jump_back()
          of Rune('d'): editor.select_next()
          of Rune('u'): editor.pop_cursor()
          of Rune('z'): editor.buffer.undo()
          of Rune('y'): editor.buffer.redo()
          of Rune('o'): editor.jump_to_matching_brackets(key.shift)
          else: discard
      else:
        editor.insert(key.chr)
        clear_completions = false
        if editor.autocompleter != nil:
          if key.chr in editor.autocompleter.triggers:
            editor.trigger_autocomplete(key.chr)
          elif key.chr in editor.autocompleter.finish:
            clear_completions = true
          elif editor.autocompleter.min_word_len != 0 and
               editor.completion_query().len >= editor.autocompleter.min_word_len:
            editor.trigger_autocomplete(key.chr)
    of KeyFn:
      case key.fn:
        of 2:
          if editor.autocompleter != nil:
            editor.trigger_autocomplete(Rune(' '))
            clear_completions = false
        else: discard
    of KeyUnknown, KeyNone: clear_completions = false
    else: discard
  if clear_completions:
    editor.completions = @[]
    editor.completion_time = get_time()
  editor.merge_cursors()

proc to_command(tool: Tool, editor: Editor): Command =
  return Command(
    name: tool.name,
    cmd: () => tool.callback(editor)
  )

proc to_commands(tools: seq[Tool], editor: Editor): seq[Command] =
  for tool in tools:
    result.add(to_command(tool, editor))

method list_commands(editor: Editor): seq[Command] =
  return @[
    Command(
      name: "Undo",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('z'))],
      cmd: () => editor.buffer.undo()
    ),
    Command(
      name: "Redo",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('y'))],
      cmd: () => editor.buffer.redo()
    ),
    Command(
      name: "Select All",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('a'))],
      cmd: () => editor.select_all()
    ),
    Command(
      name: "Quick Open",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('t'))],
      cmd: () => editor.show_quick_open()
    ),
    Command(
      name: "Find Definition",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('r'))],
      cmd: () => editor.show_find_def()
    ),
    Command(
      name: "Save",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('s'))],
      cmd: () => editor.save()
    ),
    Command(
      name: "Save As",
      cmd: () => editor.show_save_as()
    ),
    Command(
      name: "New Buffer",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('n'))],
      cmd: () => editor.new_buffer()
    ),
    Command(
      name: "Find",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('f'))],
      cmd: () => editor.show_find()
    ),
    Command(
      name: "Go to Line",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('g'))],
      cmd: () => editor.show_goto()
    ),
    Command(
      name: "Paste",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('v'))],
      cmd: () => editor.paste()
    ),
    Command(
      name: "Copy",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('c'))],
      cmd: () => editor.copy()
    ),
    Command(
      name: "Cut",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('x'))],
      cmd: () => editor.cut()
    ),
    Command(
      name: "Jump Back",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('b'))],
      cmd: () => editor.jump_back()
    ),
    Command(
      name: "Select Next",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('d'))],
      cmd: () => editor.select_next()
    ),
    Command(
      name: "Remove Last Cursor",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('u'))],
      cmd: () => editor.pop_cursor()
    ),
    Command(
      name: "Only Primary Cursor",
      cmd: () => editor.only_primary_cursor()
    ),
    Command(
      name: "Set Indent Width",
      cmd: () => editor.show_set_indent_width()
    ),
    Command(
      name: "Jump to Matching Brackets",
      shortcut: @[Key(kind: KeyChar, ctrl: true, chr: Rune('o'))],
      cmd: () => editor.jump_to_matching_brackets()
    ),
    Command(
      name: "Select Brackets",
      shortcut: @[Key(kind: KeyChar, ctrl: true, shift: true, chr: Rune('o'))],
      cmd: () => editor.jump_to_matching_brackets(true)
    )
  ] & editor_tools.to_commands(editor)

proc compute_line_numbers_width(editor: Editor): int =
  var max_line_number = editor.buffer.lines.len
  while max_line_number != 0:
    result += 1
    max_line_number = max_line_number div 10

proc compute_width(comps: seq[Symbol]): int =
  for comp in comps:
    result = max(result, comp.name.len + 1)

const
  CHAR_VERTICAL = to_runes("│")[0]
  CHAR_INDENT = to_runes("»")[0]
  CHAR_CR = to_runes("←")[0]

method render(editor: Editor, box: Box, ren: var TermRenderer) =
  if editor.dialog.kind != DialogNone:
    editor.dialog.render(box, ren)
    return
  
  let
    line_numbers_width = editor.compute_line_numbers_width() + 1
    prompt_size = editor.prompt.compute_size()
  
  editor.window_size = box.size
  editor.update_scroll(box.size - Index2d(x: line_numbers_width + 1, y: prompt_size), editor.detach_scroll)
  
  # Render title
  ren.moveTo(box.min)
  let
    title = editor.buffer.display_file_name()
    title_aligned = strutils.align_left(title, (box.size.x - 1 - line_numbers_width).max(0))
    title_output = repeat(' ', line_numbers_width + 1) & title_aligned
  ren.put(
    title_output,
    fg=Color(base: ColorBlack, bright: false),
    bg=Color(base: ColorWhite, bright: true)
  )
  
  # Render line numbers
  for y in 0..<(box.size.y - prompt_size - 1):
    let it = y + editor.scroll.y
    if it >= editor.buffer.lines.len:
      ren.move_to(box.min.x, box.min.y + y + 1)
      ren.put(
        repeat(' ', line_numbers_width),
        fg = Color(base: ColorBlack),
        bg = Color(base: ColorWhite, bright: true)
      )
    else:
      ren.move_to(box.min.x, box.min.y + y + 1)
      ren.put(
        align($(it + 1), line_numbers_width, padding=' '),
        fg = Color(base: ColorBlack),
        bg = Color(base: ColorWhite, bright: true)
      )

  # Render text
  var bracket_matches: seq[int] = @[]
  for cursor in editor.cursors:
    if cursor.kind == CursorInsert:
      let match = editor.buffer.match_bracket(cursor.pos)
      if match != -1:
        bracket_matches.add(match)
  
  var current_token = 0
  var
    shifts = init_table[int, int]()
    display_shifts = init_table[int, int]()
  
  block:
    let width = box.size.x - line_numbers_width - 1
    if width <= 0:
      break
    for cursor in editor.cursors:
      var pos = editor.buffer.to_display_2d(cursor.get_pos())
      shifts[pos.y] = 0
      display_shifts[pos.y] = 0
      var stopped = false
      while pos.x >= width and not stopped:
        let initial_x = pos.x
        while abs(pos.x - initial_x) < width:
          let index = editor.buffer.lines[pos.y] + shifts[pos.y]
          if index > editor.buffer.text.len:
            stopped = true
            break
          let chr = editor.buffer.text[index]
          case chr:
            of '\t':
              pos.x -= editor.buffer.indent_width
            of '\n':
              stopped = true
              break
            else:
              pos.x -= 1
          shifts[pos.y] += 1
        display_shifts[pos.y] += abs(pos.x - initial_x)
  
  for y in 0..<(box.size.y - prompt_size - 1):
    let it = y + editor.scroll.y
    
    if it >= editor.buffer.lines.len:
      break
    
    var
      index = editor.buffer.lines[it]
      reached_end = false
      is_indent = true
      x = 0
    
    var index_shift = 0
    if it in shifts:
      index_shift = shifts[it]
    index += index_shift
    x += index_shift
    
    if index_shift !=  0:
      ren.move_to(line_numbers_width + box.min.x, y + box.min.y + 1)
      ren.put('<', fg=Color(base: ColorWhite), bg=Color(base: ColorRed))
    else:
      ren.move_to(line_numbers_width + 1 + box.min.x, y + box.min.y + 1)

    while editor.buffer.get_token(current_token).kind != TokenNone and
          editor.buffer.get_token(current_token).stop < index:
      current_token += 1
    
    while index < editor.buffer.len and editor.buffer[index] != '\n':
      if index - editor.buffer.lines[it] + line_numbers_width + 1 - index_shift >= box.size.x:
        reached_end = true
        break
      
      var
        chr = editor.buffer[index]
        fg = Color(base: ColorDefault, bright: false)
      
      if chr != ' ' and chr != '\t':
        is_indent = false
      
      if chr == '\t':
        let indent_width = editor.buffer.indent_width
        if editor.is_under_cursor(index):
          for it in 0..<indent_width:
            ren.put(' ', reverse=true)
        else:
          let fg = Color(base: ColorBlack, bright: true)
          ren.put(CHAR_INDENT, fg=fg)
          for it in 0..<(indent_width - 2):
            ren.put(' ', fg=fg)
          ren.put(CHAR_VERTICAL, fg=fg)
        index += 1
        x += indent_width
        continue
      elif chr == '\r' and fg.base == ColorDefault:
        if editor.is_under_cursor(index):
          ren.put(' ', reverse=true)
        else:
          let fg = Color(base: ColorBlack, bright: true)
          ren.put(CHAR_CR, fg=fg)
        index += 1
        x += 1
        continue
      elif chr == '\0':
        if editor.is_under_cursor(index):
          ren.put('0', reverse=true, bg=Color(base: ColorRed, bright: true))
        else:
          ren.put('0',
            fg=Color(base: ColorWhite, bright: true),
            bg=Color(base: ColorRed, bright: true)
          )
        index += 1
        x += 1
        continue
      
      if editor.is_under_cursor(index):
        ren.put(editor.buffer[index], reverse=true)
        index += 1
        x += 1
        continue
      elif index in bracket_matches:
        ren.put(editor.buffer[index], fg=Color(base: ColorBlack), bg=Color(base: ColorRed, bright: true))
        index += 1
        x += 1
        continue
          
      while editor.buffer.get_token(current_token).kind != TokenNone and
            index >= editor.buffer.get_token(current_token).stop:
        current_token += 1
      
      if editor.buffer.get_token(current_token).kind != TokenNone:
        let token = editor.buffer.get_token(current_token)
        if token.is_inside(index):
          fg = token.color()
      
      if chr == ' ' and fg.base == ColorDefault:
        let indent_width = editor.buffer.indent_width
        if x mod indent_width == indent_width - 1 and is_indent:
          chr = CHAR_VERTICAL
        else:
          chr = '.'
        fg = Color(base: ColorBlack, bright: true)

      ren.put(chr, fg=fg)
      index += 1
      x += 1
    if index - editor.buffer.lines[it] + line_numbers_width + 1 - index_shift >= box.size.x:
      reached_end = true
    
    if editor.is_under_cursor(index) and (not reached_end):
      ren.put(' ', reverse=true)
  
  # Render Completions
  let
    comps = editor.filter_completions()
    comp_width = comps.compute_width()
  var pos = editor.buffer.to_display_2d(editor.primary_cursor().get_pos()) + box.min
  let completion_line = pos.y
  pos.y -= editor.scroll.y - 1
  pos.x += line_numbers_width - 1
  
  const MAX_COMPS = 4
  for it, comp in comps:
    if it >= MAX_COMPS:
      break
    
    var p = pos + Index2d(y: it + 1)
    if completion_line in display_shifts:
      p.x -= display_shifts[completion_line]
    
    if p.y <= 0:
      continue
    if p.y >= box.max.y - prompt_size:
      break
    ren.move_to(p)
    var
      bg_color = Color(base: ColorBlack)
      fg_color = Color(base: ColorWhite)
      kind_chr: Rune = '.'
    case comp.kind:
      of SymProc:
        kind_chr = 'p'
        bg_color = Color(base: ColorRed)
      of SymFunc:
        kind_chr = 'f'
        bg_color = Color(base: ColorRed)
      of SymConverter:
        kind_chr = 'c'
        bg_color = Color(base: ColorRed)
      of SymMethod:
        kind_chr = 'm'
        bg_color = Color(base: ColorRed)
      of SymTemplate:
        kind_chr = 't'
        bg_color = Color(base: ColorRed)
      of SymIterator:
        kind_chr = 'i'
        bg_color = Color(base: ColorRed)
      of SymMacro:
        kind_chr = 'm'
        bg_color = Color(base: ColorRed)
      of SymConst:
        kind_chr = 'c'
        bg_color = Color(base: ColorYellow)
      of SymLet:
        kind_chr = 'l'
        bg_color = Color(base: ColorYellow)
      of SymVar:
        kind_chr = 'v'
        bg_color = Color(base: ColorYellow)
      of SymType:
        kind_chr = 't'
        bg_color = Color(base: ColorCyan)
      of SymField:
        kind_chr = 'f'
        bg_color = Color(base: ColorCyan)
      of SymEnum:
        kind_chr = 'e'
        bg_color = Color(base: ColorCyan)
      of SymTag:
        kind_chr = 't'
        bg_color = Color(base: ColorRed)
      else: discard
    if bg_color.base == ColorYellow:
      fg_color.base = ColorBlack
    ren.put($kind_chr & " ", fg=fg_color, bg=bg_color)
    let padding = sequtils.repeat(Rune(' '), comp_width - comp.name.len - 1)
    if it == 0:
      ren.put(comp.name & padding, reverse=true)
    else:
      ren.put(comp.name & padding, fg=Color(base:ColorWhite), bg=Color(base:ColorBlack))

  # Render prompt
  case editor.prompt.kind:
    of PromptInfo:
      for it, line in editor.prompt.lines:
        ren.move_to(box.min.x, box.min.y + box.size.y - prompt_size + it)
        ren.put(
          strutils.repeat(' ', line_numbers_width + 1) & strutils.align_left(line, max(box.size.x - line_numbers_width - 1, 0)),
          fg=Color(base: ColorBlack, bright: false),
          bg=Color(base: ColorWhite, bright: true)
        )
    of PromptActive, PromptInactive:
      ren.move_to(box.min.x, box.min.y + box.size.y - prompt_size)
      ren.put(
        repeat(' ', line_numbers_width + 1) & strutils.align_left(editor.prompt.title, box.size.x - line_numbers_width - 1),
        fg=Color(base: ColorBlack, bright: false),
        bg=Color(base: ColorWhite, bright: true)
      )
      
      for it, field in editor.prompt.fields:
        ren.move_to(box.min.x, box.min.y + box.size.y - prompt_size + it + 1)
        ren.put(field.title)
        if it == editor.prompt.selected_field:
          field.entry.render(ren)
        else:
          ren.put(field.entry.text)
    else:
      discard
  

method close*(editor: Editor) =
  editor.buffer.unregister_hook(editor.cursor_hook_id)  

proc new_editor*(app: App, buffer: Buffer): Editor =
  result = Editor(
    buffer: buffer,
    scroll: Index2d(x: 0, y: 0),
    cursors: @[Cursor(kind: CursorInsert, pos: 0)],
    app: app
  )
  result.cursor_hook_id = result.buffer.register_hook(result.make_cursor_hook())
  result.autocompleter = app.get_autocompleter(result.buffer.language)

proc new_editor*(app: App): Window =
  new_editor(app, new_buffer())

proc new_editor*(app: App, path: string): Window =
  new_editor(app, app.new_buffer(path))
