///| Interrupt handling module
///
/// This module provides signal handling for interrupting Jarvis operations.
/// It uses C FFI to handle SIGINT (Ctrl+C) signals.

///|
/// Initialize signal handling (call once at startup)
extern "c" fn signal_init() -> Unit = "jarvis_signal_init"

///|
/// Check if interrupt was requested (Ctrl+C pressed)
extern "c" fn check_interrupt() -> Bool = "jarvis_signal_check_interrupt"

///|
/// Clear the interrupt flag
extern "c" fn clear_interrupt() -> Unit = "jarvis_signal_clear_interrupt"

///|
/// Check for interrupt and raise error if interrupted
pub async fn check_and_raise() -> Unit raise JarvisError {
  if check_interrupt() {
    clear_interrupt()
    raise InterruptError("Operation interrupted by user (Ctrl+C)")
  }
}

///|
/// Initialize interrupt handling (should be called at program start)
pub fn setup_interrupt_handler() -> Unit {
  signal_init()
}
