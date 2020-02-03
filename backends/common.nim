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

import unicode

type 
  BaseColor* = enum
    ColorBlack = 0, ColorRed, ColorGreen, ColorYellow, ColorBlue, ColorMagenta, ColorCyan, ColorWhite, ColorDefault

  Color* = object
    base*: BaseColor
    bright*: bool
  
  CharCell* = object
    chr*: Rune
    fg*: Color
    bg*: Color
    reverse*: bool
    
  KeyKind* = enum
    KeyNone, KeyUnknown,
    KeyChar, KeyReturn, KeyBackspace, KeyDelete, KeyEscape,
    KeyArrowLeft, KeyArrowRight, KeyArrowDown, KeyArrowUp,
    KeyHome, KeyEnd, KeyPageUp, KeyPageDown

  Key* = object
    shift*: bool
    ctrl*: bool
    alt*: bool
    case kind*: KeyKind:
      of KeyChar: chr*: Rune
      of KeyUnknown: key_code*: int
      else: discard

