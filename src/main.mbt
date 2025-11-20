///|
/// Handle user input and generate response
async fn handle_user_input(
  user_input : String,
  chat_history : @session.ChatHistory,
  config : @types.Config,
) -> Unit {
  // Add user message to history
  let user_message = @types.Message::new("user", user_input)
  chat_history.add(user_message)

  // Manage history before sending request
  try {
    let summarized = chat_history.manage_history(config)
    if summarized {
      @output.jarvis_says(
        "(Summarized old conversation history to manage context length)",
      )

      // Create new file and print notifications (shared logic with manual summarize)
      chat_history.create_new_file_after_summary()
    }
  } catch {
    e =>
      // If history management fails, just log and continue
      @output.system_error("History management failed: \{e}")
  }

  // @types.Tool calling loop
  let tools = @tools.get_available_tools()
  @executor.handle_tool_calls(config, chat_history, tools)

  // Save conversation after each interaction
  chat_history.save_to_numbered_file()
}

///|
/// Check if input is an exit command
fn is_exit_command(input : String) -> Bool {
  input == "exit" || input == "quit" || input == "<EXIT>"
}

///|
async fn chat_loop(config : @types.Config) -> Unit {
  // Ensure .jarvis directory exists
  @session.ensure_jarvis_dir()

  // Try to load the latest conversation using numbered files
  let chat_history = match @session.load_latest_conversation() {
    Some(loaded_history) => {
      let num_str = @session.format_conv_number(loaded_history.current_file_number)
      @output.system_info("Loaded conversation from conv_\{num_str}.json")
      loaded_history
    }
    None => {
      // Create new conversation with initial system message
      let history = @session.ChatHistory::new()

      // Create the first conversation file
      let file_num = @session.create_new_conversation_file(
        history.messages,
        history.current_model,
        history.last_context_tokens,
      )
      history.current_file_number = file_num
      @output.system_info("Created new conversation: conv_001.json")
      history
    }
  }
  @output.jarvis_says(
    (
      #|Hello! I'm Jarvis, your AI assistant. How can I help you today?
      #|(Type 'exit' or 'quit' to end the conversation)
    ),
  )

  // Load user input history from file (at the beginning of chat_loop)
  let command_history = @session.load_user_input_history()

  // Main loop: Ctrl+C handling to interrupt operations
  for {
    try {
      @async.with_task_group(fn(group) {
        // Create a queue for readline input
        let input_queue : @aqueue.Queue[String] = @aqueue.Queue::new()

        // Start readline task in background
        group.spawn_bg(fn() {
          let rl = @readline.ReadlineInterface::with_history(100, command_history)
          while rl.read_to_queue(input_queue) {

          }
        })
        chat_history.print_token_usage()
        let user_input = input_queue.get()
        @output.newline_async()
        @output.print_separator()
        interact(chat_history, user_input, config, command_history)
        raise @types.ActionFinished
      })
      continue
    } catch {
      @types.ExitRequested => break
      @readline.InterruptByUser => {
        @output.system_error("Interrupted by user")
        continue
      }
      @types.ActionFinished => continue
      e => {
        @output.system_error("Fatal error: \{e}")
        break
      }
    }
  }
  @session.save_user_input_history(command_history)
}

///|
/// Execute a single prompt and exit (for -e flag)
async fn execute_prompt(config : @types.Config, prompt : String) -> Unit {
  @session.ensure_jarvis_dir()
  let chat_history = @session.ChatHistory::new()

  // Enable raw mode for Ctrl+C detection
  @readline.set_raw_mode(@stdio.stdin.fd())

  // Run with Ctrl+C handling
  @async.with_task_group(fn(group) {
    // Spawn background task to monitor Ctrl+C
    group.spawn_bg(@readline.start_interrupt_monitor)

    // Execute the prompt
    handle_user_input(prompt, chat_history, config)
    raise @types.ActionFinished
  }) catch {
    @readline.InterruptByUser => @output.system_error("Interrupted by user")
    @types.ActionFinished => ()
    e => @output.system_error("Fatal: \{e}")
  }
}

///|
/// Consult mode: Execute a single prompt with persistent conversation history
async fn consult_prompt(config : @types.Config, prompt : String) -> Unit {
  @session.ensure_jarvis_dir()

  // Load existing conversation or create new one (same as chat_loop)
  let chat_history = match @session.load_latest_conversation() {
    Some(loaded_history) => {
      let num_str = @session.format_conv_number(loaded_history.current_file_number)
      @output.system_info("Loaded conversation from conv_\{num_str}.json")
      loaded_history
    }
    None => {
      // Create new conversation
      let history = @session.ChatHistory::new()

      // Create the first conversation file
      let file_num = @session.create_new_conversation_file(
        history.messages,
        history.current_model,
        history.last_context_tokens,
      )
      history.current_file_number = file_num
      @output.system_info("Created new conversation: conv_001.json")
      history
    }
  }
  @output.system_info("Consulting: \{prompt}")
  @output.newline_async()

  // Enable raw mode for Ctrl+C detection
  @readline.set_raw_mode(@stdio.stdin.fd())

  // Run with Ctrl+C handling
  @async.with_task_group(fn(group) {
    // Spawn background task to monitor Ctrl+C
    group.spawn_bg(@readline.start_interrupt_monitor)

    // Execute the prompt
    handle_user_input(prompt, chat_history, config)
    raise @types.ActionFinished
  }) catch {
    @readline.InterruptByUser => @output.system_error("Interrupted by user")
    @types.ActionFinished => ()
    e => @output.system_error("Fatal: \{e}")
  }
}

///|
async fn main {
  // Initialize proxy configuration from environment variables
  @proxy.init_proxy_config()

  // Parse command line arguments using clap
  let parser = @clap.Parser::new(
    prog="jarvis",
    description="AI assistant powered by Claude",
    args={
      "execute": @clap.Arg::flag(
        short='e',
        help="Execute a single prompt and exit (no history)",
      ),
      "consult": @clap.Arg::flag(
        short='c',
        help="Consult mode: execute with persistent conversation history",
      ),
      "debug": @clap.Arg::flag(
        short='d',
        help="Enable debug mode (verbose logging)",
      ),
      "prompt": @clap.Arg::positional(
        nargs=@clap.Any,
        help="Prompt to execute (requires -e or -c flag)",
      ),
    },
  )
  let value = @clap.SimpleValue::new(parser.prog)
  let args = @sys.get_cli_args()
  // Remove program name from args
  let cli_args = if args.length() > 1 {
    let result : Array[String] = []
    for i = 1; i < args.length(); i = i + 1 {
      result.push(args[i])
    }
    result
  } else {
    []
  }

  // Parse arguments
  if parser.parse(value, cli_args) is Some(help_msg) {
    // Help message requested or parse error
    @output.println_async(help_msg)
    return
  }

  // Check modes
  let execute_mode = value.flags.get("execute").unwrap_or(false)
  let consult_mode = value.flags.get("consult").unwrap_or(false)

  // Set debug mode
  @types.debug_mode.val = value.flags.get("debug").unwrap_or(false)

  // Get prompt if provided
  let prompt = if (execute_mode || consult_mode) &&
    value.positional_args.length() > 0 {
    // Join all positional args as the prompt
    let builder = StringBuilder::new()
    let mut first = true
    for arg in value.positional_args {
      if !first {
        builder.write_string(" ")
      }
      builder.write_string(arg)
      first = false
    }
    Some(builder.to_string())
  } else {
    None
  }
  try {
    let config = @types.load_config()

    // Check which mode to use
    if execute_mode && consult_mode {
      @stdio.stderr.write("Error: Cannot use both -e and -c flags together\n")
      @stdio.stderr.write(
        "Usage: jarvis -e \"<prompt>\" OR jarvis -c \"<prompt>\"\n",
      )
    } else {
      match prompt {
        Some(p) =>
          if execute_mode {
            execute_prompt(config, p)
          } else if consult_mode {
            consult_prompt(config, p)
          } else {
            @stdio.stderr.write("Error: Prompt provided but no mode flag\n")
            @stdio.stderr.write(
              "Usage: jarvis -e \"<prompt>\" OR jarvis -c \"<prompt>\"\n",
            )
          }
        None =>
          if execute_mode {
            @stdio.stderr.write("Error: -e flag requires a prompt argument\n")
            @stdio.stderr.write("Usage: jarvis -e \"<prompt>\"\n")
          } else if consult_mode {
            @stdio.stderr.write("Error: -c flag requires a prompt argument\n")
            @stdio.stderr.write("Usage: jarvis -c \"<prompt>\"\n")
          } else {
            chat_loop(config)
          }
      }
    }
  } catch {
    @types.EnvVarNotSet(msg) =>
      @stdio.stderr.write("Error: Environment variable not set: \{msg}\n")
    @types.HttpError(msg) => @stdio.stderr.write("Error: HTTP error: \{msg}\n")
    @types.StringViewError(msg) =>
      @stdio.stderr.write("Error: String view error: \{msg}\n")
    e => @stdio.stderr.write("Error: Unknown error occurred: \{e}\n")
  }
}
