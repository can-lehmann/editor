# Editor
A simple text editor written in Nim.

## Features
- Quick Open 
- Multiple Cursors
- Automatic Indentation
- Unicode Support (utf-8)
- Syntax Highlighting
- Multiple Windows

## Installation
### ncurses Backend
```bash
nim compile -r --opt:speed main.nim
```
  
### SDL2 Backend
Note: Requires https://github.com/nim-lang/sdl2
```bash
nim compile -r -o:main-sdl --opt:speed -d:sdl_backend main.nim
```

## Keyboard Bindings
### Window Management
- `Ctrl + P N Left/Right/Up/Down`: Create new window
- `Ctrl + P A`: Select Application
- `Ctrl + Left/Right/Up/Down` / `Alt + Left/Right/Up/Down`: Change active window
- `Ctrl + W`: Close active window
- `Ctrl + Q`: Quit

### Editor
- `Ctrl + N`: New
- `Ctrl + T`: Quick Open
- `Ctrl + S`: Save

- `Ctrl + F`: Find
- `Ctrl + E`: Close active prompt

- `Ctrl + C`: Copy
- `Ctrl + X`: Cut
- `Ctrl + V`: Paste

- `Tab`: Autocomplete word / Indent
- `Shift + Tab`: Unindent

- `Ctrl + Z`: Undo
- `Ctrl + Y`: Redo

#### Multiple Cursors
- `Ctrl + D`: Select next
- `Shift + Alt + Up/Down`: New cursor
- `Escape` / `Ctrl + O`: Remove cursors

## License
This project is licensed under the MIT License.
See LICENSE.txt for more details.
