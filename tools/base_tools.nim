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

import unicode, base64, sugar
import ".." / [editor, buffer, utils, ui_utils, window_manager]

proc wrap_replace_selection(callback: proc (x: string): string): (proc (editor: Editor)) =
  return proc (editor: Editor) =
    template apply_callback(start, stop) =
      try:
        let
          text = $editor.buffer.slice(start, stop)
          changed = to_runes(callback(text))
        editor.buffer.replace(start, stop, changed)
      except Exception as err:
        editor.show_info(@[err.msg])
    
    var applied = false
    for cursor in editor.cursors:
      if cursor.kind != CursorSelection:
        continue
      applied = true
      let cur = cursor.sort()
      apply_callback(cur.start, cur.stop)
    
    if not applied:
      apply_callback(0, editor.buffer.len)
    editor.buffer.finish_undo_frame()

editor_tools.add(Tool(
  name: "Decode Base64",
  callback: wrap_replace_selection(text => decode(text))
))

editor_tools.add(Tool(
  name: "Encode Base64",
  callback: wrap_replace_selection(text => encode(text))
))

proc replace_all(editor: Editor, inputs: seq[seq[Rune]]) =
  var
    cur = 0
    pos = -1
  while (pos = editor.buffer.text.find(inputs[0], cur); pos != -1):
    editor.buffer.replace(pos, pos + inputs[0].len, inputs[1])
    pos += 1
  editor.buffer.finish_undo_frame()

proc show_replace_all(editor: Editor) =
  editor.show_prompt("Replace All",
    @["Pattern: ", "Replace: "],
    replace_all
  )

editor_tools.add(Tool(
  name: "Replace All",
  callback: show_replace_all
))

proc replace_pattern(editor: Editor, inputs: seq[seq[Rune]]) =
  var pos = editor.buffer.text.find(inputs[0], editor.primary_cursor().get_pos + 1)
  if pos == -1:
    pos = editor.buffer.text.find(inputs[0])
  if pos != -1:
    editor.jump(pos)
    editor.buffer.replace(pos, pos + inputs[0].len, inputs[1])

proc show_replace(editor: Editor) =
  editor.show_prompt(
    "Find and Replace",
    @["Pattern: ", "Replace: "],
    callback=replace_pattern
  )

editor_tools.add(Tool(
  name: "Find and Replace",
  callback: show_replace
))
