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

import common, tables, hashes, unicode, times

{.passL: gorge("pkg-config --libs ncursesw").}

# Wrapper
type
  WindowObj {.header: "<ncurses.h>", importc:"WINDOW".} = object
  Window = ptr WindowObj

  MouseMask {.header: "<ncurses.h>", importc:"mmask_t".} = culong

  MouseEvent {.header: "<ncurses.h>", importc:"MEVENT".} = object
    id: cshort
    x: cint
    y: cint
    z: cint
    bstate: MouseMask

proc setlocale(category: cint, locale: cstring) {.header: "<locale.h>", importc.}

proc initscr(): Window {.header: "<ncurses.h>", importc.}
proc endwin(): cint {.header: "<ncurses.h>", importc.}
proc move(y, x: cint): cint {.header: "<ncurses.h>", importc.}
proc addch(chr: char): cint {.header: "<ncurses.h>", importc.}
proc add_wch(chr: cstring): cint {.header: "<ncurses.h>", importc.}
proc addwstr(chr: cstring): cint {.header: "<ncurses.h>", importc.}
proc addstr(str: cstring): cint {.header: "<ncurses.h>", importc.}
proc getch(): cint {.header: "<ncurses.h>", importc.}
proc clear(): cint {.header: "<ncurses.h>", importc.}
proc start_color(): cint {.header: "<ncurses.h>", importc.}
proc enable_echo(): cint {.header: "<ncurses.h>", importc: "echo".}
proc disable_echo(): cint {.header: "<ncurses.h>", importc: "noecho".}
proc refresh(): cint {.header: "<ncurses.h>", importc.}
proc init_pair(pair, f, b: cshort): cint {.header: "<ncurses.h>", importc.}
proc has_colors(): bool {.header: "<ncurses.h>", importc.}
proc color_set(pair: cshort, opts: pointer): bool {.header: "<ncurses.h>", importc.}
proc cbreak(): int {.header: "<ncurses.h>", importc.}
proc use_default_colors(): cint {.header: "<ncurses.h>", importc.}
proc keypad(win: Window, bf: bool): int {.header: "<ncurses.h>", importc.}
proc attrset(attrs: cint): cint {.header: "<ncurses.h>", importc.}
proc attron(attrs: cint): cint {.header: "<ncurses.h>", importc.}
proc attroff(attrs: cint): cint {.header: "<ncurses.h>", importc.}
proc getmaxx(win: Window): cint {.header: "<ncurses.h>", importc.}
proc getmaxy(win: Window): cint {.header: "<ncurses.h>", importc.}
proc curs_set(mode: cint) {.header: "<ncurses.h>", importc.}
proc raw() {.header: "<ncurses.h>", importc.}
proc nonl() {.header: "<ncurses.h>", importc.}
proc nodelay(window: Window, state: bool): int {.header: "<ncurses.h>", importc.}
proc notimeout(window: Window, state: bool): int {.header: "<ncurses.h>", importc.}
proc timeout(t: cint) {.header: "<ncurses.h>", importc.}
proc has_mouse(): bool {.header: "<ncurses.h>", importc.}
proc mousemask(newmask: MouseMask, oldmask: ptr MouseMask): MouseMask {.header: "<ncurses.h>", importc.}
proc getmouse(evt: ptr MouseEvent): cint {.header: "<ncurses.h>", importc.}
proc mouseinterval(interval: cint): cint {.header: "<ncurses.h>", importc.}

var
  A_NORMAL {.header: "<ncurses.h>", importc.}: cint
  A_REVERSE {.header: "<ncurses.h>", importc.}: cint
  A_BOLD {.header: "<ncurses.h>", importc.}: cint
  A_DIM {.header: "<ncurses.h>", importc.}: cint
  LC_ALL {.header: "<locale.h>", importc.}: cint

var
  ALL_MOUSE_EVENTS {.header: "<ncurses.h>", importc.}: MouseMask
  REPORT_MOUSE_POSITION {.header: "<ncurses.h>", importc.}: MouseMask
  BUTTON1_PRESSED {.header: "<ncurses.h>", importc.}: MouseMask
  BUTTON1_RELEASED {.header: "<ncurses.h>", importc.}: MouseMask
  BUTTON2_PRESSED {.header: "<ncurses.h>", importc.}: MouseMask
  BUTTON2_RELEASED {.header: "<ncurses.h>", importc.}: MouseMask
  BUTTON3_PRESSED {.header: "<ncurses.h>", importc.}: MouseMask
  BUTTON3_RELEASED {.header: "<ncurses.h>", importc.}: MouseMask
  BUTTON4_PRESSED {.header: "<ncurses.h>", importc.}: MouseMask
  BUTTON4_RELEASED {.header: "<ncurses.h>", importc.}: MouseMask
  BUTTON5_PRESSED {.header: "<ncurses.h>", importc.}: MouseMask
  BUTTON5_RELEASED {.header: "<ncurses.h>", importc.}: MouseMask

  BUTTON1_CLICKED {.header: "<ncurses.h>", importc.}: MouseMask
  KEY_MOUSE_VALUE {.header: "<ncurses.h>", importc: "KEY_MOUSE".}: cint
  OK {.header: "<ncurses.h>", importc.}: cint


var stdscr {.header: "<ncurses.h>", importc.}: Window

proc terminal_width(): int = stdscr.getmaxx().int()
proc terminal_height(): int = stdscr.getmaxy().int()

type Terminal* = ref object
  # Initial State
  prev_mouse_mask: MouseMask
  prev_mouse_interval: cint
  # Input
  buttons: array[3, bool]
  ptime: Time
  pbutton: int
  pclicks: int
  # Rendering
  color_pairs: Table[tuple[fg, bg: Color], int]
  # Screen
  screen: TermScreen

proc new_terminal*(): Terminal =
  result = Terminal(pbutton: -1, ptime: get_time())
  setlocale(LC_ALL, "")
  discard initscr()
  discard disable_echo()
  discard start_color()
  discard use_default_colors()
  discard cbreak()
  nonl()
  discard keypad(stdscr, true)
  discard mousemask(ALL_MOUSE_EVENTS or REPORT_MOUSE_POSITION, result.prev_mouse_mask.addr)
  result.prev_mouse_interval = mouseinterval(0)

  timeout(10)
  raw()
  curs_set(0)
  stdout.write("\x1b[?1003h\n")
  result.screen = new_term_screen(terminal_width(), terminal_height())

proc destroy*(term: Terminal) =
  stdout.write("\x1b[?1003l\n")  
  
  discard mousemask(term.prev_mouse_mask, nil)
  discard mouseinterval(term.prev_mouse_interval)
  discard notimeout(stdscr, true)
  discard enable_echo()
  discard endwin()

proc recompute_screen_size*(term: Terminal) =
  let (width, height) = (terminal_width(), terminal_height())
  if width != term.screen.width or height != term.screen.height:
    term.screen.resize(width, height)

proc poll*(term: Terminal): bool = discard

proc read_key*(term: Terminal): Key =
  let key_code = getch().int()
  term.recompute_screen_size()
  
  if key_code == KEY_MOUSE_VALUE:
    return Key(kind: KeyMouse)
  
  case key_code:
    of -1: return Key(kind: KeyNone)
    of 263, 127: return Key(kind: KeyBackspace)
    of 13: return Key(kind: KeyReturn)
    of 27: return Key(kind: KeyEscape)
    of 259: return Key(kind: KeyArrowUp)
    of 258: return Key(kind: KeyArrowDown)
    of 260: return Key(kind: KeyArrowLeft)
    of 261: return Key(kind: KeyArrowRight)
    of 564: return Key(kind: KeyArrowUp, alt: true)
    of 523: return Key(kind: KeyArrowDown, alt: true)
    of 543: return Key(kind: KeyArrowLeft, alt: true)
    of 558: return Key(kind: KeyArrowRight, alt: true)
    of 566: return Key(kind: KeyArrowUp, ctrl: true)
    of 525: return Key(kind: KeyArrowDown, ctrl: true)
    of 545: return Key(kind: KeyArrowLeft, ctrl: true)
    of 560: return Key(kind: KeyArrowRight, ctrl: true)
    of 567: return Key(kind: KeyArrowUp, ctrl: true, shift: true)
    of 526: return Key(kind: KeyArrowDown, ctrl: true, shift: true)
    of 546: return Key(kind: KeyArrowLeft, ctrl: true, shift: true)
    of 561: return Key(kind: KeyArrowRight, ctrl: true, shift: true)
    of 337: return Key(kind: KeyArrowUp, shift: true)
    of 336: return Key(kind: KeyArrowDown, shift: true)
    of 393: return Key(kind: KeyArrowLeft, shift: true)
    of 402: return Key(kind: KeyArrowRight, shift: true)
    of 565: return Key(kind: KeyArrowUp, shift: true, alt: true)
    of 524: return Key(kind: KeyArrowDown, shift: true, alt: true)
    of 559: return Key(kind: KeyArrowRight, shift: true, alt: true)
    of 544: return Key(kind: KeyArrowLeft, shift: true, alt: true) 
    of 330: return Key(kind: KeyDelete)
    of 353: return Key(kind: KeyChar, chr: Rune('I'), ctrl: true, shift: true) 
    of 339: return Key(kind: KeyPageUp)
    of 338: return Key(kind: KeyPageDown)
    of 262: return Key(kind: KeyHome)
    of 360: return Key(kind: KeyEnd)
    of 391: return Key(kind: KeyHome, shift: true)
    of 386: return Key(kind: KeyEnd, shift: true)
    of 398: return Key(kind: KeyPageUp, shift: true)
    of 396: return Key(kind: KeyPageDown, shift: true)
    else: discard
  
  if key_code <= 26:
    return Key(
      kind: KeyChar,
      chr: Rune(char(key_code - 1 + ord('a'))),
      ctrl: true
    )
  
  if key_code >= 265 and key_code <= 276:
    return Key(kind: KeyFn, fn: key_code - 265 + 1)
    
  if key_code <= 255:
    var str = $chr(key_code)
    let len = str.rune_len_at(0)
    
    for it in 1..<len:
      str &= char(getch().int())
    
    return Key(kind: KeyChar, chr: str.rune_at(0))

  return Key(kind: KeyUnknown, key_code: key_code)

proc read_mouse*(term: Terminal): Mouse =
  var event: MouseEvent

  if getmouse(event.addr) != OK:
    return Mouse(kind: MouseNone)

  var
    state = true
    button = -1

  if (event.bstate and REPORT_MOUSE_POSITION) != 0:
    return Mouse(kind: MouseMove, x: event.x.int, y: event.y.int, buttons: term.buttons)
  elif (event.bstate and BUTTON1_PRESSED) != 0:
    button = 0
    state = true
  elif (event.bstate and BUTTON1_RELEASED) != 0:
    button = 0
    state = false
  elif (event.bstate and BUTTON2_PRESSED) != 0:
    button = 1
    state = true
  elif (event.bstate and BUTTON2_RELEASED) != 0:
    button = 1
    state = false
  elif (event.bstate and BUTTON3_PRESSED) != 0:
    button = 2
    state = true
  elif (event.bstate and BUTTON3_RELEASED) != 0:
    button = 2
    state = false
  elif (event.bstate and BUTTON4_PRESSED) != 0:
    return Mouse(kind: MouseScroll, delta: -1, x: event.x.int, y: event.y.int, buttons: term.buttons)
  elif (event.bstate and BUTTON4_RELEASED) != 0:
    return Mouse(kind: MouseScroll, delta: -1, x: event.x.int, y: event.y.int, buttons: term.buttons)
  elif (event.bstate and BUTTON5_PRESSED) != 0:
    return Mouse(kind: MouseScroll, delta: 1, x: event.x.int, y: event.y.int, buttons: term.buttons)
  elif (event.bstate and BUTTON5_RELEASED) != 0:
    return Mouse(kind: MouseScroll, delta: 1, x: event.x.int, y: event.y.int, buttons: term.buttons)
  
  if button == -1:
    return Mouse(kind: MouseUnknown,
      x: event.x.int, y: event.y.int,
      state: event.bstate.uint16,
      buttons: term.buttons
    )
  
  term.buttons[button] = state
  
  if term.pbutton == button and
     (get_time() - term.ptime).in_milliseconds() < 200:
    if state:
      term.pclicks += 1
  else:
    term.pclicks = 1
  
  if state:
    term.ptime = get_time()
    term.pbutton = button
  
  if state:
    return Mouse(kind: MouseDown,
      button: button, buttons: term.buttons,
      clicks: term.pclicks,
      x: event.x.int, y: event.y.int
    )
  else:
    return Mouse(kind: MouseUp,
      button: button, buttons: term.buttons,
      clicks: term.pclicks,
      x: event.x.int, y: event.y.int
    )

proc hash(color: Color): Hash =
  return !$(color.base.hash() !& color.bright.hash())

proc color_tuple(cell: CharCell): tuple[fg, bg: Color] =
  return (fg: cell.fg, bg: cell.bg)

proc ord(color: Color): int =
  if color.base == ColorDefault:
    return -1
  result = ord(color.base)

proc lookup_color_pair(term: Terminal, cell: CharCell): cshort =
  let index = cell.color_tuple()
  if index notin term.color_pairs:
    let id = term.color_pairs.len + 1
    discard init_pair(id.cshort, cell.fg.ord.cshort, cell.bg.ord.cshort)
    term.color_pairs[index] = id
    result = id.cshort
  else:
    result = term.color_pairs[index].cshort

proc redraw*(term: Terminal) =
  for y in 0..<term.screen.height:
    discard move(cint(y + 0), 0)
    for x in 0..<term.screen.width:
      let cell = term.screen[x, y]
      if cell.reverse:
        discard attron(A_REVERSE)
      else:
        discard attroff(A_REVERSE)
      
      discard color_set(term.lookup_color_pair(cell), nil)
      
      if cell.chr.ord < 128:
        discard addch(char(cell.chr.ord))
      else:
        discard addstr(cstring($cell.chr))
  discard refresh()

proc init_term_renderer*(term: Terminal): TermRenderer =
  result = init_term_renderer(term.screen)
