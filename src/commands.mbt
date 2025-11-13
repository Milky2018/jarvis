///|
async fn handle_command(
  input : String,
  chat_history : ChatHistory,
  config : Config,
) -> Bool {
  if input.has_prefix(":") == false {
    return false
  }
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
      print_jarvis_prefix()
      println_async("Available commands:")
      println_async("  :help, :h           - Show this help message")
      println_async("  :model [name]       - Show or set current model")
      println_async("  :models             - List available models")
      println_async("  :cost               - Show API usage statistics")
      println_async("  :clear              - Clear conversation history")
      println_async("  :summarize          - Summarize and save current conversation")
      println_async("  :exit, :quit, :q    - Exit Jarvis")
      println_async("  exit, quit          - Also exits Jarvis")
      true
    }
    "model" | "m" => {
      if parts.length() == 1 {
        // Show current model
        print_jarvis_prefix()
        println_async("Current model: \{chat_history.current_model}")
      } else {
        // Set model
        let new_model = parts[1]
        chat_history.set_model(new_model)
        print_jarvis_prefix()
        println_async("Model changed to: \{new_model}")
      }
      true
    }
    "models" => {
      print_jarvis_prefix()
      println_async("Available models:")
      println_async(
        "  claude-sonnet-4-5-20250929   - Claude Sonnet 4.5 (default, $3/$15 per 1M tokens)",
      )
      println_async(
        "  claude-haiku-4-5-20251001    - Claude Haiku 4.5 (fastest, $0.8/$4 per 1M tokens)",
      )
      println_async(
        "  claude-opus-4-1-20250805     - Claude Opus 4.1 (most capable, $15/$75 per 1M tokens)",
      )
      println_async("")
      println_async("Use ':model <name>' to switch models")
      true
    }
    "clear" | "c" => {
      // Clear all messages
      while chat_history.messages.length() > 0 {
        ignore(chat_history.messages.pop())
      }
      print_jarvis_prefix()
      println_async("Conversation history cleared")
      true
    }
    "cost" => {
      let stats = chat_history.usage_stats
      let total_cost = stats.total_cost()
      print_jarvis_prefix()
      println_async("API Usage Statistics:")
      println_async("  Total requests:    \{stats.total_requests}")
      println_async("  Input tokens:      \{stats.total_input_tokens}")
      println_async("  Output tokens:     \{stats.total_output_tokens}")
      println_async(
        "  Total tokens:      \{stats.total_input_tokens + stats.total_output_tokens}",
      )
      println_async("  Estimated cost:    $\{total_cost}")
      true
    }
    "summarize" | "sum" => {
      if chat_history.messages.length() == 0 {
        print_jarvis_prefix()
        println_async("No messages to summarize")
        return true
      }
      print_jarvis_prefix()
      println_async("Summarizing conversation...")
      let (title, summary) = generate_summary_with_title(chat_history, config)
      if title.is_empty() || summary.is_empty() {
        print_jarvis_prefix()
        println_async("Failed to generate summary")
        return true
      }

      // Generate timestamp-based filename for archive
      let (exit_code, output) = @process.collect_output_merged("sh", [
        "-c",
        "date +%Y%m%d_%H%M%S",
      ])
      let timestamp = if exit_code == 0 {
        output.text()[:].trim(chars=" \n\t\r").to_string()
      } else {
        "unknown"
      }

      // Save archived JSON with timestamp and title
      let json_filename = get_jarvis_dir() + "/" + timestamp + "_" + title + ".json"
      chat_history.save(json_filename)

      // Save markdown summary using @fs API
      let md_filename = get_jarvis_dir() + "/" + timestamp + "_" + title + ".md"
      try {
        @fs.write_file(md_filename, summary, create=0o644)
        print_jarvis_prefix()
        println_async("Conversation archived as: \{timestamp}_\{title}")
      } catch {
        e => {
          print_jarvis_prefix()
          println_async("Warning: Failed to save summary file: \{e}")
        }
      }

      // Create a new conversation file and switch to it (like auto-summarize)
      chat_history.create_new_file_after_summary()
      let num_str = if chat_history.current_file_number < 10 {
        "00\{chat_history.current_file_number}"
      } else if chat_history.current_file_number < 100 {
        "0\{chat_history.current_file_number}"
      } else {
        chat_history.current_file_number.to_string()
      }
      print_jarvis_prefix()
      println_async("Created new conversation file: conv_\{num_str}.json")
      println_async("(Continuing conversation in new file)")

      true
    }
    "exit" | "quit" | "q" => {
      print_jarvis_prefix()
      println_async("Goodbye!")
      false // Signal to exit
    }
    _ => {
      print_jarvis_prefix()
      println_async("Unknown command: :\{command}")
      println_async("Type ':help' for available commands")
      true
    }
  }
}

///|
