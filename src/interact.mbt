///|
async fn interact(
  chat_history : ChatHistory,
  user_input : String,
  config : Config,
  command_history : Array[String],
) -> Unit {
  // Check for exit commands
  if is_exit_command(user_input) {
    jarvis_says("Goodbye!")
    raise ExitRequested
  }

  // Handle special commands
  if handle_command(user_input, chat_history, config) {
    return
  }

  // Add user input to in-memory command history
  command_history.push(user_input)

  // Handle normal user input
  handle_user_input(user_input, chat_history, config)
}
