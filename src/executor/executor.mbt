///|
/// Send chat request (streaming for text output, but always with tools)
pub async fn send_chat_request(
  config : @types.Config,
  chat_history : @session.ChatHistory,
  tools : Array[@types.Tool],
) -> (@types.ChatResponse, Bool) {
  // Use streaming for real-time output, with tools available
  // This allows both tool calls and text output
  let resp = @api.send_streaming_chat_request(
    config,
    chat_history.messages,
    tools,
    chat_history.current_model,
  )
  @output.newline_async() // Add newline after streaming
  (resp, true)
}

///|
/// Execute tools and collect results
pub async fn execute_tools_and_collect_results(
  tool_uses : Array[(String, String, Json)],
  chat_history : @session.ChatHistory,
) -> (Array[Json], Bool) {
  let tool_results : Array[Json] = []
  let mut elaborate_complete = false
  for tool_use in tool_uses {
    let (tool_id, tool_name, tool_input) = tool_use
    let result = @tools.execute_tool_claude(tool_name, tool_input, chat_history)

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
pub fn format_tool_results_as_text(
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
/// Handle tool calling loop
pub async fn handle_tool_calls(
  config : @types.Config,
  chat_history : @session.ChatHistory,
  tools : Array[@types.Tool],
) -> Unit {
  let mut max_iterations = @types.MAX_TOOL_ITERATIONS // Prevent infinite loops
  let mut used_streaming = false // Track if we used streaming
  let mut has_called_tools = false // Track if any tools have been called
  try {
    while max_iterations > 0 {
      max_iterations = max_iterations - 1

      // Send request (use streaming for first request)
      let (response, was_streaming) = send_chat_request(
        config, chat_history, tools,
      )
      if was_streaming {
        used_streaming = true
      }

      // Record usage statistics
      if response.usage is Some(u) {
        chat_history.usage_stats.add_request(
          u.input_tokens,
          u.output_tokens,
          u.input_tokens + u.output_tokens,
          chat_history.current_model,
        )
        // Update last context tokens with accurate value from API
        chat_history.last_context_tokens = u.input_tokens
      }

      // Extract text content and tool uses from response
      let content_text = response.get_text_content()
      let tool_uses = response.get_tool_uses()

      // Display text content if present and not using streaming
      if tool_uses.length() == 0 {
        match content_text {
          Some(content_str) => {
            if !used_streaming {
              @output.jarvis_says(content_str)
            }

            // Check if message ends with a colon (: or ：)
            // This often indicates Claude is about to describe an action but hasn't taken it
            let trimmed = content_str.trim(chars=" \t\n\r").to_string()
            let ends_with_colon = trimmed.has_suffix(":") ||
              trimmed.has_suffix("：")
            if ends_with_colon {
              // Message added to history
              let assistant_msg = @types.Message::new("assistant", content_str)
              chat_history.add(assistant_msg)

              // Prompt Claude to actually call the tool instead of just describing
              let continuation_prompt = @types.Message::new(
                "user", "Please proceed with the actual tool call now. Do not describe what you will do - execute the tool.",
              )
              chat_history.add(continuation_prompt)

              // Continue the loop to get the actual tool call
              continue
            }
          }
          None =>
            if !used_streaming {
              @output.system_error("No content in response")
              return
            }
        }
        // No tool calls, add message to history if non-empty
        // Claude API requires text content blocks to be non-empty
        let content_str = match content_text {
          Some(c) => c
          None => ""
        }
        if !content_str.is_empty() {
          let assistant_msg = @types.Message::new("assistant", content_str)
          chat_history.add(assistant_msg)
        }

        // If we used streaming, this is the final response - return control to user
        if used_streaming {
          return
        }

        // Auto-continue: only if we've already called tools (i.e., we're in "work mode")
        // This prevents simple conversational responses from looping forever
        if has_called_tools {
          // system_notify("Working on your request...")
          let continue_msg = @types.Message::new(
            "user", "Continue with your task. If you have completed everything, call the end_elaborate tool.",
          )
          chat_history.add(continue_msg)
          // Continue the loop instead of breaking
          continue
        } else {
          // First response with no tool calls - just return control to user
          return
        }
      }

      // We have tool calls to execute
      has_called_tools = true // Mark that we've entered work mode
      // Display text content only if not using streaming (streaming already printed it)
      if !used_streaming {
        if content_text is Some(content_str) && !content_str.is_blank() {
          @output.jarvis_says(content_str)
        }
      }

      // Build assistant message with the full response for history
      // IMPORTANT: Only add message if there's actual content
      // Claude API requires content field to be non-null
      if content_text is Some(content) {
        if !content.is_empty() {
          let assistant_msg = @types.Message::new("assistant", content)
          chat_history.add(assistant_msg)
        }
      }

      // Execute each tool and collect results
      let (tool_results, elaborate_complete) = execute_tools_and_collect_results(
        tool_uses, chat_history,
      )

      // If elaborate is complete, end the loop
      if elaborate_complete {
        return
      }

      // Send tool results back as a user message
      let results_text = format_tool_results_as_text(tool_uses, tool_results)
      let user_msg_with_results = @types.Message::new("user", results_text)
      chat_history.add(user_msg_with_results)

      // Continue loop to get final response after tool execution
    }
    if max_iterations == 0 {
      @output.system_error("Maximum tool calling iterations reached")
    }
  } catch {
    @types.EnvVarNotSet(msg) => @output.system_error("Environment variable not set: \{msg}")
    @types.HttpError(msg) => @output.system_error("HTTP error: \{msg}")
    @types.StringViewError(msg) => @output.system_error("String view error: \{msg}")
    e => raise e
  }
}
