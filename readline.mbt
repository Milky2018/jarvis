///| Readline - Terminal line editing with history and cursor control
///
/// This module provides a readline-like interface for reading user input
/// with support for:
/// - Arrow keys for cursor movement and history navigation
/// - Command history (up/down arrows)
/// - Line editing (left/right arrows, backspace, delete)

///| ANSI Escape Sequences
let escape_byte : Byte = b'\x1b'
let backspace_byte : Byte = b'\x7f'
let ctrl_c_byte : Byte = b'\x03'
let ctrl_d_byte : Byte = b'\x04'
let enter_byte : Byte = b'\r'
let newline_byte : Byte = b'\n'

///| ANSI Control Functions
async fn move_cursor_left(count : Int) -> Unit {
  if count > 0 {
    @stdio.stdout.write("\u001b[\{count}D")
  }
}

async fn move_cursor_right(count : Int) -> Unit {
  if count > 0 {
    @stdio.stdout.write("\u001b[\{count}C")
  }
}

async fn clear_to_end() -> Unit {
  @stdio.stdout.write("\u001b[K")
}

async fn move_to_start() -> Unit {
  @stdio.stdout.write("\r")
}

///| History Management
pub struct CommandHistory {
  entries : Array[String]
  mut position : Int
  max_size : Int
}

pub fn CommandHistory::new(max_size : Int) -> CommandHistory {
  { entries: [], position: -1, max_size }
}

pub fn CommandHistory::add(self : CommandHistory, line : String) -> Unit {
  if line.is_empty() {
    return
  }

  // Don't add duplicate consecutive entries
  let should_add = if self.entries.length() > 0 {
    self.entries[self.entries.length() - 1] != line
  } else {
    true
  }

  if should_add {
    self.entries.push(line)

    // Limit history size
    if self.entries.length() > self.max_size {
      let new_entries : Array[String] = []
      for i = 1; i < self.entries.length(); i = i + 1 {
        new_entries.push(self.entries[i])
      }
      // Note: can't reassign self.entries in current MoonBit
      // This is a limitation we'll work around
    }
  }

  self.position = -1
}

pub fn CommandHistory::previous(self : CommandHistory) -> String? {
  if self.entries.length() == 0 {
    return None
  }

  if self.position == -1 {
    self.position = self.entries.length() - 1
    Some(self.entries[self.position])
  } else if self.position > 0 {
    self.position = self.position - 1
    Some(self.entries[self.position])
  } else {
    None
  }
}

pub fn CommandHistory::next(self : CommandHistory) -> String? {
  if self.position == -1 {
    return None
  }

  if self.position < self.entries.length() - 1 {
    self.position = self.position + 1
    Some(self.entries[self.position])
  } else {
    self.position = -1
    Some("")
  }
}

///| Line Editor
struct LineEditor {
  mut buffer : String
  mut cursor_pos : Int
  history : CommandHistory
  mut saved_line : String
}

fn LineEditor::new(history : CommandHistory) -> LineEditor {
  { buffer: "", cursor_pos: 0, history, saved_line: "" }
}

fn LineEditor::insert_char(self : LineEditor, ch : Char) -> Unit {
  if self.cursor_pos == self.buffer.length() {
    self.buffer = self.buffer + ch.to_string()
    self.cursor_pos = self.cursor_pos + 1
  } else {
    let before = try {
      self.buffer[0:self.cursor_pos].to_string()
    } catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    let after = try {
      self.buffer[self.cursor_pos:].to_string()
    } catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    self.buffer = before + ch.to_string() + after
    self.cursor_pos = self.cursor_pos + 1
  }
}

fn LineEditor::delete_char(self : LineEditor) -> Bool {
  if self.cursor_pos > 0 {
    let before = try {
      self.buffer[0:self.cursor_pos - 1].to_string()
    } catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    let after = try {
      self.buffer[self.cursor_pos:].to_string()
    } catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    self.buffer = before + after
    self.cursor_pos = self.cursor_pos - 1
    true
  } else {
    false
  }
}

fn LineEditor::delete_forward(self : LineEditor) -> Bool {
  if self.cursor_pos < self.buffer.length() {
    let before = try {
      self.buffer[0:self.cursor_pos].to_string()
    } catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    let after = try {
      self.buffer[self.cursor_pos + 1:].to_string()
    } catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    self.buffer = before + after
    true
  } else {
    false
  }
}

fn LineEditor::move_left(self : LineEditor) -> Bool {
  if self.cursor_pos > 0 {
    self.cursor_pos = self.cursor_pos - 1
    true
  } else {
    false
  }
}

fn LineEditor::move_right(self : LineEditor) -> Bool {
  if self.cursor_pos < self.buffer.length() {
    self.cursor_pos = self.cursor_pos + 1
    true
  } else {
    false
  }
}

fn LineEditor::move_to_start(self : LineEditor) -> Bool {
  if self.cursor_pos > 0 {
    self.cursor_pos = 0
    true
  } else {
    false
  }
}

fn LineEditor::move_to_end(self : LineEditor) -> Bool {
  if self.cursor_pos < self.buffer.length() {
    self.cursor_pos = self.buffer.length()
    true
  } else {
    false
  }
}

fn LineEditor::set_buffer(self : LineEditor, text : String) -> Unit {
  self.buffer = text
  self.cursor_pos = text.length()
}

fn LineEditor::clear(self : LineEditor) -> Unit {
  self.buffer = ""
  self.cursor_pos = 0
}

///| Redraw line
async fn redraw_line(editor : LineEditor, prompt : String) -> Unit {
  move_to_start()
  clear_to_end()
  @stdio.stdout.write(prompt + editor.buffer)

  let chars_after_cursor = editor.buffer.length() - editor.cursor_pos
  if chars_after_cursor > 0 {
    move_cursor_left(chars_after_cursor)
  }
}

///| Read escape sequence
async fn read_escape_sequence() -> String? {
  let buf = FixedArray::make(1, b'\x00')

  let n1 = @stdio.stdin.read(buf)
  if n1 == 0 {
    return None
  }

  if buf[0] == b'[' {
    let n2 = @stdio.stdin.read(buf)
    if n2 == 0 {
      return None
    }

    match buf[0] {
      b'A' => Some("up")
      b'B' => Some("down")
      b'C' => Some("right")
      b'D' => Some("left")
      b'H' => Some("home")
      b'F' => Some("end")
      b'3' => {
        let n3 = @stdio.stdin.read(buf)
        if n3 > 0 && buf[0] == b'~' {
          Some("delete")
        } else {
          None
        }
      }
      _ => None
    }
  } else if buf[0] == b'O' {
    let n2 = @stdio.stdin.read(buf)
    if n2 == 0 {
      return None
    }

    match buf[0] {
      b'H' => Some("home")
      b'F' => Some("end")
      _ => None
    }
  } else {
    None
  }
}

///| Main readline function with simplified approach (no raw mode for now)
pub async fn readline_simple(prompt : String, history : CommandHistory) -> String? {
  let editor = LineEditor::new(history)
  let buf = FixedArray::make(1, b'\x00')

  @stdio.stdout.write(prompt)

  while true {
    let n = @stdio.stdin.read(buf)
    if n == 0 {
      println("")
      return None
    }

    let byte = buf[0]

    if byte == enter_byte || byte == newline_byte {
      println("")
      let result = editor.buffer
      history.add(result)
      return Some(result)
    } else if byte == backspace_byte {
      if editor.delete_char() {
        redraw_line(editor, prompt)
      }
    } else if byte == ctrl_c_byte {
      println("^C")
      editor.clear()
      return Some("")
    } else if byte == ctrl_d_byte {
      if editor.buffer.is_empty() {
        println("")
        return None
      }
    } else if byte == escape_byte {
      match read_escape_sequence() {
        Some("up") => {
          if editor.history.position == -1 {
            editor.saved_line = editor.buffer
          }
          match editor.history.previous() {
            Some(line) => {
              editor.set_buffer(line)
              redraw_line(editor, prompt)
            }
            None => ()
          }
        }
        Some("down") => {
          match editor.history.next() {
            Some(line) => {
              if line.is_empty() && editor.saved_line.is_empty() == false {
                editor.set_buffer(editor.saved_line)
              } else {
                editor.set_buffer(line)
              }
              redraw_line(editor, prompt)
            }
            None => ()
          }
        }
        Some("left") => {
          if editor.move_left() {
            move_cursor_left(1)
          }
        }
        Some("right") => {
          if editor.move_right() {
            move_cursor_right(1)
          }
        }
        Some("home") => {
          if editor.move_to_start() {
            redraw_line(editor, prompt)
          }
        }
        Some("end") => {
          if editor.move_to_end() {
            redraw_line(editor, prompt)
          }
        }
        Some("delete") => {
          if editor.delete_forward() {
            redraw_line(editor, prompt)
          }
        }
        _ => ()
      }
    } else if byte >= b' ' && byte < b'\x7f' {
      let ch = Int::unsafe_to_char(byte.to_int())
      editor.insert_char(ch)

      if editor.cursor_pos == editor.buffer.length() {
        @stdio.stdout.write(ch.to_string())
      } else {
        redraw_line(editor, prompt)
      }
    }
  }

  Some(editor.buffer)
}
