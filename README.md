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
nim compile -r --opt:speed main.nim
```

### SDL2 Backend
The sdl backend requires the [sdl2 module](https://github.com/nim-lang/sdl2).
You also need to supply your own font which has to be placed in `assets/font.ttf`.

```bash
nim compile -r -o:main-sdl --opt:speed -d:sdl_backend main.nim
```

## Keyboard Bindings
### Window Management
- <kbd>Ctrl</kbd><kbd>P N Left/Right/Up/Down</kbd>: Create new window
- <kbd>Ctrl</kbd><kbd>P A</kbd>: Select Application
- <kbd>Ctrl</kbd><kbd>Left/Right/Up/Down<kbd> / <kbd>Alt</kbd><kbd>Left/Right/Up/Down</kbd>: Change active window
- <kbd>Ctrl</kbd><kbd>W</kbd>: Close active window
- <kbd>Ctrl</kbd><kbd>Q</kbd>: Quit

- <kbd>F1</kbd>: Search command

### Editor
- <kbd>Ctrl</kbd><kbd>N</kbd>: New
- <kbd>Ctrl</kbd><kbd>T</kbd>: Quick Open
- <kbd>Ctrl</kbd><kbd>S</kbd>: Save

- <kbd>Ctrl</kbd><kbd>R</kbd>: Find definition
- <kbd>Ctrl</kbd><kbd>F</kbd>: Find
- <kbd>Ctrl</kbd><kbd>G</kbd>: Go to line
- <kbd>Ctrl</kbd><kbd>E</kbd>: Close active prompt

- <kbd>Ctrl</kbd><kbd>C</kbd>: Copy
- <kbd>Ctrl</kbd><kbd>X</kbd>: Cut
- <kbd>Ctrl</kbd><kbd>V</kbd>: Paste

- <kbd>F2</kbd>: Show autocomplete
- <kbd>Tab</kbd>: Autocomplete word / Indent
- <kbd>Shift</kbd><kbd>Tab</kbd>: Unindent

- <kbd>Ctrl</kbd><kbd>Z</kbd>: Undo
- <kbd>Ctrl</kbd><kbd>Y</kbd>: Redo
- <kbd>Ctrl</kbd><kbd>O</kbd>: Jump to matching bracket
- <kbd>Ctrl</kbd><kbd>Shift</kbd><kbd>O</kbd>: Select bracket

#### Multiple Cursors
- <kbd>Ctrl</kbd><kbd>D</kbd>: Select next
- <kbd>Shift</kbd><kbd>Alt</kbd><kbd>Up/Down</kbd>: New cursor
- <kbd>Escape</kbd>: Remove cursors
- <kbd>Ctrl</kbd><kbd>U</kbd>: Remove last cursor

## License
This project is licensed under the MIT License.
See LICENSE.txt for more details.

