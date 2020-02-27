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

import sequtils, strutils, unicode, sugar, os, algorithm, math
import window_manager, utils, ui_utils, termdiff, editor

type
  ItemKind = enum ItemDir, ItemFile, ItemUnknown
  
  Item = object
    name: string
    path: string
    kind: ItemKind

  ModeKind = enum ModeNone, ModeSearch
  
  Mode = object
    case kind: ModeKind:
      of ModeSearch:
        search_entry: Entry
      of ModeNone: discard
 
  FileManager = ref object of Window
    app: App
    
    path: string
    items: seq[Item]
    shown_items: seq[Item]
    list: List
    
    mode: Mode

proc `<`(a, b: Item): bool =
  if a.kind != b.kind:
    return a.kind.ord < b.kind.ord
  
  return a.name < b.name

proc to_item_kind(pc: PathComponent): ItemKind =
  case pc:
    of pcDir: return ItemDir
    of pcFile: return ItemFile
    else: return ItemUnknown
  
proc `$`(item: Item): string = item.name

proc match(item: Item, query: string): bool =
  unicode.to_lower(query) in unicode.to_lower(item.name)

proc update_list(file_manager: FileManager) =
  case file_manager.mode.kind:
    of ModeNone: file_manager.shown_items = file_manager.items
    of ModeSearch:
      file_manager.shown_items = file_manager.items
        .filter(item => item.match($file_manager.mode.search_entry.text))
  file_manager.list.items = file_manager.shown_items.map(`$`).map(to_runes)
  if file_manager.list.selected >= file_manager.list.items.len:
    file_manager.list.selected = max(file_manager.list.items.len - 1, 0)


proc open(file_manager: FileManager, path: string) =
  file_manager.path = path
  file_manager.items = @[]
  for item in walk_dir(path):
    case item.kind:
      of pcFile, pcDir:
        file_manager.items.add(Item(
          kind: item.kind.to_item_kind(),
          path: item.path,
          name: item.path.relative_path(path)
        ))
      else: discard 
  file_manager.items.sort()
  file_manager.update_list()
  file_manager.list.selected = 0

method process_key(file_manager: FileManager, key: Key) =
  case key.kind:
    of KeyReturn:
      if file_manager.shown_items.len == 0:
        return
      let item = file_manager.shown_items[file_manager.list.selected]
      case item.kind:
        of ItemDir:
          file_manager.mode = Mode(kind: ModeNone)
          file_manager.open(item.path)
        of ItemFile:
          file_manager.app.root_pane.open_window(file_manager.app.make_editor(item.path))
        else: discard
    of KeyArrowUp, KeyArrowDown:
      file_manager.list.process_key(key)
    of KeyEscape:
      file_manager.mode = Mode(kind: ModeNone)
      file_manager.update_list()
    else:
      case file_manager.mode.kind:
        of ModeNone:
          case key.kind:
            of KeyBackspace:
              file_manager.open(file_manager.path.parent_dir())
            of KeyChar:
              file_manager.mode = Mode(kind: ModeSearch,
                search_entry: make_entry(file_manager.app.copy_buffer)
              )
              file_manager.mode.search_entry.process_key(key)
              file_manager.update_list()
            else: discard
        of ModeSearch:
          file_manager.mode.search_entry.process_key(key)
          file_manager.update_list()

method render(file_manager: FileManager, box: Box, ren: var TermRenderer) =
  case file_manager.mode.kind:
    of ModeNone:
      render_border(file_manager.path, 1, box, ren)
      file_manager.list.render(Box(
        min: box.min + Index2d(x: 2, y: 1),
        max: box.max
      ), ren)
    of ModeSearch:
      let sidebar_text = "Search:"
      render_border(file_manager.path, sidebar_text.len, box, ren)
      file_manager.list.render(Box(
        min: box.min + Index2d(x: sidebar_text.len + 1, y: 2),
        max: box.max
      ), ren)
      
      ren.move_to(box.min + Index2d(y: 1))
      ren.put(sidebar_text, fg=Color(base: ColorBlack), bg=Color(base: ColorWhite))
      
      ren.move_to(box.min + Index2d(x: sidebar_text.len + 1, y: 1))
      file_manager.mode.search_entry.render(ren)

proc make_file_manager*(app: App): Window =
  let file_manager = FileManager(app: app)
  file_manager.open(get_current_dir())
  return file_manager
