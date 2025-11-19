///|
suberror JarvisSignal {
  InterruptByUser
  ActionFinished
  PlayModeEnded
}

///|
/// Send chat request (streaming or non-streaming based on context)
async fn send_chat_request(
  config : Config,
  chat_history : ChatHistory,
  tools : Array[Tool],
  first_request : Bool,
) -> (ChatResponse, Bool) {
  // Always use streaming mode
  ignore(first_request)
  let resp = send_streaming_chat_request(
    config,
    chat_history.messages,
    tools,
    chat_history.current_model,
  )
  newline_async() // Add newline after streaming
  (resp, true)
}

///|
/// Execute tools and collect results
async fn execute_tools_and_collect_results(
  tool_uses : Array[(String, String, Json)],
  chat_history : ChatHistory,
) -> (Array[Json], Bool) {
  let tool_results : Array[Json] = []
  let mut elaborate_complete = false
  for tool_use in tool_uses {
    let (tool_id, tool_name, tool_input) = tool_use
    let result = execute_tool_claude(tool_name, tool_input, chat_history)

    // Check if end_elaborate was called
    if result.has_prefix("ELABORATE_COMPLETE:") {
      elaborate_complete = true
    }

    // Create tool_result content block
    let tool_result : Json = {
      "type": "tool_result",
      "tool_use_id": tool_id,
      "content": result,
    }
    tool_results.push(tool_result)
  }
  (tool_results, elaborate_complete)
}

///|
/// Format tool results as text message
fn format_tool_results_as_text(
  tool_uses : Array[(String, String, Json)],
  tool_results : Array[Json],
) -> String {
  let builder = StringBuilder::new()
  let mut first = true
  for i = 0; i < tool_uses.length(); i = i + 1 {
    let (tool_id, tool_name, _) = tool_uses[i]
    let result_json = tool_results[i]
    // Extract the content from tool_result
    match result_json {
      Object(map) =>
        match map.get("content") {
          Some(String(content)) => {
            if !first {
              builder.write_string("\n\n")
            }
            builder.write_string("Tool: ")
            builder.write_string(tool_name)
            builder.write_string(" (ID: ")
            builder.write_string(tool_id)
            builder.write_string(")\nResult: ")
            builder.write_string(content)
            first = false
          }
          _ => ()
        }
      _ => ()
    }
  }
  builder.to_string()
}

///|
async fn handle_tool_calls(
  config : Config,
  chat_history : ChatHistory,
  tools : Array[Tool],
) -> Bool {
  let mut max_iterations = MAX_TOOL_ITERATIONS // Prevent infinite loops
  let mut first_request = true // Use streaming for first request only
  let mut used_streaming = false // Track if we used streaming
  let mut has_called_tools = false // Track if any tools have been called
  try {
    while max_iterations > 0 {
      max_iterations = max_iterations - 1

      // Send request (use streaming for first request)
      let (response, was_streaming) = send_chat_request(
        config, chat_history, tools, first_request,
      )
      if was_streaming {
        used_streaming = true
      }
      first_request = false

      // Record usage statistics
      if response.usage is Some(u) {
        chat_history.usage_stats.add_request(
          u.input_tokens,
          u.output_tokens,
          u.input_tokens + u.output_tokens,
          chat_history.current_model,
        )
      }

      // Extract text content and tool uses from response
      let content_text = response.get_text_content()
      let tool_uses = response.get_tool_uses()

      // Display text content if present and not using streaming
      if tool_uses.length() == 0 {
        match content_text {
          Some(content_str) => {
            if !used_streaming {
              jarvis_says(content_str)
            }

            // Check if message ends with a colon (: or ：)
            // This often indicates Claude is about to describe an action but hasn't taken it
            let trimmed = content_str.trim(chars=" \t\n\r").to_string()
            let ends_with_colon = trimmed.has_suffix(":") ||
              trimmed.has_suffix("：")
            if ends_with_colon {
              // Message added to history
              let assistant_msg = Message::new("assistant", content_str)
              chat_history.add(assistant_msg)

              // Prompt Claude to actually call the tool instead of just describing
              let continuation_prompt = Message::new(
                "user", "Please proceed with the actual tool call now. Do not describe what you will do - execute the tool.",
              )
              chat_history.add(continuation_prompt)

              // Continue the loop to get the actual tool call
              continue
            }
          }
          None =>
            if !used_streaming {
              system_error("No content in response")
              return false // Signal error to caller
            }
        }
        // No tool calls, add message to history
        // Ensure content is not None to avoid API errors
        let content_str = match content_text {
          Some(c) => c
          None => ""
        }
        let assistant_msg = Message::new("assistant", content_str)
        chat_history.add(assistant_msg)

        // Auto-continue: only if we've already called tools (i.e., we're in "work mode")
        // This prevents simple conversational responses from looping forever
        if has_called_tools {
          // system_notify("Working on your request...")
          let continue_msg = Message::new(
            "user", "Continue with your task. If you have completed everything, call the end_elaborate tool.",
          )
          chat_history.add(continue_msg)
          // Continue the loop instead of breaking
          continue
        } else {
          // First response with no tool calls - just return control to user
          return true
        }
      }

      // We have tool calls to execute
      has_called_tools = true // Mark that we've entered work mode
      // First, display any text content
      if content_text is Some(content_str) && !content_str.is_blank() {
        jarvis_says(content_str)
      }

      // Build assistant message with the full response for history
      // IMPORTANT: Only add message if there's actual content
      // Claude API requires content field to be non-null
      if content_text is Some(content) {
        if !content.is_empty() {
          let assistant_msg = Message::new("assistant", content)
          chat_history.add(assistant_msg)
        }
      }

      // Execute each tool and collect results
      let (tool_results, elaborate_complete) = execute_tools_and_collect_results(
        tool_uses, chat_history,
      )

      // If elaborate is complete, end the loop
      if elaborate_complete {
        return true
      }

      // Send tool results back as a user message
      let results_text = format_tool_results_as_text(tool_uses, tool_results)
      let user_msg_with_results = Message::new("user", results_text)
      chat_history.add(user_msg_with_results)

      // Continue loop to get final response after tool execution
    }
    if max_iterations == 0 {
      system_error("Maximum tool calling iterations reached")
      return false
    }
    true // Success
  } catch {
    EnvVarNotSet(msg) => {
      system_error("Environment variable not set: \{msg}")
      false
    }
    HttpError(msg) => {
      system_error("HTTP error: \{msg}")
      false
    }
    StringViewError(msg) => {
      system_error("String view error: \{msg}")
      false
    }
    e => raise e
  }
}

///|
/// Handle user input and generate response
async fn handle_user_input(
  user_input : String,
  chat_history : ChatHistory,
  config : Config,
) -> Unit {
  // Add user message to history
  let user_message = Message::new("user", user_input)
  chat_history.add(user_message)

  // Manage history before sending request
  try {
    let summarized = chat_history.manage_history(config)
    if summarized {
      jarvis_says(
        "(Summarized old conversation history to manage context length)",
      )

      // Create new file and print notifications (shared logic with manual summarize)
      chat_history.create_new_file_after_summary()
    }
  } catch {
    e =>
      // If history management fails, just log and continue
      system_error("History management failed: \{e}")
  }

  // Tool calling loop
  let tools = get_available_tools()
  let success = handle_tool_calls(config, chat_history, tools)

  // If elaborate completed successfully, show completion message
  if success {
    jarvis_says("Task completed. Feel free to ask me anything else!")
  }

  // Save conversation after each interaction
  chat_history.save_to_numbered_file()
}

///|
/// Check if input is an exit command
fn is_exit_command(input : String) -> Bool {
  input == "exit" || input == "quit" || input == "<EXIT>"
}

///|
async fn chat_loop(config : Config) -> Unit {
  // Ensure .jarvis directory exists
  ensure_jarvis_dir()

  // Try to load the latest conversation using numbered files
  let chat_history = match load_latest_conversation() {
    Some((loaded_history, file_num)) => {
      loaded_history.current_file_number = file_num
      let num_str = format_conv_number(file_num)
      system_info("Loaded conversation from conv_\{num_str}.json")
      loaded_history
    }
    None => {
      // Create new conversation with initial system message
      let history = ChatHistory::new()

      // Create the first conversation file
      let file_num = create_new_conversation_file(
        history.messages,
        history.current_model,
      )
      history.current_file_number = file_num
      system_info("Created new conversation: conv_001.json")
      history
    }
  }
  newline_async()
  jarvis_says("Hello! I'm Jarvis, your AI assistant. How can I help you today?")
  println_async("(Type 'exit' or 'quit' to end the conversation)")
  newline_async()

  // Main loop: Ctrl+C handling to interrupt operations
  for {
    try {
      @async.with_task_group(fn(group) {
        // Create a queue for readline input
        let input_queue : @aqueue.Queue[String] = @aqueue.Queue::new()

        // Start readline task in background
        group.spawn_bg(fn() {
          // Extract user messages from chat history for readline history
          // Filter out tool result messages (they start with "Tool:")
          let user_inputs : Array[String] = []
          for msg in chat_history.messages {
            if msg.role == "user" {
              let content = msg.get_text()
              // Skip tool result messages
              if !content.is_empty() && !content.has_prefix("Tool:") {
                user_inputs.push(content)
              }
            }
          }
          let rl = ReadlineInterface::with_history(100, user_inputs)
          while rl.read_to_queue(input_queue) {

          }
        })
        interact(chat_history, input_queue, config)
        raise ActionFinished
      })
      continue
    } catch {
      ExitRequested => break
      InterruptByUser => {
        jarvis_says("Interrupted by user")
        newline_async()
        continue
      }
      ActionFinished => continue
      e => {
        newline_async()
        system_error("Fatal error: \{e}")
        break
      }
    }
  }
}

///|
/// Execute a single prompt and exit (for -e flag)
async fn execute_prompt(config : Config, prompt : String) -> Unit {
  ensure_jarvis_dir()
  let chat_history = ChatHistory::new()

  // Enable raw mode for Ctrl+C detection
  set_raw_mode(@stdio.stdin.fd())

  // Run with Ctrl+C handling
  @async.with_task_group(fn(group) {
    // Spawn background task to monitor Ctrl+C
    group.spawn_bg(fn() {
      for {
        let keypress = parse_keypress()
        if keypress is Some(CtrlC) {
          raise InterruptByUser
        }
      }
    })

    // Execute the prompt
    handle_user_input(prompt, chat_history, config)
    raise ActionFinished
  }) catch {
    InterruptByUser => {
      jarvis_says("Interrupted by user")
      newline_async()
    }
    ActionFinished => ()
    e => {
      jarvis_says("Error: \{e}")
      newline_async()
    }
  }
}

///|
/// Consult mode: Execute a single prompt with persistent conversation history
async fn consult_prompt(config : Config, prompt : String) -> Unit {
  ensure_jarvis_dir()

  // Load existing conversation or create new one (same as chat_loop)
  let chat_history = match load_latest_conversation() {
    Some((loaded_history, file_num)) => {
      loaded_history.current_file_number = file_num
      let num_str = format_conv_number(file_num)
      system_info("Loaded conversation from conv_\{num_str}.json")
      loaded_history
    }
    None => {
      // Create new conversation
      let history = ChatHistory::new()

      // Create the first conversation file
      let file_num = create_new_conversation_file(
        history.messages,
        history.current_model,
      )
      history.current_file_number = file_num
      system_info("Created new conversation: conv_001.json")
      history
    }
  }
  system_info("Consulting: \{prompt}")
  newline_async()

  // Enable raw mode for Ctrl+C detection
  set_raw_mode(@stdio.stdin.fd())

  // Run with Ctrl+C handling
  @async.with_task_group(fn(group) {
    // Spawn background task to monitor Ctrl+C
    group.spawn_bg(fn() {
      for {
        let keypress = parse_keypress()
        if keypress is Some(CtrlC) {
          raise InterruptByUser
        }
      }
    })

    // Execute the prompt
    handle_user_input(prompt, chat_history, config)
    raise ActionFinished
  }) catch {
    InterruptByUser => {
      jarvis_says("Interrupted by user")
      newline_async()
    }
    ActionFinished => ()
    e => {
      jarvis_says("Error: \{e}")
      newline_async()
    }
  }
}

///|
async fn main {
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
    println_async(help_msg)
    return
  }

  // Check modes
  let execute_mode = value.flags.get("execute").unwrap_or(false)
  let consult_mode = value.flags.get("consult").unwrap_or(false)

  // Set debug mode
  debug_mode.val = value.flags.get("debug").unwrap_or(false)

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
    let config = load_config()

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
    EnvVarNotSet(msg) =>
      @stdio.stderr.write("Error: Environment variable not set: \{msg}\n")
    HttpError(msg) => @stdio.stderr.write("Error: HTTP error: \{msg}\n")
    StringViewError(msg) =>
      @stdio.stderr.write("Error: String view error: \{msg}\n")
    e => @stdio.stderr.write("Error: Unknown error occurred: \{e}\n")
  }
}
