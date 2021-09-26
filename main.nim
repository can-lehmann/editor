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

import unicode, tables, os
import termdiff, window_manager, buffer, utils
import editor, keyinfo, calc, file_manager, log_viewer
import highlight/[lisp, json, html, markdown, cpp, nim, lua, css]
import autocomplete/[comp_nim, comp_simple, comp_lua]
import tools/[base_tools, json_tools]

var
  languages = @[
    Language(
      name: "Nim",
      highlighter: new_nim_highlighter,
      file_exts: @["nim", "nims", "nimble"],
      indent_width: 2,
      make_autocompleter: make_nim_autocompleter
    ),
    Language(
      name: "HTML",
      highlighter: new_html_highlighter,
      file_exts: @["html", "htm"],
      indent_width: 2,
      make_autocompleter: new_html_autocompleter
    ),
    Language(
      name: "JavaScript",
      file_exts: @["js"],
      indent_width: 2
    ),
    Language(
      name: "CSS",
      file_exts: @["css"],
      indent_width: 2,
      highlighter: new_css_highlighter
    ),
    Language(
      name: "Lisp/Scheme",
      file_exts: @["clj", "lisp", "cl", "scm", "sld"],
      highlighter: new_lisp_highlighter,
      indent_width: 2
    ),
    Language(
      name: "Python",
      file_exts: @["py"],
      indent_width: 4
    ),
    Language(
      name: "JSON",
      file_exts: @["json"],
      indent_width: 2,
      highlighter: new_json_highlighter
    ),
    Language(
      name: "Markdown",
      file_exts: @["md"],
      indent_width: 2,
      highlighter: new_markdown_highlighter,
      make_autocompleter: new_markdown_autocompleter
    ),
    Language(
      name: "C++",
      file_exts: @["cpp", "hpp", "c", "h"],
      indent_width: 2,
      highlighter: new_cpp_highlighter
    ),
    Language(
      name: "Text",
      file_exts: @["txt"],
      indent_width: 2
    ),
    Language(
      name: "Lua",
      file_exts: @["lua"],
      indent_width: 2,
      highlighter: new_lua_highlighter,
      make_autocompleter: new_lua_autocompleter
    )
  ]
  window_constructors = @[
    init_window_constructor("Editor", new_editor),
    init_window_constructor("File Manager", new_file_manager),
    init_window_constructor("Calc", new_calc),
    init_window_constructor("Keyinfo", new_keyinfo),
    init_window_constructor("Log Viewer", new_log_viewer)
  ]

var app = new_app(languages, window_constructors)

if param_count() > 0:
  for it in 1..param_count():
    let editor = app.new_editor(param_str(it).absolute_path(get_current_dir()))
    app.columns.add(init_panes(AxisY, @[editor]), 1 / param_count())
else:
  app.columns.add(init_panes(AxisY, @[app.new_editor()]))

let term = new_terminal()

proc quit_app() {.noconv.} = term.destroy()
system.add_quit_proc(quit_app)

var ren = init_term_renderer(term)
app.render(ren)
term.redraw()

while true:
  if term.poll():
    break
  let key = term.read_key()
  if key.kind == KeyMouse:
    app.process_mouse(term.read_mouse(), ren.screen.size)
  else:
    if app.process_key(key):
      break
  
  app.render(ren)
  term.redraw()
