import unicode, strutils
import highlight, "../utils"

type State = ref object of HighlightState
  it: int
  is_tag: bool

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
    of '<', '>', '/', '=':
      var is_tag = false
      case chr:
        of '<': is_tag = true
        of '/': is_tag = state.is_tag
        else: discard
      let state = State(it: start + 1, is_tag: is_tag)
      return Token(kind: TokenUnknown, start: start, stop: start + 1, state: state)
    else:
      var
        name: seq[Rune] = @[]
        it = start
      while it < text.len:
        let chr = text[it]
        case chr:
          of ' ', '\t', '\n', '\r', '<', '>', '/', '=':
            break
          else:
            name.add(chr)
        it += 1
      var kind = TokenName
      if state.is_tag:
        kind = TokenKeyword
      return Token(kind: kind, start: start, stop: it, state: State(it: it))

proc new_html_highlighter*(): HighlightState = State()
