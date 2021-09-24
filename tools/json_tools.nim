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

import json, sugar, unicode, strutils, algorithm
import base_tools, ".." / [editor, buffer]

proc make_indent(level: int, width: int = 2): string =
  for it in 0..<level:
    for it2 in 0..<width:
      result.add(' ')

proc print_string(str: string): string =
  for rune in str.to_runes():
    case rune:
      of Rune('\n'): result &= "\\n"
      of Rune('\r'): result &= "\\r"
      of Rune('\t'): result &= "\\t"
      of Rune('\\'): result &= "\\\\"
      of Rune('/'): result &= "\\/"
      of Rune('\"'): result &= "\\\""
      else:
        if int(rune) < 128:
          result.add(char(rune))
        else:
          const digits = "0123456789ABCDEF"
          var
            cur = int(rune)
            num = ""
          for it in 0..<4:
            num.add(digits[cur mod 16])
            cur = cur div 16
          num.reverse()
          result &= "\\u" & num
  result = "\"" & result & "\""

proc pretty_print(node: JsonNode, indent: int, use_indent: bool): string =
  if use_indent:
    result = make_indent(indent)
  
  case node.kind:
    of JNull: result &= "null"
    of JBool: result &= $node.get_bool()
    of JInt: result &= $node.get_int()
    of JFloat: result &= $node.get_float()
    of JString: result &= node.get_str().print_string()
    of JArray:
      result &= "[\n"
      var it = 0
      for item in node:
        if it != 0:
          result &= ",\n"
        result &= item.pretty_print(indent + 1, true)
        it += 1
      result &= "\n" & make_indent(indent) & "]"
    of JObject:
      result &= "{\n"
      var it = 0
      for name, value in node:
        if it != 0:
          result &= ",\n"
        result &= make_indent(indent + 1) & name.print_string() & ": "
        result &= value.pretty_print(indent + 1, false)
        it += 1
      result &= "\n" & make_indent(indent) & "}"

editor_tools.add(Tool(
  name: "Minify Json",
  callback: wrap_replace_selection(text => $parse_json(text))
))

editor_tools.add(Tool(
  name: "Pretty Print Json",
  callback: wrap_replace_selection(text =>
    pretty_print(text.parse_json(), 0, true)
  )
))
