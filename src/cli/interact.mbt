///|
async fn interact(
  chat_history : @session.ChatHistory,
  user_input : String,
  config : @types.Config,
  command_history : Array[String],
) -> Unit {
  // Check for exit commands
  if is_exit_command(user_input) {
    @output.jarvis_says("Goodbye!")
    raise @types.ExitRequested
  }

  // Handle special commands
  if @commands.handle_command(user_input, chat_history, config) {
    return
  }

  // Add user input to in-memory command history
  command_history.push(user_input)

  // Handle normal user input
  handle_user_input(user_input, chat_history, config)
}
