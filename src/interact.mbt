///|
async fn interact(
  chat_history : ChatHistory,
  input_queue : @async.Queue[String],
  config : Config,
) -> Unit {
  // Show token usage before prompt
  chat_history.print_token_usage()

  // Wait for input from readline task
  let user_input = input_queue.get()

  println_async("") // Print newline after user input
  print_separator()

  // Check for exit commands
  if is_exit_command(user_input) {
    jarvis_says("Goodbye!")
    raise ExitRequested
  }

  // Handle special commands
  if handle_command(user_input, chat_history, config) {
    println_async("")
    return 
  }

  // Handle normal user input
  handle_user_input(user_input, chat_history, config)
  println_async("")
}
