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

import tables, unicode, sequtils, sugar
import ../utils, ../buffer, ../highlight/highlight, autocomplete

proc new_markdown_autocompleter*(): Autocompleter =
  SimpleContext(
    defs: to_table({
      TokenHeading: DefHeading
    })
  )

const HTML_TAGS = map(@[
  "html", "head", "meta", "title", "body", "p",
  "div", "span", "h1", "h2", "h3", "h4", "h5",
  "h6", "iframe", "script", "img", "a",
  "table", "thead", "tr", "td", "th", "tbody", "tfoot",
  "caption", "input", "button", "code", "template",
  "noscript", "textarea"
], tag => Completion(kind: CompTag, text: to_runes(tag)))

proc new_html_autocompleter*(): Autocompleter =
  SimpleContext(
    defs: to_table({
      TokenTag: DefTag
    }),
    comps: HTML_TAGS,
    triggers: @[
      Rune('<'), Rune('/')
    ],
    finish: @[
      Rune(' '), Rune('\n'), Rune('\r'), Rune('\t'),
      Rune('='), Rune('>')
    ],
    min_word_len: 3
  )


