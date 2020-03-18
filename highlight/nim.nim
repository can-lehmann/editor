import unicode, strutils
import highlight, "../utils"

type
  State = ref object of HighlightState
    it: int

const
  NIM_KEYWORDS = [
    # Converted from https://nim-lang.org/docs/manual.html
    "addr", "and", "as", "asm", "bind", "block",
    "break", "case", "cast", "concept", "const", "continue",
    "converter", "defer", "discard", "distinct", "div", "do",
    "elif", "else", "end", "enum", "except", "export", "finally",
    "for", "from", "func", "if", "import", "in", "include",
    "interface", "is", "isnot", "iterator", "let", "macro",
    "method", "mixin", "mod", "nil", "not", "notin", "object",
    "of", "or", "out", "proc", "ptr", "raise", "ref", "return",
    "shl", "shr", "static", "template", "try", "tuple", "type",
    "using", "var", "when", "while", "xor", "yield",
    
    "owned", "echo"
  ]
  
  NIM_TYPES = [
    "int", "int8", "int16", "int32", "int64",
    "byte", "uint8", "uint16", "uint32", "uint64",
    "float", "float64", "float32",
    "array", "string", "seq", "set", "tuple",
    "bool", "char", "auto", "pointer",
    "cint", "cshort", "cstring",
    "openArray", "Table", "Deque", "HashSet"
  ]

proc is_int(str: seq[Rune]): bool =
  for it, chr in str:
    if not ((chr.int64 >= 0 and chr.int64 <= 127 and char(chr).is_digit) or
            chr == '_' or
            (chr == '+' and it == 0 and str.len > 1) or
            (chr == '-' and it == 0 and str.len > 1)):
      return false
  return true

proc is_float(str: seq[Rune]): bool =
  var point = false
  for it, chr in str:
    if not ((chr.int64 >= 0 and chr.int64 <= 127 and char(chr).is_digit) or
            chr == '_' or
            (chr == '+' and it == 0 and str.len > 1) or
            (chr == '-' and it == 0 and str.len > 1)):
      if chr == '.' and not point and str.len > 1:
        point = true
      else:
        return false
  return true

proc token_kind(str: seq[Rune]): TokenKind =
  if $str == "true" or $str == "false":
    return TokenLiteral
  elif $str in NIM_KEYWORDS:
    return TokenKeyword
  elif $str in NIM_TYPES:
    return TokenType
  elif str.is_int or str.is_float:
    return TokenLiteral
  
  return TokenName

method next*(state: State, text: seq[Rune]): Token =
  var start = text.skip_whitespace(state.it)
  if start >= text.len:
    return Token(kind: TokenNone)  
  let chr = text[start]
  case chr:
    of '\"':
      let
        it = text.skip_string_like(start + 1)
        state = State(it: it + 1)
      return Token(kind: TokenString, start: start, stop: it + 1, state: state)
    of '\'':  
      let
        it = text.skip_string_like(start + 1, end_char='\'')
        state = State(it: it + 1)
      return Token(kind: TokenChar, start: start, stop: it + 1, state: state)
    of '#':
      if start + 1 < text.len and text[start + 1] == '[':
        var
          it = start + 2
          depth = 1
        while it < text.len and depth > 0:
          if text[it] == '#' and it + 1 < text.len and text[it + 1] == '[':
            depth += 1
            it += 1
          elif text[it] == ']' and it + 1 < text.len and text[it + 1] == '#':
            depth -= 1
            it += 1
          it += 1
        let state = State(it: it)
        return Token(kind: TokenComment, start: start, stop: it, state: state)
      else:
        var it = start + 1
        while it < text.len and text[it] != '\n':
          it += 1
        let state = State(it: it + 1)
        return Token(kind: TokenComment, start: start, stop: it, state: state)
    of ':', '<', '>', '[', ']', '(', ')', '{', '}', ',', ';', '=', '`':
      let state = State(it: start + 1)
      return Token(kind: TokenUnknown, start: start, stop: start + 1, state: state)
    else:
      var
        name: seq[Rune] = @[]
        it = start
      while it < text.len:
        let chr = text[it]
        case chr:
          of ' ', '\t', '\n', '\r', ':', '<', '>',
             '[', ']', '(', ')', '{', '}', ',', ';',
             '=', '`', '\"', '#', '\'':
            break
          else:
            name.add(chr)
        it += 1
      let state = State(it: it)
      return Token(kind: name.token_kind(), start: start, stop: it, state: state)

proc new_nim_highlighter*(): HighlightState = State()
