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

import terminal, common

export terminal_width, terminal_height, set_style, set_cursor_pos, getch

proc term_write*(chr: char) =
  stdout.write(chr)

proc term_refresh*() =
  discard

proc set_fg*(fg: Color) =
  case fg.base:
    of ColorBlack: stdout.set_foreground_color(fgBlack, fg.bright)
    of ColorRed: stdout.set_foreground_color(fgRed, fg.bright)
    of ColorGreen: stdout.set_foreground_color(fgGreen, fg.bright)
    of ColorYellow: stdout.set_foreground_color(fgYellow, fg.bright)
    of ColorBlue: stdout.set_foreground_color(fgBlue, fg.bright)
    of ColorMagenta: stdout.set_foreground_color(fgMagenta, fg.bright)
    of ColorCyan: stdout.set_foreground_color(fgCyan, fg.bright)
    of ColorWhite: stdout.set_foreground_color(fgWhite, fg.bright)
    of ColorDefault: stdout.set_foreground_color(fgDefault, fg.bright)

proc set_bg*(bg: Color) =
  case bg.base:
    of ColorBlack: stdout.set_background_color(bgBlack, bg.bright)
    of ColorRed: stdout.set_background_color(bgRed, bg.bright)
    of ColorGreen: stdout.set_background_color(bgGreen, bg.bright)
    of ColorYellow: stdout.set_background_color(bgYellow, bg.bright)
    of ColorBlue: stdout.set_background_color(bgBlue, bg.bright)
    of ColorMagenta: stdout.set_background_color(bgMagenta, bg.bright)
    of ColorCyan: stdout.set_background_color(bgCyan, bg.bright)
    of ColorWhite: stdout.set_background_color(bgWhite, bg.bright)
    of ColorDefault: stdout.set_background_color(bgDefault, bg.bright)

proc apply_style*(a, b: CharCell) =
  if a.fg != b.fg:
    b.fg.set_fg()
  
  if a.bg != b.bg:
    b.bg.set_bg()
    
  if a.reverse != b.reverse:
    if b.reverse:
      stdout.set_style({styleReverse})
    else:
      stdout.set_style({})
      reset_attributes()
      b.fg.set_fg()
      b.bg.set_bg()

proc apply_style*(cell: CharCell) =
  reset_attributes()
  cell.fg.set_fg()
  cell.bg.set_bg()
  if cell.reverse:
    stdout.set_style({styleReverse})
  else:
    stdout.set_style({})
  stdout.flush_file()

proc setup_term*() =
  hide_cursor()
  erase_screen()  

proc reset_term*() =
  set_style({})
  reset_attributes()
  stdout.set_foreground_color(fgDefault, false)
  stdout.set_background_color(bgDefault, false)
  erase_screen()
  set_cursor_pos(0, 0)
  show_cursor()
  
proc read_escape(): Key =
  if ord(getch()) != 91:
    return Key(kind: KeyUnknown)
    
  case ord(getch()):
    of 66: return Key(kind: KeyArrowDown)
    of 67: return Key(kind: KeyArrowRight)
    of 68: return Key(kind: KeyArrowLeft)
    of 65: return Key(kind: KeyArrowUp)
    of 51:
      if ord(getch()) == 126:
        return Key(kind: KeyArrowDown)
      return Key(kind: KeyUnknown)
    of 49:
      if ord(getch()) != 59:
        return Key(kind: KeyUnknown)
      let modifiers = ord(getch())
      var
        shift = false
        ctrl = false
        alt = false
        kind = KeyUnknown
      
      case modifiers:
        of 50: shift = true
        of 51: alt = true
        of 52:
          shift = true
          alt = true
        of 53:
          ctrl = true
        of 54:
          ctrl = true
          shift = true
        else: discard
      
      case ord(getch()):
        of 66: kind = KeyArrowDown
        of 67: kind = KeyArrowRight
        of 68: kind = KeyArrowLeft
        of 65: kind = KeyArrowUp
        else: return Key(kind: KeyUnknown)
      
      return Key(kind: kind, shift: shift, ctrl: ctrl, alt: alt)
    else:
      return Key(kind: KeyUnknown)
      
proc read_key*(): Key =
  let chr = getch()
  var key = Key(kind: KeyChar, chr: chr)
  
  if ord(chr) == 127:
    return Key(kind: KeyBackspace)
  elif ord(chr) == 13:
    return Key(kind: KeyReturn)
  
  if ord(chr) == 27:
    return read_escape()
    
  if ord(chr) <= 26:
    return Key(
      kind: KeyChar,
      chr: char(ord(chr) - 1 + ord('a')),
      ctrl: true
    )
  
  return Key(kind: KeyChar, chr: chr)
