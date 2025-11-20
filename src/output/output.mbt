///|
/// Print colored Jarvis prefix
pub async fn print_jarvis_prefix() -> Unit {
  @stdio.stdout.write(@types.COLOR_BOLD)
  @stdio.stdout.write(@types.COLOR_CYAN)
  @stdio.stdout.write("Jarvis")
  @stdio.stdout.write(@types.COLOR_RESET)
  @stdio.stdout.write(": ")
}

///|
/// Jarvis speaks - unified function for all Jarvis output
pub async fn jarvis_says(message : String) -> Unit {
  print_jarvis_prefix()
  println_async(message)
  newline_async()
}

///|
/// System error - shows system-level error message (red)
pub async fn system_error(message : String) -> Unit {
  newline_async()
  @stdio.stdout.write(@types.COLOR_RED)
  @stdio.stdout.write("[ERROR] ")
  @stdio.stdout.write(@types.COLOR_RESET)
  println_async(message)
}

///|
/// Tool execution log - shows which tool is being executed (green)
pub async fn tool_log(tool_name : String, content : String) -> Unit {
  @stdio.stdout.write(@types.COLOR_GREEN)
  @stdio.stdout.write("[Tool] ")
  @stdio.stdout.write(@types.COLOR_RESET)
  @stdio.stdout.write(@types.COLOR_BOLD)
  @stdio.stdout.write(tool_name)
  @stdio.stdout.write(@types.COLOR_RESET)
  @stdio.stdout.write("(")
  @stdio.stdout.write(content)
  @stdio.stdout.write(")")
  @stdio.stdout.write("\n\n")
}

///|
/// System info - shows system-level information (white)
pub async fn system_info(message : String) -> Unit {
  @stdio.stdout.write("[INFO] ")
  println_async(message)
}

///|
/// Print debug message (only when debug_mode is enabled, gray)
pub async fn system_debug(message : String) -> Unit {
  if @types.debug_mode.val {
    @stdio.stdout.write(@types.COLOR_GRAY)
    @stdio.stdout.write("[DEBUG] ")
    @stdio.stdout.write(@types.COLOR_RESET)
    println_async(message)
  }
}

///|
pub async fn println_async(s : String) -> Unit {
  @stdio.stdout.write("\{s}\n")
}

///|
/// Print a newline
pub async fn newline_async() -> Unit {
  @stdio.stdout.write("\n")
}

///|
/// Print horizontal separator line
pub async fn print_separator() -> Unit {
  let size = @readline.window_size()
  ignore(size.row)
  let builder = StringBuilder::new()
  for i = 0; i < size.col; i = i + 1 {
    builder.write_string("─")
  }
  @stdio.stdout.write(@types.COLOR_GRAY)
  println_async(builder.to_string())
  @stdio.stdout.write(@types.COLOR_RESET)
}
