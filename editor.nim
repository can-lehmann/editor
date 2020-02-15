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

import sequtils, strutils, os, sugar, streams, deques, unicode, sets, hashes, tables
import utils, ui_utils, termdiff, highlight, buffer, window_manager, autocomplete

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
    selected: int
  
  # Dialog
  DialogKind = enum DialogNone, DialogQuickOpen
  Dialog = object
    case kind: DialogKind:
      of DialogNone: discard
      of DialogQuickOpen:
        quick_open: QuickOpen
  
  # Editor
  Editor = ref object of Window
    buffer: Buffer
    prompt: Prompt
    dialog: Dialog
    app: App
    scroll: Index2d
    cursors: seq[Cursor]
    jump_stack: seq[int]
    cursor_hook_id: int
    window_size: Index2d
    autocomplete: AutocompleteContext
 
# Dialog / QuickOpen
proc is_hidden(path: string): bool =
  let dirs = path.split("/")
  for dir in dirs:
    if dir.startswith("."):
      return true
  return false

proc index_project(dir: string): seq[string] =
  for item in walk_dir(dir):
    case item.kind:
      of pcFile: result.add(item.path)
      of pcDir: result &= index_project(item.path)
      else: discard

proc index_project(): seq[FileEntry] =
  let paths = index_project(get_current_dir())
  return paths
    .map(path => FileEntry(
      path: path,
      name: path.relative_path(get_current_dir())
    ))
    .filter(entry => not entry.name.is_hidden())
    
proc load_file(editor: Editor, path: string)
proc process_key(quick_open: QuickOpen, editor: Editor, key: Key) =
  case key.kind:
    of KeyReturn:
      if quick_open.selected < quick_open.shown_files.len:
        let path = quick_open.shown_files[quick_open.selected].path 
        editor.load_file(path)
        editor.dialog = Dialog(kind: DialogNone)
    of KeyArrowDown:
      quick_open.selected += 1
      if quick_open.selected >= quick_open.shown_files.len:
        quick_open.selected = quick_open.shown_files.len - 1
    of KeyArrowUp:
      quick_open.selected -= 1
      if quick_open.selected < 0:
        quick_open.selected = 0
    else:
      quick_open.entry.process_key(key)
      quick_open.shown_files = quick_open.files.filter(file => file.name.contains($quick_open.entry.text))
      quick_open.selected = quick_open.selected.min(quick_open.shown_files.len - 1).max(0)

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

  var it = 0
  for y in 2..<box.size.y:
    ren.move_to(box.min.x, y + box.min.y)
    ren.put(repeat(" ", label.len), fg=Color(base: ColorBlack), bg=Color(base: ColorWhite, bright: true))
    ren.put(" ")
    if it < quick_open.shown_files.len:
      var name = quick_open.shown_files[it].name
      if quick_open.shown_files[it].changed:
        name &= "*"
      ren.put(name, reverse=(quick_open.selected == it))
    it += 1

proc make_quick_open(app: App): owned QuickOpen =
  let files = index_project()
    .map(entry => FileEntry(path: entry.path, name: entry.name, changed: app.is_changed(entry.path)))
  return QuickOpen(entry: make_entry(app.copy_buffer), files: files, shown_files: files, selected: 0)

# Dialog
proc process_key(dialog: Dialog, editor: Editor, key: Key) =
  case dialog.kind:
    of DialogNone: discard
    of DialogQuickOpen: dialog.quick_open.process_key(editor, key)

proc render(dialog: Dialog, box: Box, ren: var TermRenderer) =
  case dialog.kind:
    of DialogNone: discard
    of DialogQuickOpen:
      dialog.quick_open.render(box, ren)

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

proc show_info(editor: Editor, lines: seq[string]) =
  editor.prompt = Prompt(kind: PromptInfo, lines: lines) 

proc show_prompt(editor: Editor,
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

proc hide_prompt(editor: Editor) = 
  editor.prompt = Prompt(kind: PromptNone)

proc primary_cursor(editor: Editor): Cursor = editor.cursors[editor.cursors.len - 1]

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
    
proc update_scroll(editor: Editor, size: Index2d) =
  let pos = editor.buffer.to_2d(editor.primary_cursor().get_pos())
  
  while (pos.y - editor.scroll.y) < 4:
    editor.scroll.y -= 1
  while (pos.y - editor.scroll.y) >= size.y - 4:
    editor.scroll.y += 1
    
  editor.scroll.y = max(editor.scroll.y, 0)

proc jump(editor: Editor, to: int) =
  editor.jump_stack.add(editor.primary_cursor().get_pos())
  editor.cursors = @[Cursor(kind: CursorInsert, pos: to)]

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

proc replace_pattern(editor: Editor, inputs: seq[seq[Rune]]) =
  var pos = editor.buffer.text.find(inputs[0], editor.primary_cursor().get_pos + 1)
  if pos == -1:
    pos = editor.buffer.text.find(inputs[0])
  if pos != -1:
    editor.jump(pos)
    editor.buffer.replace(pos, pos + inputs[0].len, inputs[1])

proc save_as(editor: Editor, inputs: seq[seq[Rune]]) =
  if inputs[0].len == 0:
    return
  
  let path = absolute_path($inputs[0])
  editor.buffer.set_path(path, editor.app.languages)
  editor.app.buffers[path] = editor.buffer
  editor.buffer.save()
  editor.autocomplete.recount_words()
  editor.hide_prompt()

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
  editor.buffer = editor.app.make_buffer(path)
  editor.cursor_hook_id = editor.buffer.register_hook(editor.make_cursor_hook())
  editor.hide_prompt()
  editor.cursors = @[Cursor(kind: CursorInsert, pos: 0)]
  editor.autocomplete = make_autocomplete_context(editor.buffer)

proc new_buffer(editor: Editor) =
  editor.buffer.unregister_hook(editor.cursor_hook_id)
  editor.buffer = make_buffer()
  editor.cursor_hook_id = editor.buffer.register_hook(editor.make_cursor_hook())
  editor.hide_prompt()
  editor.cursors = @[Cursor(kind: CursorInsert, pos: 0)]
  editor.autocomplete = make_autocomplete_context(editor.buffer)

method process_key(editor: Editor, key: Key) = 
  if key.kind == KeyChar and key.ctrl and key.chr == Rune('e'):
    if editor.dialog.kind != DialogNone:
      editor.dialog = Dialog(kind: DialogNone)
    else:
      editor.hide_prompt()
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
      if key.alt:
        var index = editor.buffer.to_2d(editor.primary_cursor().get_pos())
        index.y -= 1
        index.y = max(index.y, 0) 
        editor.cursors.add(Cursor(kind: CursorInsert, pos: editor.buffer.to_index(index)))
      else:
        for it, cursor in editor.cursors:
          var index = editor.buffer.to_2d(cursor.get_pos())
          index.y -= 1
          index.y = max(index.y, 0)
          editor.update_cursor(it, editor.buffer.to_index(index), key.shift)
    of KeyArrowDown:
      if key.alt:
        var index = editor.buffer.to_2d(editor.primary_cursor().get_pos())
        index.y += 1
        index.y = min(index.y, editor.buffer.lines.len - 1) 
        editor.cursors.add(Cursor(kind: CursorInsert, pos: editor.buffer.to_index(index)))
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
          indent = repeat(' ', indent_level)
        editor.buffer.insert(cursor.pos, to_runes('\n' & indent))
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
        editor.cursors[it] = Cursor(kind: CursorInsert, pos: editor.buffer.to_index(index))
    of KeyEnd:
      for it, cursor in editor.cursors:
        var index = editor.buffer.to_2d(cursor.get_pos())
        if index.y == editor.buffer.lines.len - 1:
          editor.cursors[it] = Cursor(kind: CursorInsert, pos: editor.buffer.len)  
          continue
        
        index.y += 1
        index.y = min(index.y, editor.buffer.lines.len - 1)
        index.x = 0
        editor.cursors[it] = Cursor(kind: CursorInsert, pos: (editor.buffer.to_index(index) - 1).max(0))
    of KeyBackspace:
      for it, cursor in editor.cursors:
        case cursor.kind
          of CursorSelection:
            let cur = cursor.sort()
            editor.buffer.delete(cur.start, cur.stop)
            editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.start)
          of CursorInsert:
            if cursor.pos > 0:
              editor.buffer.delete(cursor.pos - 1, cursor.pos)
    of KeyDelete:
      for it, cursor in editor.cursors:
        case cursor.kind:
          of CursorSelection:
            let cur = cursor.sort()
            editor.buffer.delete(cur.start, cur.stop)
            editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.start)
          of CursorInsert:
            editor.buffer.delete(cursor.pos, cursor.pos + 1)
    of KeyEscape:
      var cur = editor.primary_cursor()
      editor.cursors = @[cur]
    of KeyChar:
      if key.ctrl:
        case key.chr:
          of Rune('i'):
            if editor.cursors.len == 1 and editor.cursors[0].kind == CursorInsert:
              let completions = editor.autocomplete.predict(editor.cursors[0].pos)
              if completions.len > 0:
                let
                  cursor = editor.cursors[0]
                  compl = completions[0]
              
                editor.buffer.replace(cursor.pos - compl.pos, cursor.pos, compl.text)
                return
            for cursor in editor.cursors:
              case cursor.kind:
                of CursorInsert:  
                  editor.buffer.insert(cursor.pos, sequtils.repeat(Rune(' '), editor.buffer.indent_width))
                of CursorSelection:
                  let cur = cursor.sort()
                  editor.buffer.indent(cur.start, cur.stop)
          of Rune('I'):
            for cursor in editor.cursors:
              case cursor.kind:
                of CursorInsert:  
                  editor.buffer.unindent(editor.buffer.to_2d(cursor.pos).y)
                of CursorSelection:
                  let cur = cursor.sort()
                  editor.buffer.unindent(cur.start, cur.stop)
          of Rune('a'): editor.select_all()
          of Rune('t'):
            editor.dialog = Dialog(
              kind: DialogQuickOpen,
              quick_open: make_quick_open(editor.app)
            )
          of Rune('s'):
            if editor.buffer.file_path == "":
              editor.show_prompt("Save", @["File Name:"], callback=save_as)
            else:
              editor.buffer.save()
              editor.autocomplete.recount_words()
              editor.show_info(@["File saved."])
          of Rune('n'):
            editor.new_buffer()
          of Rune('r'):
            editor.show_prompt("Find and replace", @["Pattern: ", "Replace: "], callback=replace_pattern)
          of Rune('f'): editor.show_prompt("Find", @["Pattern: "], callback=find_pattern)
          of Rune('g'): editor.show_prompt("Go to Line", @["Line: "], callback=goto_line)
          of Rune('v'):
            editor.delete_selections()
            editor.insert(editor.app.copy_buffer.paste())
          of Rune('c'): editor.copy()
          of Rune('x'):
            editor.copy()
            editor.delete_selections()
          of Rune('b'):
            if editor.jump_stack.len > 0:
              editor.cursors = @[Cursor(kind: CursorInsert, pos: editor.jump_stack.pop())]
          of Rune('d'):
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
          of Rune('o'):
            var cur = editor.primary_cursor()
            editor.cursors = @[cur]
          of Rune('z'): editor.buffer.undo()
          of Rune('y'): editor.buffer.redo()
          else: discard
      else:
        editor.insert(key.chr)
    else: discard
  editor.merge_cursors()

proc compute_line_numbers_width(editor: Editor): int =
  var max_line_number = editor.buffer.lines.len
  while max_line_number != 0:
    result += 1
    max_line_number = max_line_number div 10

method render(editor: Editor, box: Box, ren: var TermRenderer) =
  if editor.dialog.kind != DialogNone:
    editor.dialog.render(box, ren)
    return
  
  let
    line_numbers_width = editor.compute_line_numbers_width() + 1
    prompt_size = editor.prompt.compute_size()
  
  editor.window_size = box.size
  editor.update_scroll(box.size - Index2d(x: line_numbers_width + 1, y: prompt_size))
  
  # Render title
  ren.moveTo(box.min)
  let
    title = editor.buffer.display_file_name()
    title_aligned = strutils.align_left(title, box.size.x - 1 - line_numbers_width)
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
  
  for y in 0..<(box.size.y - prompt_size - 1):
    let it = y + editor.scroll.y
    if it >= editor.buffer.lines.len:
      break
    
    ren.move_to(line_numbers_width + 1 + box.min.x, y + box.min.y + 1)
    var
      index = editor.buffer.lines[it]
      reached_end = false
    
    while editor.buffer.get_token(current_token).kind != TokenNone and
          editor.buffer.get_token(current_token).stop < index:
      current_token += 1
    
    while index < editor.buffer.len and editor.buffer[index] != '\n':
      if index - editor.buffer.lines[it] + line_numbers_width + 1 >= box.size.x:
        reached_end = true
        break
    
      if editor.is_under_cursor(index):
        ren.put(editor.buffer[index], reverse=true)
        index += 1
        continue
      elif index in bracket_matches:
        ren.put(editor.buffer[index], fg=Color(base: ColorBlack), bg=Color(base: ColorRed, bright: true))
        index += 1
        continue
          
      var
        chr = editor.buffer[index]
        fg = Color(base: ColorDefault, bright: false)
        
      if editor.buffer.get_token(current_token).kind != TokenNone:
        if index >= editor.buffer.get_token(current_token).stop:
          current_token += 1
      
        if editor.buffer.get_token(current_token).kind != TokenNone:
          let token = editor.buffer.get_token(current_token)
          if token.is_inside(index):
            fg = token.color()
      
      if chr == ' ' and fg.base == ColorDefault:
        chr = '.'
        fg = Color(base: ColorBlack, bright: true)  
      
      ren.put(chr, fg=fg)
      index += 1
    
    if index - editor.buffer.lines[it] + line_numbers_width + 1 >= box.size.x:
      reached_end = true
    
    if editor.is_under_cursor(index) and (not reached_end):
      ren.put(' ', reverse=true)
          
  
  # Render prompt
  case editor.prompt.kind:
    of PromptInfo:
      for it, line in editor.prompt.lines:
        ren.move_to(box.min.x, box.min.y + box.size.y - prompt_size + it)
        ren.put(
          strutils.repeat(' ', line_numbers_width + 1) & strutils.align_left(line, box.size.x - line_numbers_width - 1),
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
  
proc make_editor*(app: App, buffer: Buffer): Editor =
  result = Editor(
    buffer: buffer,
    scroll: Index2d(x: 0, y: 0),
    cursors: @[Cursor(kind: CursorInsert, pos: 0)],
    app: app,
    autocomplete: make_autocomplete_context(buffer)
  )
  result.cursor_hook_id = result.buffer.register_hook(result.make_cursor_hook())

proc make_editor*(app: App): Window =
  make_editor(app, make_buffer())

proc make_editor*(app: App, path: string): Window =
  make_editor(app, make_buffer(path, app.languages))
