# Editor
A text editor written in Nim.

## Features
- Quick Open 
- Multiple Cursors
- Automatic Indentation
- Unicode Support (utf-8)
- Syntax Highlighting
- Multiple Windows
- Autocompletion using Nimsuggest
- Mouse Support

## Installation
### ncurses Backend
When using the ncurses backend, the development package for
ncurses needs to be installed.

```bash
nim compile -r --opt:speed --threads:on main.nim
```

### SDL2 Backend
The sdl backend requires the [sdl2 module](https://github.com/nim-lang/sdl2).
You also need to supply your own font which has to be placed in `assets/font.ttf`.

```bash
nim compile -r -o:main-sdl --opt:speed -d:sdl_backend --threads:on main.nim
```

## Keyboard Bindings
### Window Management
- `Ctrl + P N Left/Right/Up/Down`: Create new window
- `Ctrl + P A`: Select Application
- `Ctrl + Left/Right/Up/Down` / `Alt + Left/Right/Up/Down`: Change active window
- `Ctrl + W`: Close active window
- `Ctrl + Q`: Quit

- `F1`: Search command

### Editor
- `Ctrl + N`: New
- `Ctrl + T`: Quick Open
- `Ctrl + S`: Save

- `Ctrl + R`: Find definition
- `Ctrl + F`: Find
- `Ctrl + G`: Go to line
- `Ctrl + E`: Close active prompt

- `Ctrl + C`: Copy
- `Ctrl + X`: Cut
- `Ctrl + V`: Paste

- `F2`: Show autocomplete
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

