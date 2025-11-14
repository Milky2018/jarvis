///| Readline - Terminal line editing with history and cursor control
///
/// This module provides a readline-like interface for reading user input
/// with support for:
/// - Arrow keys for cursor movement and history navigation
/// - Command history (up/down arrows)
/// - Line editing (left/right arrows, backspace, delete)
///
/// Architecture:
/// - Runs in a background coroutine to allow immediate Ctrl+C response
/// - Communicates with main coroutine via async queue

///|
/// Readline interface for direct use in main loop
struct ReadlineInterface {
  mut prompt : String
  history : CommandHistory
}

///|
/// Create a new readline interface
fn ReadlineInterface::new(history_size : Int) -> ReadlineInterface {
  { prompt: "> ", history: CommandHistory::new(history_size) }
}

///|
/// Set the prompt for next readline
fn ReadlineInterface::set_prompt(
  self : ReadlineInterface,
  prompt : String
) -> Unit {
  self.prompt = prompt
}

///|
/// Read a line from user (blocking, waits for user input)
async fn ReadlineInterface::read_line(
  self : ReadlineInterface
) -> String? raise {
  readline_simple(self.prompt, self.history)
}

///|
/// Key press events
enum KeyPress {
  Char(Char)
  Enter
  Backspace
  Delete
  CtrlC
  CtrlD
  CtrlU  // Delete to start
  CtrlW  // Delete word backward
  CtrlA  // Move to start
  CtrlE  // Move to end
  Up
  Down
  Left
  Right
  Home
  End
  OptionLeft   // Word backward
  OptionRight  // Word forward
  OptionDelete // Delete word backward
  CmdLeft      // Move to start
  CmdRight     // Move to end
  CmdDelete    // Delete to start
  PasteStart   // Bracketed paste start
  PasteEnd     // Bracketed paste end
  Unknown
}

///|
/// ANSI Escape Sequences
let backspace_byte : Byte = b'\x7f'

///|
/// ANSI Control Functions
async fn move_cursor_left(count : Int) -> Unit {
  if count > 0 {
    @stdio.stdout.write("\u001b[\{count}D")
  }
}

///|
async fn move_cursor_right(count : Int) -> Unit {
  if count > 0 {
    @stdio.stdout.write("\u001b[\{count}C")
  }
}

///|
async fn clear_to_end() -> Unit {
  @stdio.stdout.write("\u001b[K")
}

///|
async fn move_to_start() -> Unit {
  @stdio.stdout.write("\r")
}

///|
/// History Management
struct CommandHistory {
  entries : Array[String]
  mut position : Int
  max_size : Int
}

///|
fn CommandHistory::new(max_size : Int) -> CommandHistory {
  { entries: [], position: -1, max_size }
}

///|
fn CommandHistory::add(self : CommandHistory, line : String) -> Unit {
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

///|
fn CommandHistory::previous(self : CommandHistory) -> String? {
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

///|
fn CommandHistory::next(self : CommandHistory) -> String? {
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

///|
/// Line Editor
struct LineEditor {
  mut buffer : String
  mut cursor_pos : Int
  history : CommandHistory
  mut saved_line : String
}

///|
fn LineEditor::new(history : CommandHistory) -> LineEditor {
  { buffer: "", cursor_pos: 0, history, saved_line: "" }
}

///|
fn LineEditor::insert_char(self : LineEditor, ch : Char) -> Unit {
  if self.cursor_pos == self.buffer.length() {
    self.buffer = self.buffer + ch.to_string()
    self.cursor_pos = self.cursor_pos + 1
  } else {
    let before = self.buffer[0:self.cursor_pos].to_string() catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    let after = self.buffer[self.cursor_pos:].to_string() catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    self.buffer = before + ch.to_string() + after
    self.cursor_pos = self.cursor_pos + 1
  }
}

///|
fn LineEditor::delete_char(self : LineEditor) -> Bool {
  if self.cursor_pos > 0 {
    let before = self.buffer[0:self.cursor_pos - 1].to_string() catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    let after = self.buffer[self.cursor_pos:].to_string() catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    self.buffer = before + after
    self.cursor_pos = self.cursor_pos - 1
    true
  } else {
    false
  }
}

///|
fn LineEditor::delete_forward(self : LineEditor) -> Bool {
  if self.cursor_pos < self.buffer.length() {
    let before = self.buffer[0:self.cursor_pos].to_string() catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    let after = self.buffer[self.cursor_pos + 1:].to_string() catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    self.buffer = before + after
    true
  } else {
    false
  }
}

///|
fn LineEditor::move_left(self : LineEditor) -> Bool {
  if self.cursor_pos > 0 {
    self.cursor_pos = self.cursor_pos - 1
    true
  } else {
    false
  }
}

///|
fn LineEditor::move_right(self : LineEditor) -> Bool {
  if self.cursor_pos < self.buffer.length() {
    self.cursor_pos = self.cursor_pos + 1
    true
  } else {
    false
  }
}

///|
fn LineEditor::move_to_start(self : LineEditor) -> Bool {
  if self.cursor_pos > 0 {
    self.cursor_pos = 0
    true
  } else {
    false
  }
}

///|
fn LineEditor::move_to_end(self : LineEditor) -> Bool {
  if self.cursor_pos < self.buffer.length() {
    self.cursor_pos = self.buffer.length()
    true
  } else {
    false
  }
}

///|
fn LineEditor::set_buffer(self : LineEditor, text : String) -> Unit {
  self.buffer = text
  self.cursor_pos = text.length()
}

///|
/// Calculate display width of a character
/// Most CJK characters have width 2, ASCII has width 1
fn char_display_width(ch : Char) -> Int {
  let code = ch.to_int()
  // CJK Unified Ideographs: 0x4E00-0x9FFF
  // CJK Extension A: 0x3400-0x4DBF
  // Hangul Syllables: 0xAC00-0xD7AF
  // Hiragana: 0x3040-0x309F
  // Katakana: 0x30A0-0x30FF
  // Full-width forms: 0xFF00-0xFFEF
  if (code >= 0x4E00 && code <= 0x9FFF) ||
    (code >= 0x3400 && code <= 0x4DBF) ||
    (code >= 0xAC00 && code <= 0xD7AF) ||
    (code >= 0x3040 && code <= 0x309F) ||
    (code >= 0x30A0 && code <= 0x30FF) ||
    (code >= 0xFF00 && code <= 0xFFEF) {
    2
  } else {
    1
  }
}

///|
/// Check if a character is a word separator
fn is_word_separator(ch : Char) -> Bool {
  ch == ' ' ||
  ch == '\t' ||
  ch == '\n' ||
  ch == '/' ||
  ch == '\\' ||
  ch == '.' ||
  ch == ',' ||
  ch == ';' ||
  ch == ':' ||
  ch == '-' ||
  ch == '_' ||
  ch == '=' ||
  ch == '+' ||
  ch == '*' ||
  ch == '&' ||
  ch == '|' ||
  ch == '<' ||
  ch == '>' ||
  ch == '(' ||
  ch == ')' ||
  ch == '[' ||
  ch == ']' ||
  ch == '{' ||
  ch == '}' ||
  ch == '\'' ||
  ch == '"' ||
  ch == '`' ||
  ch == '!' ||
  ch == '?' ||
  ch == '@' ||
  ch == '#' ||
  ch == '$' ||
  ch == '%' ||
  ch == '^'
}

///|
/// Move cursor forward by one word
fn LineEditor::move_word_forward(self : LineEditor) -> Bool {
  if self.cursor_pos >= self.buffer.length() {
    return false
  }
  let mut pos = self.cursor_pos
  let len = self.buffer.length()

  // Skip current word separators
  while pos < len {
    match self.buffer.get_char(pos) {
      Some(ch) => {
        if is_word_separator(ch) == false {
          break
        }
        pos = pos + 1
      }
      None => break
    }
  }

  // Skip word characters
  while pos < len {
    match self.buffer.get_char(pos) {
      Some(ch) => {
        if is_word_separator(ch) {
          break
        }
        pos = pos + 1
      }
      None => break
    }
  }
  if pos != self.cursor_pos {
    self.cursor_pos = pos
    true
  } else {
    false
  }
}

///|
/// Move cursor backward by one word
fn LineEditor::move_word_backward(self : LineEditor) -> Bool {
  if self.cursor_pos == 0 {
    return false
  }
  let mut pos = self.cursor_pos - 1

  // Skip current word separators
  while pos > 0 {
    match self.buffer.get_char(pos) {
      Some(ch) => {
        if is_word_separator(ch) == false {
          break
        }
        pos = pos - 1
      }
      None => break
    }
  }

  // Skip word characters
  while pos > 0 {
    match self.buffer.get_char(pos) {
      Some(ch) => {
        if is_word_separator(ch) {
          pos = pos + 1
          break
        }
        pos = pos - 1
      }
      None => break
    }
  }

  // Handle the case where we reached the beginning
  match self.buffer.get_char(pos) {
    Some(ch) =>
      if pos == 0 && is_word_separator(ch) == false {
        // We're at the start of a word at position 0
        self.cursor_pos = 0
        return true
      }
    None => ()
  }
  if pos != self.cursor_pos {
    self.cursor_pos = pos
    true
  } else {
    false
  }
}

///|
/// Delete from cursor to the beginning of the previous word (Option+Delete)
fn LineEditor::delete_word_backward(self : LineEditor) -> Bool {
  if self.cursor_pos == 0 {
    return false
  }
  let start_pos = self.cursor_pos
  let mut pos = self.cursor_pos - 1

  // Skip current word separators
  while pos > 0 {
    match self.buffer.get_char(pos) {
      Some(ch) => {
        if is_word_separator(ch) == false {
          break
        }
        pos = pos - 1
      }
      None => break
    }
  }

  // Skip word characters
  while pos > 0 {
    match self.buffer.get_char(pos) {
      Some(ch) => {
        if is_word_separator(ch) {
          pos = pos + 1
          break
        }
        pos = pos - 1
      }
      None => break
    }
  }

  // Handle the case where we reached the beginning
  match self.buffer.get_char(pos) {
    Some(ch) => if pos == 0 && is_word_separator(ch) == false { pos = 0 }
    None => ()
  }
  if pos != start_pos {
    let before = self.buffer[0:pos].to_string() catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    let after = self.buffer[start_pos:].to_string() catch {
      IndexOutOfBounds(_) | InvalidIndex(_) => ""
    }
    self.buffer = before + after
    self.cursor_pos = pos
    true
  } else {
    false
  }
}

///|
/// Delete from cursor to the beginning of the line (Command+Delete)
fn LineEditor::delete_to_start(self : LineEditor) -> Bool {
  if self.cursor_pos == 0 {
    return false
  }
  let after = self.buffer[self.cursor_pos:].to_string() catch {
    IndexOutOfBounds(_) | InvalidIndex(_) => ""
  }
  self.buffer = after
  self.cursor_pos = 0
  true
}

///|
/// Redraw line
async fn redraw_line(editor : LineEditor, prompt : String) -> Unit {
  move_to_start()
  clear_to_end()
  @stdio.stdout.write(prompt + editor.buffer)

  // Calculate display width of characters after cursor
  let mut display_width_after = 0
  for i = editor.cursor_pos; i < editor.buffer.length(); i = i + 1 {
    match editor.buffer.get_char(i) {
      Some(ch) =>
        display_width_after = display_width_after + char_display_width(ch)
      None => ()
    }
  }
  if display_width_after > 0 {
    move_cursor_left(display_width_after)
  }
}

///|
/// Read escape sequence
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
      b'1' => {
        // Check for modified keys like ESC[1;3C (Option+Right)
        let n3 = @stdio.stdin.read(buf)
        if n3 == 0 {
          return None
        }
        if buf[0] == b';' {
          let n4 = @stdio.stdin.read(buf)
          if n4 == 0 {
            return None
          }
          let modifier = buf[0]
          let n5 = @stdio.stdin.read(buf)
          if n5 == 0 {
            return None
          }
          let key = buf[0]
          // modifier: 3 = Option, 9 = Command
          if modifier == b'3' {
            match key {
              b'C' => Some("option-right") // Option+Right
              b'D' => Some("option-left") // Option+Left
              b'~' => Some("option-delete") // Option+Delete (ESC[1;3~)
              _ => None
            }
          } else if modifier == b'9' {
            match key {
              b'C' => Some("cmd-right") // Command+Right
              b'D' => Some("cmd-left") // Command+Left
              b'~' => Some("cmd-delete") // Command+Delete (ESC[1;9~)
              _ => None
            }
          } else {
            None
          }
        } else {
          None
        }
      }
      b'3' => {
        let n3 = @stdio.stdin.read(buf)
        if n3 > 0 && buf[0] == b'~' {
          Some("delete")
        } else {
          None
        }
      }
      b'2' => {
        // Check for bracketed paste: ESC[200~ (start) or ESC[201~ (end)
        let n3 = @stdio.stdin.read(buf)
        if n3 == 0 {
          return None
        }
        if buf[0] == b'0' {
          let n4 = @stdio.stdin.read(buf)
          if n4 == 0 {
            return None
          }
          match buf[0] {
            b'0' => {
              // ESC[200~ - paste start
              let n5 = @stdio.stdin.read(buf)
              if n5 > 0 && buf[0] == b'~' {
                Some("paste-start")
              } else {
                None
              }
            }
            b'1' => {
              // ESC[201~ - paste end
              let n5 = @stdio.stdin.read(buf)
              if n5 > 0 && buf[0] == b'~' {
                Some("paste-end")
              } else {
                None
              }
            }
            _ => None
          }
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
  } else if buf[0] == b'b' {
    // Option+Left alternative sequence (ESC b)
    Some("option-left")
  } else if buf[0] == b'f' {
    // Option+Right alternative sequence (ESC f)
    Some("option-right")
  } else if buf[0] == b'd' {
    // Option+Delete alternative sequence (ESC d)
    // Some terminals send this for Option+Delete
    Some("option-delete")
  } else if buf[0] == backspace_byte {
    // Option+Backspace/Delete (ESC + 0x7F)
    // macOS Terminal often sends this for Option+Delete
    Some("option-delete")
  } else {
    None
  }
}

///|
/// Parse a byte into a KeyPress event
async fn parse_keypress() -> KeyPress? {
  let buf = FixedArray::make(1, b'\x00')
  let n = @stdio.stdin.read(buf)
  if n == 0 {
    return None
  }
  let byte = buf[0]

  // Handle special control characters
  match byte {
    b'\r' | b'\n' => Some(Enter)
    b'\x7f' => Some(Backspace)  // Backspace
    b'\x03' => Some(CtrlC)
    b'\x04' => Some(CtrlD)
    b'\x15' => Some(CtrlU)
    b'\x17' => Some(CtrlW)
    b'\x01' => Some(CtrlA)
    b'\x05' => Some(CtrlE)
    b'\x1b' => {
      // Escape sequence
      match read_escape_sequence() {
        Some("up") => Some(Up)
        Some("down") => Some(Down)
        Some("left") => Some(Left)
        Some("right") => Some(Right)
        Some("home") => Some(Home)
        Some("end") => Some(End)
        Some("delete") => Some(Delete)
        Some("option-left") => Some(OptionLeft)
        Some("option-right") => Some(OptionRight)
        Some("option-delete") => Some(OptionDelete)
        Some("cmd-left") => Some(CmdLeft)
        Some("cmd-right") => Some(CmdRight)
        Some("cmd-delete") => Some(CmdDelete)
        Some("paste-start") => Some(PasteStart)
        Some("paste-end") => Some(PasteEnd)
        _ => Some(Unknown)
      }
    }
    _ => {
      // UTF-8 character
      match read_utf8_char(byte) {
        Some(ch) => Some(Char(ch))
        None => Some(Unknown)
      }
    }
  }
}

///|
/// Read a UTF-8 character from stdin
async fn read_utf8_char(first_byte : Byte) -> Char? {
  // Single byte (ASCII)
  if first_byte < b'\x80' {
    return Some(Int::unsafe_to_char(first_byte.to_int()))
  }

  // Multi-byte UTF-8
  let buf = FixedArray::make(1, b'\x00')

  // 2-byte sequence (110xxxxx 10xxxxxx)
  if first_byte >= b'\xC0' && first_byte < b'\xE0' {
    let n = @stdio.stdin.read(buf)
    if n == 0 {
      return None
    }
    let code_point = ((first_byte.to_int() & 0x1F) << 6) |
      (buf[0].to_int() & 0x3F)
    return Some(Int::unsafe_to_char(code_point))
  }

  // 3-byte sequence (1110xxxx 10xxxxxx 10xxxxxx)
  if first_byte >= b'\xE0' && first_byte < b'\xF0' {
    let n1 = @stdio.stdin.read(buf)
    if n1 == 0 {
      return None
    }
    let byte2 = buf[0]
    let n2 = @stdio.stdin.read(buf)
    if n2 == 0 {
      return None
    }
    let byte3 = buf[0]
    let code_point = ((first_byte.to_int() & 0x0F) << 12) |
      ((byte2.to_int() & 0x3F) << 6) |
      (byte3.to_int() & 0x3F)
    return Some(Int::unsafe_to_char(code_point))
  }

  // 4-byte sequence (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
  if first_byte >= b'\xF0' && first_byte < b'\xF8' {
    let n1 = @stdio.stdin.read(buf)
    if n1 == 0 {
      return None
    }
    let byte2 = buf[0]
    let n2 = @stdio.stdin.read(buf)
    if n2 == 0 {
      return None
    }
    let byte3 = buf[0]
    let n3 = @stdio.stdin.read(buf)
    if n3 == 0 {
      return None
    }
    let byte4 = buf[0]
    let code_point = ((first_byte.to_int() & 0x07) << 18) |
      ((byte2.to_int() & 0x3F) << 12) |
      ((byte3.to_int() & 0x3F) << 6) |
      (byte4.to_int() & 0x3F)
    return Some(Int::unsafe_to_char(code_point))
  }
  None
}

///|
/// Handle a keypress event
async fn handle_keypress(
  key : KeyPress,
  editor : LineEditor,
  prompt : String,
  in_paste_mode : Bool,
  consecutive_inserts : Int
) -> (Bool, Int, Bool) {
  // Returns: (should_continue, new_consecutive_inserts, new_in_paste_mode)
  match key {
    Char(ch) => {
      editor.insert_char(ch)
      let new_consecutive = consecutive_inserts + 1

      // Render the character
      if in_paste_mode == false || new_consecutive % 5 == 0 {
        if editor.cursor_pos < editor.buffer.length() {
          redraw_line(editor, prompt)
        } else {
          @stdio.stdout.write(ch.to_string())
        }
      } else {
        @stdio.stdout.write(ch.to_string())
      }
      (true, new_consecutive, in_paste_mode)
    }
    Enter => {
      if in_paste_mode {
        editor.insert_char(' ')
        (true, consecutive_inserts + 1, in_paste_mode)
      } else {
        (false, 0, false)  // Exit the loop
      }
    }
    Backspace => {
      if editor.delete_char() {
        redraw_line(editor, prompt)
      }
      (true, 0, false)
    }
    Delete => {
      if editor.delete_forward() {
        redraw_line(editor, prompt)
      }
      (true, 0, false)
    }
    CtrlU | CmdDelete => {
      if editor.delete_to_start() {
        redraw_line(editor, prompt)
      }
      (true, 0, false)
    }
    CtrlW | OptionDelete => {
      if editor.delete_word_backward() {
        redraw_line(editor, prompt)
      }
      (true, 0, false)
    }
    CtrlA | CmdLeft => {
      if editor.move_to_start() {
        redraw_line(editor, prompt)
      }
      (true, 0, false)
    }
    CtrlE | CmdRight => {
      if editor.move_to_end() {
        redraw_line(editor, prompt)
      }
      (true, 0, false)
    }
    Up => {
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
      (true, 0, false)
    }
    Down => {
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
      (true, 0, false)
    }
    Left => {
      if editor.move_left() {
        match editor.buffer.get_char(editor.cursor_pos) {
          Some(ch) => {
            let width = char_display_width(ch)
            move_cursor_left(width)
          }
          None => move_cursor_left(1)
        }
      }
      (true, 0, false)
    }
    Right => {
      if editor.move_right() {
        match editor.buffer.get_char(editor.cursor_pos - 1) {
          Some(ch) => {
            let width = char_display_width(ch)
            move_cursor_right(width)
          }
          None => move_cursor_right(1)
        }
      }
      (true, 0, false)
    }
    Home => {
      if editor.move_to_start() {
        redraw_line(editor, prompt)
      }
      (true, 0, false)
    }
    End => {
      if editor.move_to_end() {
        redraw_line(editor, prompt)
      }
      (true, 0, false)
    }
    OptionLeft => {
      if editor.move_word_backward() {
        redraw_line(editor, prompt)
      }
      (true, 0, false)
    }
    OptionRight => {
      if editor.move_word_forward() {
        redraw_line(editor, prompt)
      }
      (true, 0, false)
    }
    CtrlC => {
      raise InterruptError("Operation interrupted by user (Ctrl+C)")
      (false, 0, false)  // Never reached
    }
    CtrlD => {
      if editor.buffer.is_empty() {
        (false, 0, false)  // Exit (will return None)
      } else if editor.delete_forward() {
        redraw_line(editor, prompt)
        (true, 0, false)
      } else {
        (true, 0, false)
      }
    }
    PasteStart => {
      // Enter paste mode
      (true, 0, true)
    }
    PasteEnd => {
      // Exit paste mode and redraw to ensure proper display
      redraw_line(editor, prompt)
      (true, 0, false)
    }
    Unknown => (true, 0, false)
  }
}

///|
/// Main readline function with raw mode enabled
async fn readline_simple(
  prompt : String,
  history : CommandHistory
) -> String? raise {
  let editor = LineEditor::new(history)

  // Enable raw mode for stdin
  set_raw_mode(@stdio.stdin.fd())

  // Enable bracketed paste mode
  @stdio.stdout.write("\u001b[?2004h")

  let mut in_paste_mode = false
  let mut consecutive_inserts = 0

  for {
    match parse_keypress() {
      Some(key) => {
        let (should_continue, new_consecutive, new_paste) = handle_keypress(
          key,
          editor,
          prompt,
          in_paste_mode,
          consecutive_inserts,
        )
        consecutive_inserts = new_consecutive
        in_paste_mode = new_paste

        if should_continue == false {
          match key {
            CtrlD => {
              if editor.buffer.is_empty() {
                // Disable bracketed paste mode before exit
                @stdio.stdout.write("\u001b[?2004l")
                return None
              }
            }
            _ => {
              // Normal exit (Enter key)
              let result = editor.buffer
              history.add(result)
              // Disable bracketed paste mode before exit
              @stdio.stdout.write("\u001b[?2004l")
              return Some(result)
            }
          }
        }
      }
      None => {
        // Disable bracketed paste mode before exit
        @stdio.stdout.write("\u001b[?2004l")
        return None
      }
    }
  }
  // Disable bracketed paste mode before exit
  @stdio.stdout.write("\u001b[?2004l")
  Some(editor.buffer)
}

