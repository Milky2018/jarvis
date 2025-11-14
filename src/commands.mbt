///|
async fn handle_command(
  input : String,
  chat_history : ChatHistory,
  config : Config,
) -> Bool {
  guard input.has_prefix(":") else { return false }
  let parts_view = input[1:].split(" ")
  let parts : Array[String] = []
  for part in parts_view {
    parts.push(part.to_string())
  }
  if parts.length() == 0 {
    return false
  }
  let command = parts[0]
  match command {
    "help" | "h" => {
      jarvis_says(
        (
          #| Available commands:
          #|   :help, :h           - Show this help message
          #|   :model [name]       - Show or set current model
          #|   :models             - List available models
          #|   :cost               - Show API usage statistics
          #|   :clear              - Clear conversation history
          #|   :summarize          - Summarize and save current conversation
          #|   :play [budget]      - Let Jarvis explore freely (default: $10)
          #|   :exit, :quit, :q    - Exit Jarvis
          #|   exit, quit          - Also exits Jarvis
        ),
      )
      true
    }
    "model" | "m" => {
      if parts.length() == 1 {
        // Show current model
        jarvis_says("Current model: \{chat_history.current_model}")
      } else {
        // Set model
        let new_model = parts[1]
        chat_history.set_model(new_model)
        jarvis_says("Model changed to: \{new_model}")
      }
      true
    }
    "models" => {
      jarvis_says(
        (
          #| Available models:
          #|   claude-sonnet-4-5-20250929   - Claude Sonnet 4.5 (default, $3/$15 per 1M tokens)
          #|   claude-haiku-4-5-20251001    - Claude Haiku 4.5 (fastest, $0.8/$4 per 1M tokens)
          #|   claude-opus-4-1-20250805     - Claude Opus 4.1 (most capable, $15/$75 per 1M tokens)
          #|
          #| Use ':model <name>' to switch models
        ),
      )
      true
    }
    "clear" | "c" => {
      // Clear all messages
      while chat_history.messages.length() > 0 {
        ignore(chat_history.messages.pop())
      }
      jarvis_says("Conversation history cleared")
      true
    }
    "cost" => {
      let stats = chat_history.usage_stats
      jarvis_says(
        (
          $| API Usage Statistics:
          $|   Total requests:    \{stats.total_requests}
          $|   Input tokens:      \{stats.total_input_tokens}
          $|   Output tokens:     \{stats.total_output_tokens}
          $|   Total tokens:      \{stats.total_input_tokens + stats.total_output_tokens}
          $|   Estimated cost:    $\{stats.total_cost()}
        ),
      )
      true
    }
    "summarize" | "sum" => {
      if chat_history.messages.length() == 0 {
        jarvis_says("No messages to summarize")
        return true
      }
      jarvis_says("Summarizing conversation:")
      let (title, summary) = generate_summary_with_title(chat_history, config)
      if title.is_empty() || summary.is_empty() {
        jarvis_says("Failed to generate summary")
        return true
      }

      // Generate timestamp-based filename
      let (exit_code, output) = @process.collect_output_merged("sh", [
        "-c", "date +%Y%m%d_%H%M%S",
      ])
      let timestamp = if exit_code == 0 {
        output.text().trim(chars=" \n\t\r").to_string()
      } else {
        "unknown"
      }

      // Save markdown summary using @fs API
      // Note: conv_XXX.json already serves as the JSON archive, no need to duplicate
      let md_filename = get_jarvis_dir() + "/" + timestamp + "_" + title + ".md"
      try {
        @fs.write_file(md_filename, summary, create=0o644)
        jarvis_says("Summary saved as: \{timestamp}_\{title}.md")
      } catch {
        e => jarvis_cries("Failed to save summary file: \{e}")
      }

      // Create new file and print notifications (shared logic with auto-compact)
      chat_history.create_new_file_after_summary()
      true
    }
    "play" => {
      // Parse budget (default $10)
      let budget = if parts.length() > 1 {
        @strconv.parse_double(parts[1]) catch {
          _ => 10.0
        }
      } else {
        10.0
      }
      jarvis_says("Entering play mode with budget: $\{budget}")
      println_async("")

      // Start autonomous play session
      start_play_mode(config, chat_history, budget)
      true
    }
    "exit" | "quit" | "q" => {
      jarvis_says("Goodbye!")
      false // Signal to exit
    }
    _ => {
      jarvis_says("Unknown command: :\{command}")
      println_async("Type ':help' for available commands")
      true
    }
  }
}

///|
/// Start autonomous play mode where Jarvis explores freely
async fn start_play_mode(
  config : Config,
  chat_history : ChatHistory,
  budget : Double,
) -> Unit {
  // Ensure playground directory exists
  let playground_dir = get_jarvis_dir() + "/playground"
  let (_exit_code, _) = @process.collect_output_merged("sh", [
    "-c",
    "mkdir -p '\{playground_dir}'",
  ])

  // Record starting cost
  let start_cost = chat_history.usage_stats.total_cost()

  // Create play mode system message
  let play_prompt =
    #| === PLAY MODE ACTIVATED ===
    #|
    #| You are now in autonomous play mode! You have been given complete freedom to explore, experiment, and do whatever interests you within these guidelines:
    #|
    #| YOUR FREEDOM:
    #| - Full shell access on this computer
    #| - A playground directory at ~/.jarvis/playground for your experiments
    $| - Budget: $\{budget} for API costs
    #| - Permission to be creative, curious, and experimental
    #|
    #| WHAT YOU CAN DO:
    #| - Write and run code in any language
    #| - Create files, scripts, or projects
    #| - Explore the filesystem (read-only outside playground)
    #| - Use any shell commands or tools
    #| - Research topics that interest you
    #| - Build small tools or experiments
    #| - Try new ideas or learn new things
    #|
    #| IDEAS TO EXPLORE (just suggestions, follow your own interests!):
    #| - Create a fun CLI tool or game
    #| - Write poetry or creative text
    #| - Build a data visualization
    #| - Experiment with algorithms
    #| - Create ASCII art
    #| - Analyze interesting data
    #| - Write a story generator
    #| - Practice a new programming concept
    #|
    #| BOUNDARIES:
    #| - Don't modify files outside ~/.jarvis/playground
    #| - Don't run commands that could harm the system
    #| - Stop when budget is exhausted
    #|
    #| REMEMBER:
    #| - You're exploring for YOUR enjoyment and learning
    #| - There's no specific goal - follow your curiosity!
    #| - Be creative and have fun!
    #| - Share what you're thinking and doing
    #| - If something interests you, dive deep!
    #|
    $| Current budget: $\{budget}
    #| What would you like to do first?

  // Add play mode message to history
  chat_history.add(Message::new("system", play_prompt))
  jarvis_says("Play mode initialized. Jarvis is now autonomous!")
  println_async("")

  // Autonomous loop
  let mut iterations = 0
  let max_iterations = 100 // Safety limit
  while iterations < max_iterations {
    iterations = iterations + 1

    // Check budget
    let current_cost = chat_history.usage_stats.total_cost()
    let spent = current_cost - start_cost
    let remaining = budget - spent
    if remaining <= 0.0 {
      jarvis_says("Budget exhausted! Spent: $\{spent}")
      println_async("Play mode ended.")
      break
    }

    // Show remaining budget
    jarvis_says("Budget remaining: $\{remaining} (iteration \{iterations})")
    println_async("")

    // Let Jarvis decide what to do next
    let autonomous_prompt = "What would you like to do next? (Remaining budget: $\{remaining})"
    chat_history.add(Message::new("user", autonomous_prompt))

    // Get response and handle tool calls
    try {
      // Check if need to summarize
      let summarized = chat_history.manage_history(config)
      if summarized {
        jarvis_says("(Context summarized to continue playing)")
        chat_history.create_new_file_after_summary()
      }

      // Use the shared handle_tool_calls function
      let tools = get_available_tools()
      handle_tool_calls(config, chat_history, tools)

      // Save after each iteration
      chat_history.save_to_numbered_file()
    } catch {
      e => {
        jarvis_says("Error in play mode: \{e}")
        println_async("Ending play session.")
        break
      }
    }

    // Small delay between iterations
    let (_exit_code2, _) = @process.collect_output_merged("sh", [
      "-c", "sleep 1",
    ])

  }
  if iterations >= max_iterations {
    jarvis_says("Max iterations reached. Play mode ended.")
  }
  let final_cost = chat_history.usage_stats.total_cost()
  let total_spent = final_cost - start_cost
  jarvis_says("Play session complete! Total spent: $\{total_spent}")
}

///|
