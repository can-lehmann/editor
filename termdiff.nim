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

import utils, sequtils, strutils, backends/ncurses, backends/common, unicode

export setup_term, reset_term, read_key

export Color, BaseColor
export Key, KeyKind

type
  TermScreen* = ref object
    width*: int
    data*: seq[CharCell]

proc make_term_screen*(w, h: int): owned TermScreen =
  let chr = CharCell(
    chr: Rune(' '),
    fg: Color(base: ColorDefault),
    bg: Color(base: ColorDefault)
  )

  return TermScreen(
    width: w,
    data: repeat(chr, w * h)
  )

proc make_term_screen*(): owned TermScreen =
  make_term_screen(terminal_width(), terminal_height())

proc height*(screen: TermScreen): int =
  screen.data.len div screen.width

proc `[]`*(screen: TermScreen, x, y: int): CharCell =
  screen.data[x + y * screen.width]

proc has_same_style(a, b: CharCell): bool =
  a.fg == b.fg and a.bg == b.bg and a.reverse == b.reverse

proc show_all*(screen: TermScreen) =
  var cur_style = screen.data[0]
  cur_style.apply_style()
  for y in 0..<screen.height:
    set_cursor_pos(0, y)
    for x in 0..<screen.width:
      cur_style.apply_style(screen[x, y])
      term_write(screen[x, y].chr)
      cur_style = screen[x, y]
  term_refresh()

proc apply*(prev, cur: TermScreen) =
  if prev.width != cur.width or prev.data.len != cur.data.len:
    cur.show_all()
    return
      
  var
    cur_style = cur.data[0]
    pos = Index2d(x: 0, y: 0)
  set_cursor_pos(0, 0)
  cur_style.apply_style()
  for y in 0..<cur.height:
    for x in 0..<cur.width:
      if cur[x, y] != prev[x, y]:
        if pos.x != x or pos.y != y:
          set_cursor_pos(x, y)
        cur_style.apply_style(cur[x, y])
        term_write(cur[x, y].chr)
        pos.x += 1
        cur_style = cur[x, y]
  term_refresh()
  
type
  TermRenderer* = object
    screen*: TermScreen
    pos*: Index2d
    clip_area*: Box
  
proc make_term_renderer*(screen: TermScreen): TermRenderer =
  return TermRenderer(
    screen: screen,
    pos: Index2d(x: 0, y: 0),
    clip_area: Box(min: Index2d(x: 0, y: 0), max: Index2d(x: screen.width, y: screen.height))
  )
  
proc move_to*(ren: var TermRenderer, pos: Index2d) = ren.pos = pos
proc move_to*(ren: var TermRenderer, x, y: int) = ren.move_to(Index2d(x: x, y: y))

proc put*(ren: var TermRenderer,
          rune: Rune,
          fg: Color = Color(base: ColorDefault),
          bg: Color = Color(base: ColorDefault),
          reverse: bool = false) =
  if not ren.clip_area.is_inside(ren.pos):
    return
  let index = ren.pos.x + ren.pos.y * ren.screen.width
  ren.pos.x += 1
  if index >= ren.screen.data.len:
    return
  ren.screen.data[index].chr = rune
  ren.screen.data[index].fg = fg
  ren.screen.data[index].bg = bg
  ren.screen.data[index].reverse = reverse

proc put*(ren: var TermRenderer,
          chr: char,
          fg: Color = Color(base: ColorDefault),
          bg: Color = Color(base: ColorDefault),
          reverse: bool = false) =
  ren.put(Rune(chr), fg=fg, bg=bg, reverse=reverse)

proc put*(ren: var TermRenderer, chr: char, pos: Index2d) =
  ren.pos = pos
  ren.put(chr)
    
proc put*(ren: var TermRenderer, chr: char, x, y: int) = ren.put(chr, Index2d(x: x, y: y))

proc put*(ren: var TermRenderer,
          str: seq[Rune],
          fg: Color = Color(base: ColorDefault),
          bg: Color = Color(base: ColorDefault),
          reverse: bool = false) =
  for it, rune in str.pairs:
    if not ren.clip_area.is_inside(ren.pos + Index2d(x: it, y: 0)):
      return
    let index = ren.pos.x + ren.pos.y * ren.screen.width + it
    if index >= ren.screen.data.len:
      break
    ren.screen.data[index].chr = rune
    ren.screen.data[index].fg = fg
    ren.screen.data[index].bg = bg
    ren.screen.data[index].reverse = reverse
  ren.pos.x += str.len

proc put*(ren: var TermRenderer,
          str: string,
          fg: Color = Color(base: ColorDefault),
          bg: Color = Color(base: ColorDefault),
          reverse: bool = false) =
  ren.put(str.to_runes(), fg=fg, bg=bg, reverse=reverse)

proc clip*(ren: var TermRenderer, area: Box) =
  ren.clip_area = area
