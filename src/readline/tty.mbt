///| TTY module for terminal control

///| Simplified version without errno dependency

///|
extern "c" fn tty_set_raw_mode(fd : Int) -> Int = "moonbit_jarvis_tty_set_raw_mode"

///|
#borrow(size)
extern "c" fn tty_get_win_size(size : FixedArray[Int]) -> Int = "moonbit_jarvis_tty_get_win_size"

///|
pub fn set_raw_mode(fd : Int) -> Unit {
  let result = tty_set_raw_mode(fd)
  if result != 0 {
    abort("Failed to set raw mode, error code: \{result}")
  }
}

///|
/// Terminal window size
pub struct Size {
  row : Int
  col : Int
}

///|
pub fn window_size() -> Size {
  let buf : FixedArray[Int] = [0, 0]
  let result = tty_get_win_size(buf)
  if result != 0 {
    // Return default size if failed
    { row: 24, col: 80 }
  } else {
    { row: buf[0], col: buf[1] }
  }
}
