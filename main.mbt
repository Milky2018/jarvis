async fn handle_tool_calls(
  config : Config,
  chat_history : ChatHistory,
  tools : Array[Tool],
) -> Unit {
  let mut max_iterations = 10 // Prevent infinite loops
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
        print_jarvis_prefix()
        used_streaming = true
        let resp = send_streaming_chat_request(
          config,
          chat_history.messages,
          tools,
          chat_history.current_model,
        )
        println("") // Add newline after streaming
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
      match response.usage {
        Some(u) =>
          chat_history.usage_stats.add_request(
            u.input_tokens,
            u.output_tokens,
            u.input_tokens + u.output_tokens,
            chat_history.current_model,
          )
        None => ()
      }

      // Extract text content and tool uses from response
      let content_text = response.get_text_content()
      let tool_uses = response.get_tool_uses()

      // Display text content if present and not using streaming
      if tool_uses.length() == 0 {
        match content_text {
          Some(content_str) =>
            if used_streaming == false {
              print_jarvis_prefix()
              println(content_str)
            }
          None =>
            if used_streaming == false {
              print_jarvis_prefix()
              println("Error: No content in response")
            }
        }
        // No tool calls, add message to history and break
        let assistant_msg = {
          role: "assistant",
          content: content_text,
          tool_calls: None,
          tool_call_id: None,
          name: None,
        }
        chat_history.add(assistant_msg)
        break
      }

      // We have tool calls to execute
      // First, display any text content
      match content_text {
        Some(content_str) =>
          if content_str.is_empty() == false {
            print_jarvis_prefix()
            println(content_str)
          }
        None => ()
      }

      // Build assistant message with the full response for history
      // Note: We store the text content, Claude API requires full conversation history
      let assistant_msg = {
        role: "assistant",
        content: content_text,
        tool_calls: None,
        tool_call_id: None,
        name: None,
      }
      chat_history.add(assistant_msg)

      // Execute each tool and collect results
      let tool_results : Array[Json] = []
      for i = 0; i < tool_uses.length(); i = i + 1 {
        let (tool_id, tool_name, tool_input) = tool_uses[i]
        let result = execute_tool_claude(tool_name, tool_input)

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
      print_jarvis_prefix()
      println("Warning: Maximum tool calling iterations reached")
    }
  } catch {
    EnvVarNotSet(msg) => {
      print_jarvis_prefix()
      println("Error: Environment variable not set: \{msg}")
    }
    HttpError(msg) => {
      print_jarvis_prefix()
      println("Error: HTTP error: \{msg}")
    }
    JsonParseError(msg) => {
      print_jarvis_prefix()
      println("Error: JSON parse error: \{msg}")
    }
    StringViewError(msg) => {
      print_jarvis_prefix()
      println("Error: String view error: \{msg}")
    }
    _ => {
      print_jarvis_prefix()
      println("Error: Unknown error occurred")
    }
  }
}

///|
/// Handle user input and generate response
async fn handle_user_input(
  config : Config,
  chat_history : ChatHistory,
  user_input : String,
) -> Unit {
  // Search for relevant memories before processing
  let relevant_memories = search_relevant_memories(
    user_input,
    config,
    chat_history.current_model,
  )

  // If we found relevant memories, inject them as a system message
  if relevant_memories.is_empty() == false {
    print_jarvis_prefix()
    println("(Found relevant memories from past conversations)")
    let memory_message = Message::new(
      "system",
      "以下是与当前话题相关的历史记忆：" + relevant_memories,
    )
    chat_history.add(memory_message)
  }

  // Add user message to history
  let user_message = Message::new("user", user_input)
  chat_history.add(user_message)

  // Manage history before sending request
  try {
    let summarized = chat_history.manage_history(config)
    if summarized {
      print_jarvis_prefix()
      println("(Summarized old conversation history to manage context length)")
    }
  } catch {
    e => {
      // If history management fails, just log and continue
      print_jarvis_prefix()
      println("Warning: History management failed: \{e}")
    }
  }

  // Tool calling loop
  let tools = get_available_tools()
  handle_tool_calls(config, chat_history, tools)
}

///|
/// Check if input is an exit command
fn is_exit_command(input : String) -> Bool {
  input == "exit" ||
  input == "quit" ||
  input.has_prefix(":exit") ||
  input.has_prefix(":quit") ||
  input.has_prefix(":q")
}

///|
async fn chat_loop(config : Config) -> Unit {
  // Ensure .jarvis directory exists
  ensure_jarvis_dir()

  // Try to load the latest unsummarized conversation
  let chat_history = match find_latest_unsummarized_conversation() {
    Some(conversation_name) => {
      let path = get_conversation_path(conversation_name)
      match ChatHistory::load(path) {
        Some(loaded) => {
          print_jarvis_prefix()
          println("Continuing from previous conversation: \{conversation_name}")
          loaded
        }
        None => {
          print_jarvis_prefix()
          println("Failed to load previous conversation, starting new one")
          ChatHistory::new()
        }
      }
    }
    None => ChatHistory::new()
  }
  let command_history = CommandHistory::new(100)
  println("")
  print_jarvis_prefix()
  println("Hello! I'm Jarvis, your AI assistant. How can I help you today?")
  println("(Type 'exit' or 'quit' to end the conversation)")
  println("")
  let mut should_save = false
  while true {
    print_separator()
    match readline_simple("> ", command_history) {
      Some(user_input) => {
        print_separator()
        if user_input.is_empty() {
          continue
        }

        // Check for exit commands first
        if is_exit_command(user_input) {
          should_save = true
          print_jarvis_prefix()
          println("Goodbye!")
          break
        }

        // Handle special commands
        if handle_command(user_input, chat_history, config) {
          println("")
          continue
        }

        // Handle normal user input
        should_save = true
        handle_user_input(config, chat_history, user_input)
        println("")
      }
      None => {
        should_save = true
        println("")
        print_jarvis_prefix()
        println("Goodbye!")
        break
      }
    }
  }

  // Save conversation on exit if there were messages (without summary)
  if should_save && chat_history.messages.length() > 0 {
    // Generate timestamp-based filename
    let (exit_code, output) = @process.collect_output_merged("sh", [
      "-c", "date +%Y%m%d_%H%M%S",
    ])
    let timestamp = if exit_code == 0 {
      output.text()[:].trim(chars=" \n\t\r").to_string()
    } else {
      "conversation"
    }
    let filename = get_conversation_path(timestamp)
    chat_history.save(filename)
    print_jarvis_prefix()
    println("Conversation saved (use :summarize to generate summary)")
  }
}

///|
/// Execute a single prompt and exit (for -e flag)
async fn execute_prompt(config : Config, prompt : String) -> Unit {
  ensure_jarvis_dir()
  let chat_history = ChatHistory::new()

  print_jarvis_prefix()
  println("Processing: \{prompt}")
  println("")

  handle_user_input(config, chat_history, prompt)
}

///|
async fn main {
  // Parse command line arguments
  let args = @sys.get_cli_args()

  // Simple argument parsing: check for -e flag
  let execute_mode = args.length() >= 2 && (args[1] == "-e" || args[1] == "--execute")
  let prompt = if execute_mode && args.length() >= 3 {
    Some(args[2])
  } else {
    None
  }

  try {
    let config = load_config()

    // Check if -e flag is used
    match prompt {
      Some(p) => execute_prompt(config, p)
      None => {
        if execute_mode {
          @stdio.stderr.write("Error: -e flag requires a prompt argument\n")
          @stdio.stderr.write("Usage: jarvis -e \"<prompt>\"\n")
        } else {
          chat_loop(config)
        }
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
    _ => @stdio.stderr.write("Error: Unknown error occurred\n")
  }
}
