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

import strutils, sequtils, sugar, tables, unicode
import window_manager, termdiff, utils, ui_utils

const
  OPERATORS = {"+": 1, "-": 1, "*": 2, "/": 2}.to_table

type
  NodeKind = enum NodeAdd, NodeSub, NodeMul, NodeDiv, NodeValue
  Node = ref object
    case kind: NodeKind:
      of NodeAdd, NodeSub, NodeMul, NodeDiv:
        a: Node
        b: Node
      of NodeValue:
        value: float64

proc stringify(node: Node, level: int): string =
  case node.kind:
    of NodeValue: return $node.value
    of NodeAdd:
      result = node.a.stringify(1) & " + " & node.b.stringify(1)
      if level > 1:
        result = "(" & result & ")"
    of NodeSub:
      result = node.a.stringify(1) & " - " & node.b.stringify(2)
      if level > 1:
        result = "(" & result & ")"
    of NodeMul:
      result = node.a.stringify(2) & " * " & node.b.stringify(2)
      if level > 1:
        result = "(" & result & ")"
    of NodeDiv:
      result = node.a.stringify(2) & " / " & node.b.stringify(3)
      if level > 2:
        result = "(" & result & ")"

proc `$`(node: Node): string = node.stringify(0)

proc eval(node: Node): float64 =
  case node.kind:
    of NodeValue: return node.value
    of NodeAdd: return node.a.eval() + node.b.eval()
    of NodeSub: return node.a.eval() - node.b.eval()
    of NodeMul: return node.a.eval() * node.b.eval()
    of NodeDiv: return node.a.eval() / node.b.eval()

converter to_node(x: float64): Node = Node(kind: NodeValue, value: x)

type
  TokenKind = enum TokenValue, TokenName, TokenOpen, TokenClose, TokenString
  Token = object
    kind: TokenKind
    value: string

proc is_float(str: string): bool =
  var point = false
  for it, chr in str:
    if chr.is_digit:
      continue
    if it == 0 and (chr == '+' or chr == '-') and str.len > 1:
      continue
    if chr == '.' and not point:
      point = true
      continue
    return false
  return true

proc make_token(str: string): Token =
  if str.is_float:
    return Token(kind: TokenValue, value: str)
  return Token(kind: TokenName, value: str)

proc tokenize(str: string): seq[Token] =
  type Mode = enum ModeNone, ModeString
  var
    it = 0
    cur = ""
    mode = ModeNone
  while it < str.len:
    let chr = str[it]
    
    case mode:
      of ModeString:
        if chr == '\"':
          result.add(Token(kind: TokenString, value: cur))
          cur = ""
          mode = ModeNone
        else:
          cur &= chr
      of ModeNone:
        case chr:
          of ' ', '(', ')', '\n', ',', '\"':
            if cur != "":
              result.add(make_token(cur))
              cur = ""
            case chr:
              of '(': result.add(Token(kind: TokenOpen))
              of ')': result.add(Token(kind: TokenClose))
              of '\"': mode = ModeString
              else: discard
          else:
            cur &= chr

    it += 1

  if cur != "":
    result.add(make_token(cur))

type
  TokenIter = object
    cur: int
    tokens: seq[Token]

proc next(iter: TokenIter, kind: TokenKind): bool =
  if iter.cur >= iter.tokens.len:
    return false
  return iter.tokens[iter.cur].kind == kind

proc take(iter: var TokenIter, kind: TokenKind): bool =
  if iter.next(kind):
    iter.cur += 1
    return true
  return false

proc is_done(iter: TokenIter): bool = iter.cur >= iter.tokens.len
proc token(iter: TokenIter): Token = iter.tokens[iter.cur - 1]

proc back(iter: var TokenIter) = iter.cur -= 1

proc parse(iter: var TokenIter, level: int = 0): Node =
  if iter.take(TokenValue):
    result = Node(kind: NodeValue, value: iter.token().value.parse_float())
  elif iter.take(TokenOpen):
    result = iter.parse()
    discard iter.take(TokenClose)
  
  if result == nil:
    return
  
  while iter.take(TokenName):
    let value = iter.token().value
    if value notin OPERATORS or OPERATORS[value] <= level:
      iter.back()
      return
    
    let b = iter.parse(OPERATORS[value])
    if b == nil:
      return nil
    
    case value:
      of "+":  result = Node(kind: NodeAdd, a: result, b: b)
      of "-":  result = Node(kind: NodeSub, a: result, b: b)
      of "*":  result = Node(kind: NodeMul, a: result, b: b)
      of "/":  result = Node(kind: NodeDiv, a: result, b: b)   
      else: quit "Unreachable"

proc parse(str: string): Node =
  var
    tokens = str.tokenize()
    iter = TokenIter(tokens: tokens, cur: 0)
  return iter.parse()
  
type
  Input = object
    entry: Entry
    output: Node

  Calc* = ref object of Window
    app: App
    inputs: seq[Input]
    selected: int
    scroll: Index2d

proc make_input(app: App): Input =
  return Input(entry: make_entry(app.copy_buffer), output: nil)

proc make_input(calc: Calc): Input = calc.app.make_input()

proc max_input_number_width(calc: Calc): int =
  ($calc.inputs.len).len + 2

method process_mouse*(calc: Calc, mouse: Mouse): bool =
  if mouse.y == 0 and mouse.x < calc.max_input_number_width:
    return true
  
  if (mouse.y - 1) mod 3 == 0:
    if mouse.kind == MouseDown:
      calc.selected = (mouse.y - 1) div 3
      calc.selected = max(min(calc.selected, calc.inputs.len - 1), 0)
    var mouse_rel = mouse
    mouse_rel.x -= calc.max_input_number_width + 1
    mouse_rel.y = 0
    calc.inputs[calc.selected].entry.process_mouse(mouse_rel)

method process_key*(calc: Calc, key: Key) =
  case key.kind:
    of KeyReturn:
      calc.inputs.insert(calc.make_input(), calc.selected + 1)
      calc.selected += 1
    of KeyArrowDown:
      calc.selected += 1
      if calc.selected >= calc.inputs.len:
        calc.selected = calc.inputs.len - 1
    of KeyArrowUp:
      calc.selected -= 1
      if calc.selected < 0:
        calc.selected = 0
    else:
      calc.inputs[calc.selected].entry.process_key(key)
      let node = ($calc.inputs[calc.selected].entry.text).parse()
      if node != nil:
        calc.inputs[calc.selected].output = node.eval()
      else:
        calc.inputs[calc.selected].output = nil

proc input_number(calc: Calc, n: int): string =
  return "[" & strutils.align($n, ($calc.inputs.len).len) & "]"

method render*(calc: Calc, box: Box, ren: var TermRenderer) =
  let
    title = repeat(' ', calc.max_input_number_width() + 1) &
            unicode.align_left("Calculator", box.size.x - calc.max_input_number_width() - 1)
  ren.move_to(box.min)
  ren.put(title, fg=Color(base: ColorBlack), bg=Color(base: ColorWhite, bright: true))
  
  for y in 0..<(box.size.y - 1):
    ren.move_to(box.min.x, box.min.y + 1 + y)
    ren.put(
      repeat(' ', calc.max_input_number_width()),
      fg=Color(base: ColorBlack),
      bg=Color(base: ColorWhite, bright: true)
    )

  for it, input in calc.inputs:
    ren.move_to(box.min.x, box.min.y + it * 3 + 1)
    ren.put(
      calc.input_number(it),
      fg=Color(base: ColorBlack),
      bg=Color(base: ColorWhite, bright: true)
    )
    ren.move_to(box.min.x + calc.max_input_number_width + 1, box.min.y + it * 3 + 1)    
    if it == calc.selected:
      input.entry.render(ren)
    else:
      ren.put(input.entry.text)
    
    if input.output != nil:
      ren.move_to(box.min.x + calc.max_input_number_width + 1, box.min.y + it * 3 + 2)
      ren.put($input.output)
    
proc make_calc*(app: App): Window =
  return Calc(app: app, inputs: @[app.make_input()])
