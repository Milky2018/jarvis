///| TTY module for terminal control
///| Simplified version without errno dependency

///|
extern "c" fn tty_set_raw_mode(fd : Int) -> Int = "moonbit_jarvis_tty_set_raw_mode"

///|
pub fn set_raw_mode(fd : Int) -> Unit {
  let result = tty_set_raw_mode(fd)
  if result != 0 {
    abort("Failed to set raw mode, error code: \{result}")
  }
}
