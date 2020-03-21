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

import unicode, sequtils, sugar, strutils

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
    MouseScroll,
    MouseClick, MouseDoubleClick, MouseTripleClick

  Mouse* = object
    x*: int
    y*: int
    buttons*: array[3, bool]
    case kind*: MouseKind:
      of MouseUp, MouseDown, MouseClick, MouseDoubleClick, MouseTripleClick:
        button*: int
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

proc height*(screen: TermScreen): int =
  if screen.width == 0:
    return 0
  return screen.data.len div screen.width

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
    of MouseScroll:
      result &= " " & $mouse.delta
    else: discard
  
  var pressed_buttons: seq[string] = @[]
  for button, pressed in mouse.buttons.pairs:
    if pressed:  
      pressed_buttons.add(display_mouse_button(button))
  
  result &= " {" & pressed_buttons.join(", ") & "}"
  result &= " (" & $mouse.x & ", " & $mouse.y & ")"
