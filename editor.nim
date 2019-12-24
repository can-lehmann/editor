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

import sequtils, strutils, os, sugar, streams, deques, unicode
import utils, ui_utils, termdiff, highlight, buffer, window_manager

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
    .map(path => FileEntry(path: path, name: path.relative_path(get_current_dir())))
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
      ren.put(quick_open.shown_files[it].name, reverse=(quick_open.selected == it))
    it += 1

proc make_quick_open(app: App): owned QuickOpen =
  let files = index_project()
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

proc update_cursor(editor: Editor, index: int, pos_raw: int, shift: bool) =
  let pos = max(min(pos_raw, editor.buffer.text.len), 0)
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
  
proc update_cursors(editor: Editor, start: int, delta: int) =
  for it in start..<editor.cursors.len:
    editor.cursors[it].move(delta, editor.buffer.text.len)

proc update_scroll(editor: Editor, size: Index2d) =
  let pos = editor.buffer.to_2d(editor.cursors[editor.cursors.len - 1].get_pos())
  
  while (pos.y - editor.scroll.y) < 4:
    editor.scroll.y -= 1
  while (pos.y - editor.scroll.y) >= size.y - 4:
    editor.scroll.y += 1
    
  editor.scroll.y = max(editor.scroll.y, 0)

proc jump(editor: Editor, to: int) =
  editor.jump_stack.add(editor.cursors[0].get_pos())
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
  var pos = editor.buffer.text.find(inputs[0], editor.cursors[0].get_pos + 1)
  if pos == -1:
    pos = editor.buffer.text.find(inputs[0])
  if pos != -1:
    editor.jump(pos)

proc save_as(editor: Editor, inputs: seq[seq[Rune]]) =
  editor.buffer.set_path($inputs[0], editor.app.languages)
  editor.buffer.save()
  editor.hide_prompt()

proc select_all(editor: Editor) =
  editor.cursors = @[Cursor(
    kind: CursorSelection,
    start: 0,
    stop: editor.buffer.text.len
  )]

proc delete_selections(editor: Editor) =
  for it, cursor in editor.cursors:
    if cursor.kind != CursorSelection:
      continue
    
    let cur = cursor.sort()
    editor.buffer.text = editor.buffer.text.substr(0, cur.start - 1) & editor.buffer.text.substr(cur.stop)
    editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.start)
    editor.buffer.delete_tokens(cur.start)
    editor.update_cursors(it + 1, -(cur.stop - cur.start))
  editor.buffer.reindex_lines()
  editor.buffer.changed = true
  
proc copy(editor: Editor) =
  for cursor in editor.cursors:
    if cursor.kind == CursorSelection:
      let
        cur = cursor.sort()
        text = editor.buffer.text.substr(cur.start, cur.stop - 1)
      editor.app.copy_buffer.copy(text)

proc insert(editor: Editor, chr: Rune) =
  for it, cursor in editor.cursors:
    if cursor.kind == CursorSelection:
      continue
    
    editor.buffer.insert(cursor.pos, chr)  
    editor.update_cursors(it, 1)

proc insert(editor: Editor, str: seq[Rune]) =
  for it, cursor in editor.cursors:
    if cursor.kind != CursorInsert:
      continue
    
    editor.buffer.insert(cursor.pos, str)    
    editor.update_cursors(it, str.len)
  
proc load_file(editor: Editor, path: string) =
  editor.buffer = editor.app.make_buffer(path)
  editor.hide_prompt()
  editor.cursors = @[Cursor(kind: CursorInsert, pos: 0)]

proc new_buffer(editor: Editor) =
  editor.buffer = make_buffer()
  editor.hide_prompt()
  editor.cursors = @[Cursor(kind: CursorInsert, pos: 0)]
  
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
      if key.ctrl:
        for it, cursor in editor.cursors:
          editor.update_cursor(it, editor.buffer.skip(cursor.get_pos() - 1, -1) + 1, key.shift)
      else:
        for it, cursor in editor.cursors:
          editor.update_cursor(it, cursor.get_pos() - 1, key.shift)
    of KeyArrowRight:
      if key.ctrl:
        for it, cursor in editor.cursors:
          editor.update_cursor(it, editor.buffer.skip(cursor.get_pos(), 1), key.shift)
      else:
        for it, cursor in editor.cursors:
          editor.update_cursor(it, cursor.get_pos() + 1, key.shift)
    of KeyArrowUp:
      for it, cursor in editor.cursors:
        var index = editor.buffer.to_2d(cursor.get_pos())
        index.y -= 1
        index.y = max(index.y, 0)
        editor.update_cursor(it, editor.buffer.to_index(index), key.shift)
    of KeyArrowDown:
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
        
        editor.update_cursors(it, 1 + indent_level)
    of KeyBackspace:
      for it, cursor in editor.cursors:
        case cursor.kind
          of CursorSelection:
            let cur = cursor.sort()
            editor.buffer.text = editor.buffer.text.substr(0, cur.start - 1) & editor.buffer.text.substr(cur.stop)
            editor.update_cursors(it + 1, -(cur.stop - cur.start))
            editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.start)
            editor.buffer.delete_tokens(cur.start)
          of CursorInsert:
            if cursor.pos > 0:
              editor.buffer.text = editor.buffer.text.substr(0, cursor.pos - 2) & editor.buffer.text.substr(cursor.pos)
              editor.update_cursors(it, -1)
              editor.buffer.delete_tokens(cursor.pos - 1)
        editor.buffer.reindex_lines()
      editor.buffer.changed = true
    of KeyDelete:
      for it, cursor in editor.cursors:
        case cursor.kind:
          of CursorSelection:
            let cur = cursor.sort()
            editor.buffer.text = editor.buffer.text.substr(0, cur.start - 1) & editor.buffer.text.substr(cur.stop)
            editor.update_cursors(it + 1, -(cur.stop - cur.start))
            editor.cursors[it] = Cursor(kind: CursorInsert, pos: cur.start)
            editor.buffer.delete_tokens(cur.start)
          of CursorInsert:
            editor.buffer.text = editor.buffer.text.substr(0, cursor.pos - 1) & editor.buffer.text.substr(cursor.pos + 1)
            editor.update_cursors(it + 1, -1)
            editor.buffer.delete_tokens(cursor.pos)
      editor.buffer.reindex_lines()
      editor.buffer.changed = true
    of KeyChar:
      if key.ctrl:
        case key.chr:
          of Rune('i'):
            editor.delete_selections()
            for it in 0..<2:
              editor.insert(' ')
          of Rune('I'):
            for it, cursor in editor.cursors:
              case cursor.kind:
                of CursorInsert:
                  let
                    line_index = editor.buffer.lines[editor.buffer.to_2d(cursor.pos).y]
                    indent_width = 2
                  var is_indented = true
                  for it in 0..<indent_width:
                    if it + line_index >= editor.buffer.text.len or
                       editor.buffer.text[it + line_index] != ' ':
                      is_indented = false
                      break
                  
                  if is_indented:
                    let
                      before = editor.buffer.text.substr(0, line_index - 1)
                      after = editor.buffer.text.substr(line_index + indent_width)
                    editor.buffer.text = before & after
                  
                  editor.buffer.reindex_lines()
                  editor.update_cursors(it, -indent_width)
                  editor.buffer.delete_tokens(cursor.pos)
                  editor.buffer.changed = true
                of CursorSelection:
                  discard
                  #editor.unindent()
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
              editor.show_info(@["File saved."])
          of Rune('n'):
            editor.new_buffer()
          of Rune('r'):
            editor.show_prompt("Find and replace", @["Pattern: ", "Replace: "], callback=find_pattern)
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
          else: discard
      else:
        editor.delete_selections()
        editor.insert(key.chr)
    else: discard

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
    
    while index < editor.buffer.text.len and editor.buffer.text[index] != '\n':
      if index - editor.buffer.lines[it] + line_numbers_width + 1 >= box.size.x:
        reached_end = true
        break
    
      if editor.is_under_cursor(index):
        ren.put(editor.buffer.text[index], reverse=true)
        index += 1
        continue
    
      var
        chr = editor.buffer.text[index]
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
  
    
proc make_editor*(app: App, buffer: Buffer): Editor =
  result = Editor(
    buffer: buffer,
    scroll: Index2d(x: 0, y: 0),
    cursors: @[Cursor(kind: CursorInsert, pos: 0)],
    app: app
  )

proc make_editor*(app: App): Window =
  make_editor(app, make_buffer())

proc make_editor*(app: App, path: string): Window =
  make_editor(app, make_buffer(path, app.languages))
