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

import times

type
  LogLevel* = enum
    LogInfo, LogWarning, LogError
  
  LogEntry* = object
    level*: LogLevel
    module*: string
    message*: string
    time*: Time
  
  Log* = ref object
    history*: seq[LogEntry]
    enabled*: bool

proc add*(log: Log, entry: LogEntry) =
  if log.enabled:
    log.history.add(entry)
    log.history[^1].time = get_time()

proc add_error*(log: Log, module, message: string) =
  log.add(LogEntry(level: LogError, module: module, message: message))

proc add_warning*(log: Log, module, message: string) =
  log.add(LogEntry(level: LogWarning, module: module, message: message))

proc add_info*(log: Log, module, message: string) =
  log.add(LogEntry(level: LogInfo, module: module, message: message))

proc enable*(log: Log) =
  log.enabled = true
  log.add_info("log", "Enable log")

proc disable*(log: Log) =
  log.add_info("log", "Disable log")
  log.enabled = false

proc clear*(log: Log) =
  log.history = @[]

proc new_log*(): Log =
  result = Log()
  when defined(enable_log):
    result.enable()
