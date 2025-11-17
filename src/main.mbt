///|
suberror JarvisSignal {
  InterruptByUser
  ActionFinished
  PlayModeEnded
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
  try {
    while max_iterations > 0 {
      max_iterations = max_iterations - 1

      // Send request (use streaming for first request)
      let response = if first_request && tools.length() > 0 {
        // First request with tools: use non-streaming to check for tool calls
        send_chat_request_with_tools(
          config,
          chat_history.messages,
          tools,
          chat_history.current_model,
        )
      } else if first_request {
        // First request without tools: use streaming
        used_streaming = true
        let resp = send_streaming_chat_request(
          config,
          chat_history.messages,
          tools,
          chat_history.current_model,
        )
        println_async("") // Add newline after streaming
        resp
      } else {
        // Subsequent requests: non-streaming
        send_chat_request_with_tools(
          config,
          chat_history.messages,
          tools,
          chat_history.current_model,
        )
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
            let ends_with_colon = trimmed.has_suffix(":") || trimmed.has_suffix("：")

            if ends_with_colon {
              // Message added to history
              let assistant_msg = {
                role: "assistant",
                content: Some(content_str),
                tool_calls: None,
                tool_call_id: None,
                name: None,
              }
              chat_history.add(assistant_msg)

              // Prompt Claude to actually call the tool instead of just describing
              let continuation_prompt = Message::new(
                "user",
                "Please proceed with the actual tool call now. Do not describe what you will do - execute the tool.",
              )
              chat_history.add(continuation_prompt)

              // Continue the loop to get the actual tool call
              continue
            }
          }
          None =>
            if !used_streaming {
              jarvis_cries("Error: No content in response")
              return false // Signal error to caller
            }
        }
        // No tool calls, add message to history and break
        // Ensure content is not None to avoid API errors
        let assistant_msg = {
          role: "assistant",
          content: match content_text {
            Some(c) => Some(c)
            None => Some("") // Use empty string instead of None
          },
          tool_calls: None,
          tool_call_id: None,
          name: None,
        }
        chat_history.add(assistant_msg)
        break
      }

      // We have tool calls to execute
      // First, display any text content
      if content_text is Some(content_str) && !content_str.is_blank() {
        jarvis_says(content_str)
      }

      // Build assistant message with the full response for history
      // IMPORTANT: Only add message if there's actual content
      // Claude API requires content field to be non-null
      if content_text is Some(content) {
        if !content.is_empty() {
          let assistant_msg = {
            role: "assistant",
            content: Some(content),
            tool_calls: None,
            tool_call_id: None,
            name: None,
          }
          chat_history.add(assistant_msg)
        }
      }

      // Execute each tool and collect results
      let tool_results : Array[Json] = []
      for i = 0; i < tool_uses.length(); i = i + 1 {
        let (tool_id, tool_name, tool_input) = tool_uses[i]
        let result = execute_tool_claude(tool_name, tool_input, chat_history)

        // Create tool_result content block
        let tool_result : Json = {
          "type": "tool_result",
          "tool_use_id": tool_id,
          "content": result,
        }
        tool_results.push(tool_result)
      }

      // Send tool results back as a user message
      // Claude API expects tool results as plain string for now
      // Ideally should be content blocks, but Message structure needs updating
      let mut results_text = ""
      for i = 0; i < tool_uses.length(); i = i + 1 {
        let (tool_id, tool_name, _) = tool_uses[i]
        let result_json = tool_results[i]
        // Extract the content from tool_result
        match result_json {
          Object(map) =>
            match map.get("content") {
              Some(String(content)) => {
                if i > 0 {
                  results_text = results_text + "\n\n"
                }
                results_text = results_text +
                  "Tool: \{tool_name} (ID: \{tool_id})\nResult: \{content}"
              }
              _ => ()
            }
          _ => ()
        }
      }
      let user_msg_with_results = {
        role: "user",
        content: Some(results_text),
        tool_calls: None,
        tool_call_id: None,
        name: None,
      }
      chat_history.add(user_msg_with_results)

      // Continue loop to get final response after tool execution
    }
    if max_iterations == 0 {
      jarvis_cries("Maximum tool calling iterations reached")
      return false
    }
    true // Success
  } catch {
    EnvVarNotSet(msg) => {
      jarvis_cries("Error: Environment variable not set: \{msg}")
      false
    }
    HttpError(msg) => {
      jarvis_cries("Error: HTTP error: \{msg}")
      false
    }
    JsonParseError(msg) => {
      jarvis_cries("Error: JSON parse error: \{msg}")
      false
    }
    StringViewError(msg) => {
      jarvis_cries("Error: String view error: \{msg}")
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
      jarvis_cries("History management failed: \{e}")
  }

  // Tool calling loop
  let tools = get_available_tools()
  ignore(handle_tool_calls(config, chat_history, tools))

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
      system_notify("Loaded conversation from conv_\{num_str}.json")
      loaded_history
    }
    None => {
      // Create new conversation with initial system message
      let initial_msg = Message::new("system", SYSTEM_PROMPT)
      let history = ChatHistory::new()
      history.add(initial_msg)

      // Create the first conversation file
      let file_num = create_new_conversation_file(
        history.messages,
        history.current_model,
      )
      history.current_file_number = file_num
      system_notify("Created new conversation: conv_001.json")
      history
    }
  }
  println_async("")
  jarvis_says("Hello! I'm Jarvis, your AI assistant. How can I help you today?")
  println_async("(Type 'exit' or 'quit' to end the conversation)")
  println_async("")

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
              match msg.content {
                Some(content) =>
                  // Skip tool result messages
                  if !content.has_prefix("Tool:") {
                    user_inputs.push(content)
                  }
                None => ()
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
        println_async("")
        continue
      }
      ActionFinished => continue
      e => {
        println_async("")
        jarvis_says("Fatal error: \{e}")
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
  system_notify("Processing: \{prompt}")
  println_async("")
  handle_user_input(prompt, chat_history, config)
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
        help="Execute a single prompt and exit",
      ),
      "prompt": @clap.Arg::positional(
        nargs=@clap.Any,
        help="Prompt to execute (requires -e flag)",
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

  // Check if execute mode
  let execute_mode = value.flags.get("execute").unwrap_or(false)
  let prompt = if execute_mode && value.positional_args.length() > 0 {
    // Join all positional args as the prompt
    let mut p = ""
    for i = 0; i < value.positional_args.length(); i = i + 1 {
      if i > 0 {
        p = p + " "
      }
      p = p + value.positional_args[i]
    }
    Some(p)
  } else {
    None
  }
  try {
    let config = load_config()

    // Check if -e flag is used
    match prompt {
      Some(p) => execute_prompt(config, p)
      None =>
        if execute_mode {
          @stdio.stderr.write("Error: -e flag requires a prompt argument\n")
          @stdio.stderr.write("Usage: jarvis -e \"<prompt>\"\n")
        } else {
          chat_loop(config)
        }
    }
  } catch {
    EnvVarNotSet(msg) =>
      @stdio.stderr.write("Error: Environment variable not set: \{msg}\n")
    HttpError(msg) => @stdio.stderr.write("Error: HTTP error: \{msg}\n")
    JsonParseError(msg) =>
      @stdio.stderr.write("Error: JSON parse error: \{msg}\n")
    StringViewError(msg) =>
      @stdio.stderr.write("Error: String view error: \{msg}\n")
    e => @stdio.stderr.write("Error: Unknown error occurred: \{e}\n")
  }
}
