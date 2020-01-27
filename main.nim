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

import termdiff, highlight, window_manager
import editor, keyinfo, calc

setup_term()

var
  cur_screen = make_term_screen()
  languages = @[
    Language(
      name: "Nim",
      highlighter: tokenize_nim,
      file_exts: @["nim", "nims"],
      indent_width: 2
    ),
    Language(
      name: "HTML",
      highlighter: tokenize_html,
      file_exts: @["html", "htm"],
      indent_width: 2
    )
  ]
  window_constructors = @[
    make_window_constructor("Editor", make_editor),
    make_window_constructor("Calc", make_calc),
    make_window_constructor("Keyinfo", make_keyinfo)
  ]
  app = make_app(languages, window_constructors)
  root_pane = Pane(kind: PaneWindow, window: app.make_editor())

app.root_pane = root_pane

block:
  var ren = make_term_renderer(cur_screen)
  app.render(ren)
  cur_screen.show_all()

import times
while true:
  let key = read_key()

  if app.process_key(key):
    quit_app()
    break
  
  var
    screen = make_term_screen()
    ren = make_term_renderer(screen)
  app.render(ren)
  
  cur_screen.apply(screen)
  cur_screen = screen

system.add_quit_proc(quit_app)