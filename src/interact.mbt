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

  // Check plan mode state
  match chat_history.plan_state {
    WaitingForApproval(task, _plan_text) => {
      // Process approval response
      let response = user_input.trim(chars=" \n\t\r").to_string().to_lower()
      match response {
        "yes" => {
          jarvis_says("Plan approved! Executing...")
          println_async("")
          chat_history.plan_state = Executing(task)
          execute_approved_plan(config, chat_history, task)
          chat_history.plan_state = Idle
        }
        "no" => {
          jarvis_says("Plan rejected. Exiting plan mode.")
          chat_history.plan_state = Idle
        }
        _ => {
          // User wants to modify or provided other input
          jarvis_says(
            "Plan modification requested. Please provide your changes:",
          )
          jarvis_says(
            "Plan mode ended. You can start a new plan with your modifications.",
          )
          chat_history.plan_state = Idle
        }
      }
      println_async("")
      return
    }
    Executing(_task) => {
      // Should not happen - execution is synchronous
      jarvis_cries("Unexpected state: already executing")
      chat_history.plan_state = Idle
      println_async("")
      return
    }
    Idle =>
      // Normal processing
      ()
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
