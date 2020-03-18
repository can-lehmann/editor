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

import unicode, sequtils, sugar, sets, tables, algorithm
import buffer, utils, highlight/highlight

type
  AutocompleteContext* = ref object
    buffer: Buffer
    words: Table[seq[Rune], int]

  Completion* = object
    text*: seq[Rune]
    pos*: int
    distance: int
    freq: int

proc text_left*(completion: Completion): seq[Rune] =
  completion.text.substr(completion.pos)

proc count_words(buffer: Buffer): Table[seq[Rune], int] =
  var word: seq[Rune] = @[]
  for it, chr in buffer.text:
    case chr:
      of ' ', '\t', '\n', '\r', '.', ':', '(', ')', '[', ']', '{', '}', '<', '>', '\\', '/', '*', '=', ',', ';', '!', '?', '\"':
        if word.len > 0:
          if not result.has_key(word):
            result[word] = 0
          result[word] += 1
          word = @[]
      else:
        word.add(chr)
        
  if word.len > 0:
    if not result.has_key(word):
      result[word] = 0
    result[word] += 1
    word = @[]

proc make_autocomplete_context*(buffer: Buffer): AutocompleteContext =
  return AutocompleteContext(
    buffer: buffer,
    words: buffer.count_words()
  )

proc recount_words*(ctx: AutocompleteContext) =
  ctx.words = ctx.buffer.count_words()

proc compute_dist(a, b: seq[Rune]): int =
  for it in 0..<min(a.len, b.len):
    if a[it] != b[it]:
      result += 1

proc `<`(a, b: Completion): bool =
  if a.distance == b.distance:
    if b.freq == -1:
      return false
    elif a.freq == -1:
      return true
    return a.freq > b.freq
  return a.distance < b.distance

proc predict(ctx: AutocompleteContext, current_word: seq[Rune]): seq[Completion] =
  if current_word.len <= 2:
    return

  for word, freq in ctx.words:
    if word.len < current_word.len:
      continue
    result.add(Completion(
      text: word,
      pos: current_word.len,
      distance: current_word.compute_dist(word),
      freq: freq
    ))

  if ctx.buffer.language != nil:
    let snippets = ctx.buffer.language.snippets
    for word in snippets.keys:
      if word.len < current_word.len:
        continue
      result.add(Completion(
        text: snippets[word],
        pos: current_word.len,
        distance: current_word.compute_dist(word),
        freq: -1
      ))
    
  result.sort()

proc predict*(ctx: AutocompleteContext, initial_pos: int): seq[Completion] =
  var
    word: seq[Rune] = @[]
    pos = initial_pos - 1
  while pos >= 0:
    let chr = ctx.buffer.text[pos]
    if chr in to_runes(" \t\n\r.:*;,()[]{}<>\\/"):
      break
    word = chr & word
    pos -= 1

  return ctx.predict(word)
