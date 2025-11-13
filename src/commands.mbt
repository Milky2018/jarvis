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
      println("Available commands:")
      println("  :help, :h           - Show this help message")
      println("  :model [name]       - Show or set current model")
      println("  :models             - List available models")
      println("  :cost               - Show API usage statistics")
      println("  :clear              - Clear conversation history")
      println("  :summarize          - Summarize and save current conversation")
      println("  :exit, :quit, :q    - Exit Jarvis")
      println("  exit, quit          - Also exits Jarvis")
      true
    }
    "model" | "m" => {
      if parts.length() == 1 {
        // Show current model
        print_jarvis_prefix()
        println("Current model: \{chat_history.current_model}")
      } else {
        // Set model
        let new_model = parts[1]
        chat_history.set_model(new_model)
        print_jarvis_prefix()
        println("Model changed to: \{new_model}")
      }
      true
    }
    "models" => {
      print_jarvis_prefix()
      println("Available models:")
      println(
        "  claude-sonnet-4-5-20250929   - Claude Sonnet 4.5 (default, $3/$15 per 1M tokens)",
      )
      println(
        "  claude-haiku-4-5-20251001    - Claude Haiku 4.5 (fastest, $0.8/$4 per 1M tokens)",
      )
      println(
        "  claude-opus-4-1-20250805     - Claude Opus 4.1 (most capable, $15/$75 per 1M tokens)",
      )
      println("")
      println("Use ':model <name>' to switch models")
      true
    }
    "clear" | "c" => {
      // Clear all messages
      while chat_history.messages.length() > 0 {
        ignore(chat_history.messages.pop())
      }
      print_jarvis_prefix()
      println("Conversation history cleared")
      true
    }
    "cost" => {
      let stats = chat_history.usage_stats
      let total_cost = stats.total_cost()
      print_jarvis_prefix()
      println("API Usage Statistics:")
      println("  Total requests:    \{stats.total_requests}")
      println("  Input tokens:      \{stats.total_input_tokens}")
      println("  Output tokens:     \{stats.total_output_tokens}")
      println(
        "  Total tokens:      \{stats.total_input_tokens + stats.total_output_tokens}",
      )
      println("  Estimated cost:    $\{total_cost}")
      true
    }
    "summarize" | "sum" => {
      if chat_history.messages.length() == 0 {
        print_jarvis_prefix()
        println("No messages to summarize")
        return true
      }
      print_jarvis_prefix()
      println("Summarizing conversation...")
      let (title, summary) = generate_summary_with_title(chat_history, config)
      if title.is_empty() || summary.is_empty() {
        print_jarvis_prefix()
        println("Failed to generate summary")
        return true
      }
      // Save JSON with title as filename
      let json_filename = get_conversation_path(title)
      chat_history.save(json_filename)
      // Save markdown summary
      let md_filename = get_jarvis_dir() + "/" + title + ".md"
      let escaped_summary = summary.replace(old="'", new="'\\''")
      let (exit_code, _) = @process.collect_output_merged("sh", [
        "-c",
        "echo '\{escaped_summary}' > '\{md_filename}'",
      ])
      if exit_code == 0 {
        print_jarvis_prefix()
        println("Conversation summarized and saved as: \{title}")
      } else {
        print_jarvis_prefix()
        println("Warning: Failed to save summary file")
      }
      true
    }
    "exit" | "quit" | "q" => {
      print_jarvis_prefix()
      println("Goodbye!")
      false // Signal to exit
    }
    _ => {
      print_jarvis_prefix()
      println("Unknown command: :\{command}")
      println("Type ':help' for available commands")
      true
    }
  }
}

///|
