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

import unicode, sequtils, sugar, strutils
import ../utils

type 
  BaseColor* = enum
    ColorBlack = 0,
    ColorRed, ColorGreen, ColorYellow, ColorBlue,
    ColorMagenta, ColorCyan, ColorWhite, ColorDefault

  Color* = object
    base*: BaseColor
    bright*: bool
  
  CharCell* = object
    chr*: Rune
    fg*: Color
    bg*: Color
    reverse*: bool

  MouseKind* = enum
    MouseUnknown, MouseNone,
    MouseMove,
    MouseDown, MouseUp,
    MouseScroll

  Mouse* = object
    x*: int
    y*: int
    buttons*: array[3, bool]
    case kind*: MouseKind:
      of MouseDown, MouseUp:
        button*: int
        clicks*: int
      of MouseScroll:
        delta*: int
      of MouseUnknown:
        state*: uint64
      else: discard
    
  KeyKind* = enum
    KeyNone, KeyUnknown, KeyMouse,
    KeyChar, KeyReturn, KeyBackspace, KeyDelete, KeyEscape,
    KeyArrowLeft, KeyArrowRight, KeyArrowDown, KeyArrowUp,
    KeyHome, KeyEnd, KeyPageUp, KeyPageDown, KeyFn,
    KeyPaste, KeyQuit

  Key* = object
    shift*: bool
    ctrl*: bool
    alt*: bool
    case kind*: KeyKind:
      of KeyChar: chr*: Rune
      of KeyUnknown: key_code*: int
      of KeyPaste: text*: seq[Rune]
      of KeyFn: fn*: int
      else: discard

type
  TermScreen* = ref object
    width*: int
    data*: seq[CharCell]

const DEFAULT_CHAR_CELL = CharCell(
  chr: Rune(' '),
  fg: Color(base: ColorDefault),
  bg: Color(base: ColorDefault)
)

proc new_term_screen*(w, h: int): owned TermScreen =
  result = TermScreen(
    width: w,
    data: repeat(DEFAULT_CHAR_CELL, w * h)
  )

proc height*(screen: TermScreen): int =
  if screen.width == 0:
    return 0
  return screen.data.len div screen.width

proc size*(screen: TermScreen): Index2d =
  Index2d(x: screen.width, y: screen.height)

proc resize*(screen: TermScreen, w, h: int) =
  screen.width = w
  screen.data = repeat(DEFAULT_CHAR_CELL, w * h)

proc `[]`*(screen: TermScreen, x, y: int): CharCell =
  screen.data[x + y * screen.width]

proc `[]=`*(screen: TermScreen, x, y: int, cell: CharCell) =
  screen.data[x + y * screen.width] = cell

proc `$`*(key: Key): string =
  if key.ctrl:
    result &= "Ctrl + "
  if key.alt:
    result &= "Alt + "
  if key.shift:
    result &= "Shift + "
  
  case key.kind:
    of KeyUnknown: result &= "Unknown (" & $key.key_code & ")"
    of KeyChar: result &= key.chr
    of KeyFn: result &= "F" & $key.fn
    of KeyPaste: result &= "Paste (" & $key.text & ")"
    of KeyArrowUp: result &= "Up"
    of KeyArrowDown: result &= "Down"
    of KeyArrowLeft: result &= "Left"
    of KeyArrowRight: result &= "Right"
    of KeyHome: result &= "Home"
    of KeyEnd: result &= "End"
    of KeyPageUp: result &= "Page Up"
    of KeyPageDown: result &= "Page Down"
    of KeyEscape: result &= "Escape"
    of KeyDelete: result &= "Delete"
    of KeyReturn: result &= "Return"
    of KeyBackspace: result &= "Backspace"
    else: result &= $key.kind

proc `$`*(keys: seq[Key]): string =
  keys.map(key => $key).join(" ")

proc display_mouse_button(button: int): string =
  case button:
    of 0: return "Left"
    of 1: return "Middle"
    of 2: return "Right"
    else: return "Button" & $button

proc `$`*(mouse: Mouse): string =
  case mouse.kind:
    of MouseDown: result &= "Down"
    of MouseUp: result &= "Up"
    of MouseMove: result &= "Move"
    of MouseScroll: result &= "Scroll"
    else: discard
  
  case mouse.kind:
    of MouseDown, MouseUp:
      result &= " " & display_mouse_button(mouse.button)
      result &= " " & $mouse.clicks
    of MouseScroll:
      result &= " " & $mouse.delta
    else: discard
  
  var pressed_buttons: seq[string] = @[]
  for button, pressed in mouse.buttons.pairs:
    if pressed:  
      pressed_buttons.add(display_mouse_button(button))
  
  result &= " {" & pressed_buttons.join(", ") & "}"
  result &= " (" & $mouse.x & ", " & $mouse.y & ")"

proc pos*(mouse: Mouse): Index2d =
  Index2d(x: mouse.x, y: mouse.y)

type TermRenderer* = object
  screen*: TermScreen
  pos*: Index2d
  clip_area*: Box

proc reset_cursor*(ren: var TermRenderer) =
  ren.pos = Index2d()
  ren.clip_area = Box(max: Index2d(x: ren.screen.width, y: ren.screen.height))

proc init_term_renderer*(screen: TermScreen): TermRenderer =
  result = TermRenderer(screen: screen)
  result.reset_cursor()

proc clear*(ren: var TermRenderer) =
  ren.reset_cursor()
  for cell in ren.screen.data.mitems:
    cell = DEFAULT_CHAR_CELL

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

