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

import unicode, strutils

type Index2d* = object
  x*: int
  y*: int

{.push inline.}
proc `+`*(a, b: Index2d): Index2d = Index2d(x: a.x + b.x, y: a.y + b.y)
proc `-`*(a, b: Index2d): Index2d = Index2d(x: a.x - b.x, y: a.y - b.y)
proc `*`*(a: Index2d, factor: int): Index2d = Index2d(x: a.x * factor, y: a.y * factor)
{.pop.}

type Box* = object
  min*: Index2d
  max*: Index2d

proc size*(box: Box): Index2d = box.max - box.min
proc is_inside*(box: Box, pos: Index2d): bool =
  return pos.x >= box.min.x and pos.x < box.max.x and
         pos.y >= box.min.y and pos.y < box.max.y

type Direction* = enum DirLeft, DirRight, DirUp, DirDown

proc to_index2d*(dir: Direction): Index2d =
  case dir:
    of DirUp: result = Index2d(x: 0, y: -1)
    of DirDown: result = Index2d(x: 0, y: 1)
    of DirLeft: result = Index2d(x: -1, y: 0)
    of DirRight: result = Index2d(x: 1, y: 0)

proc on_axis*(dir: Direction): int {.inline.} = (ord(dir) mod 2) * 2 - 1

type Axis* = enum AxisX, AxisY

proc `not`*(axis: Axis): Axis = Axis((ord(axis) + 1) mod 2)
proc to_axis*(dir: Direction): Axis = Axis(ord(dir) div 2)

{.push inline.}
proc `[]`*(index: Index2d, axis: Axis): int = [index.x, index.y][ord(axis)]
proc `[]`*(index: var Index2d, axis: Axis): var int = [index.x.addr, index.y.addr][ord(axis)][]
proc `[]=`*(index: var Index2d, axis: Axis, val: int) = [index.x.addr, index.y.addr][ord(axis)][] = val
{.pop.}

proc is_ascii*(rune: Rune): bool = rune.int32 < 127
proc to_char*(rune: Rune): char = rune.int32.char

proc is_alpha_numeric*(rune: Rune): bool =
  is_alpha(rune) or (is_ascii(rune) and to_char(rune).is_digit())

proc substr*(text: seq[Rune], first: int): seq[Rune] =
  result = new_seq[Rune](text.len - first)
  for it in first..<text.len:
    result[it - first] = text[it]

proc substr*(text: seq[Rune], first, last: int): seq[Rune] =
  result = new_seq[Rune](last - first + 1)
  var it2 = 0
  for it in max(first, 0)..min(last, text.len - 1):
    result[it2] = text[it]
    it2 += 1

proc pattern_at*(text, pattern: seq[Rune], pos: int): bool =
  if pos + pattern.len <= text.len:
    result = true
    for it in 0..<pattern.len:
      if text[it + pos] != pattern[it]:
        return false

proc pattern_at*(text: seq[Rune], pattern: string, pos: int): bool =
  return text.pattern_at(pattern.to_runes(), pos)

proc find*(text: seq[Rune], pattern: seq[Rune], start: int = 0): int =
  result = -1
  for it in start..<(text.len - pattern.len + 1):
    if text.pattern_at(pattern, it):
      return it

proc contains*(text: seq[Rune], pattern: seq[Rune]): bool =
  result = text.find(pattern) != -1

proc find_all*(text: seq[Rune], pattern: seq[Rune]): seq[int] =
  for it in 0..<(text.len - pattern.len + 1):
    if text.pattern_at(pattern, it):
      result.add(it)

proc join*(strs: seq[seq[Rune]], chr: Rune): seq[Rune] =
  result = @[]
  for it, str in strs:
    if it != 0:
      result.add(chr)
    result &= str

proc join*(strs: seq[seq[Rune]]): seq[Rune] =
  for str in strs:
    result &= str

proc split*(str: seq[Rune], delimiter: Rune): seq[seq[Rune]] =
  result.add(@[])
  for chr in str:
    if chr == delimiter:
      result.add(@[])
    else:
      result[^1].add(chr)

proc capitalize*(str: seq[Rune]): seq[Rune] =
  if str.len == 0:
    return str
  return @[str[0].to_upper()] & str[1..^1]

converter to_rune*(chr: char): Rune = Rune(chr)
