# MIT License
# 
# Copyright (c) 2019 pseudo-random <josh.leh.2018@gmail.com>
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

type  
  Index2d* = object
    x*: int
    y*: int
  
  Box* = object
    min*: Index2d
    max*: Index2d

  Direction* = enum DirUp, DirDown, DirLeft, DirRight

proc `+`*(a, b: Index2d): Index2d = Index2d(x: a.x + b.x, y: a.y + b.y)
proc `-`*(a, b: Index2d): Index2d = Index2d(x: a.x - b.x, y: a.y - b.y)

proc size*(box: Box): Index2d = box.max - box.min
proc is_inside*(box: Box, pos: Index2d): bool =
  return pos.x >= box.min.x and pos.x < box.max.x and
         pos.y >= box.min.y and pos.y < box.max.y

proc to_index2d*(dir: Direction): Index2d =
  case dir:
    of DirUp: return Index2d(x: 0, y: -1)
    of DirDown: return Index2d(x: 0, y: 1)
    of DirLeft: return Index2d(x: -1, y: 0)
    of DirRight: return Index2d(x: 1, y: 0)
