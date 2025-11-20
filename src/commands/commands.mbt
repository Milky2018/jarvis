///|
/// Command trait - defines interface for all commands
priv trait Command {
  name(Self) -> String
  aliases(Self) -> Array[String]
  usage(Self) -> String
  description(Self) -> String
  async execute(Self, Array[String], @session.ChatHistory, @types.Config) -> Bool
}

///|
/// Help Command
priv struct HelpCommand {} derive(Default)

///|
impl Command for HelpCommand with name(_self) {
  "help"
}

///|
impl Command for HelpCommand with aliases(_self) {
  ["h"]
}

///|
impl Command for HelpCommand with usage(_self) {
  ":help, :h"
}

///|
impl Command for HelpCommand with description(_self) {
  "Show this help message"
}

///|
impl Command for HelpCommand with execute(_self, _parts, _chat_history, _config) {
  let commands = get_all_commands()
  let mut help_text = "Available commands:\n"
  for cmd in commands {
    help_text = help_text +
      "  " +
      cmd.usage() +
      " - " +
      cmd.description() +
      "\n"
  }
  @output.jarvis_says(help_text.trim(chars=" \n\t\r").to_string())
  true
}

///|
/// Model Command
priv struct ModelCommand {} derive(Default)

///|
impl Command for ModelCommand with name(_self) {
  "model"
}

///|
impl Command for ModelCommand with aliases(_self) {
  ["m"]
}

///|
impl Command for ModelCommand with usage(_self) {
  ":model [name]"
}

///|
impl Command for ModelCommand with description(_self) {
  "Show or set current model"
}

///|
impl Command for ModelCommand with execute(_self, parts, chat_history, _config) {
  if parts.length() == 1 {
    @output.jarvis_says("Current model: \{chat_history.current_model}")
  } else {
    let new_model = parts[1]
    chat_history.set_model(new_model)
    @output.jarvis_says("Model changed to: \{new_model}")
  }
  true
}

///|
/// Models Command
priv struct ModelsCommand {} derive(Default)

///|
impl Command for ModelsCommand with name(_self) {
  "models"
}

///|
impl Command for ModelsCommand with aliases(_self) {
  []
}

///|
impl Command for ModelsCommand with usage(_self) {
  ":models"
}

///|
impl Command for ModelsCommand with description(_self) {
  "List available models"
}

///|
impl Command for ModelsCommand with execute(
  _self,
  _parts,
  chat_history,
  _config,
) {
  let current = chat_history.current_model
  let petite = chat_history.petite_model
  let builder = StringBuilder::new()
  builder.write_string("Available models:\n")
  for model in @types.available_models() {
    let marker = if current == model.id {
      "[current] "
    } else if petite == model.id {
      "[petite]  "
    } else {
      "          "
    }
    builder.write_string("  ")
    builder.write_string(marker)
    builder.write_string(model.id)
    builder.write_string(" - ")
    builder.write_string(model.description)
    builder.write_string("\n")
  }
  builder.write_string("\nUse ':model <name>' to switch models")
  @output.jarvis_says(builder.to_string())
  true
}

///|
/// Petite Command
priv struct PetiteCommand {} derive(Default)

///|
impl Command for PetiteCommand with name(_self) {
  "petite"
}

///|
impl Command for PetiteCommand with aliases(_self) {
  ["p"]
}

///|
impl Command for PetiteCommand with usage(_self) {
  ":petite [name]"
}

///|
impl Command for PetiteCommand with description(_self) {
  "Show or set petite model for summaries"
}

///|
impl Command for PetiteCommand with execute(_self, parts, chat_history, _config) {
  if parts.length() == 1 {
    @output.jarvis_says("Current petite model: \{chat_history.petite_model}")
  } else {
    let new_model = parts[1]
    chat_history.petite_model = new_model
    @output.jarvis_says("Petite model changed to: \{new_model}")
  }
  true
}

///|
/// Clear Command
priv struct ClearCommand {} derive(Default)

///|
impl Command for ClearCommand with name(_self) {
  "clear"
}

///|
impl Command for ClearCommand with aliases(_self) {
  ["c"]
}

///|
impl Command for ClearCommand with usage(_self) {
  ":clear, :c"
}

///|
impl Command for ClearCommand with description(_self) {
  "Clear conversation history"
}

///|
impl Command for ClearCommand with execute(_self, _parts, chat_history, _config) {
  // Clear all messages
  chat_history.messages.clear()
  @output.jarvis_says("Conversation history cleared")
  // Persist the cleared state to file
  chat_history.save_to_numbered_file()
  true
}

///|
/// Cost Command
priv struct CostCommand {} derive(Default)

///|
impl Command for CostCommand with name(_self) {
  "cost"
}

///|
impl Command for CostCommand with aliases(_self) {
  []
}

///|
impl Command for CostCommand with usage(_self) {
  ":cost"
}

///|
impl Command for CostCommand with description(_self) {
  "Show API usage statistics"
}

///|
impl Command for CostCommand with execute(_self, _parts, chat_history, _config) {
  let stats = chat_history.usage_stats
  let mut cost_breakdown = ""
  stats.cost_by_model.each(fn(model_id, cost) {
    let short_name = match @types.get_model_info(model_id) {
      Some(info) => info.name
      None => model_id
    }
    cost_breakdown = cost_breakdown +
      "  " +
      short_name +
      ": $" +
      cost.to_string() +
      "\n"
  })
  @output.jarvis_says(
    (
      $| API Usage Statistics:
      $|   Total requests:    \{stats.total_requests}
      $|   Input tokens:      \{stats.total_input_tokens}
      $|   Output tokens:     \{stats.total_output_tokens}
      $|   Total tokens:      \{stats.total_input_tokens + stats.total_output_tokens}
      $|   Estimated cost:    $\{stats.total_cost()}
      $|
      $| Cost by model:
      $| \{cost_breakdown}
    ),
  )
  true
}

///|
/// Summarize Command
priv struct SummarizeCommand {} derive(Default)

///|
impl Command for SummarizeCommand with name(_self) {
  "summarize"
}

///|
impl Command for SummarizeCommand with aliases(_self) {
  ["sum"]
}

///|
impl Command for SummarizeCommand with usage(_self) {
  ":summarize, :sum"
}

///|
impl Command for SummarizeCommand with description(_self) {
  "Compress conversation history to reduce token usage"
}

///|
impl Command for SummarizeCommand with execute(
  _self,
  _parts,
  chat_history,
  config,
) {
  if chat_history.messages.length() == 0 {
    @output.jarvis_says("No messages to compress")
    return true
  }

  // Compress the conversation history by replacing old messages with summary
  // Force compression regardless of token count since user explicitly requested it
  let messages_count = chat_history.messages.length()
  let recent_keep = @types.SUMMARIZE_KEEP_RECENT
  if messages_count <= recent_keep + 1 {
    @output.jarvis_says(
      "Not enough messages to compress (need at least \{recent_keep + 2} messages)",
    )
    return true
  }
  @output.jarvis_says("Compressing conversation history...")

  // Separate messages: first + middle + recent
  let first_message = chat_history.messages[0]
  let recent_start = messages_count - recent_keep

  // Middle messages to summarize (skip first, keep recent)
  let middle_messages : Array[@types.Message] = []
  for i = 1; i < recent_start; i = i + 1 {
    middle_messages.push(chat_history.messages[i])
  }

  // Generate summary
  let summary_text = @session.summarize_messages(
    config,
    middle_messages,
    chat_history.current_model,
  )
  let summary_message = @types.Message::new(
    "system",
    "Previous conversation summary: " + summary_text,
  )

  // Rebuild messages array: first + summary + recent
  let new_messages : Array[@types.Message] = [first_message, summary_message]
  for i = recent_start; i < messages_count; i = i + 1 {
    new_messages.push(chat_history.messages[i])
  }

  // Replace messages
  chat_history.messages.clear()
  for msg in new_messages {
    chat_history.messages.push(msg)
  }
  @output.jarvis_says(
    "Conversation history compressed (\{middle_messages.length()} messages → 1 summary)",
  )

  // Create new file and print notifications
  chat_history.create_new_file_after_summary()
  true
}

///|
/// Play Command
priv struct PlayCommand {} derive(Default)

///|
impl Command for PlayCommand with name(_self) {
  "play"
}

///|
impl Command for PlayCommand with aliases(_self) {
  []
}

///|
impl Command for PlayCommand with usage(_self) {
  ":play [budget]"
}

///|
impl Command for PlayCommand with description(_self) {
  "Let Jarvis explore freely (default: $10)"
}

///|
impl Command for PlayCommand with execute(_self, parts, chat_history, config) {
  // Parse budget (default from config)
  let budget = if parts.length() > 1 {
    @strconv.parse_double(parts[1]) catch {
      _ => @types.DEFAULT_PLAY_BUDGET
    }
  } else {
    @types.DEFAULT_PLAY_BUDGET
  }
  @output.jarvis_says("Entering play mode with budget: $\{budget}")

  // Start autonomous play session
  start_play_mode(config, chat_history, budget)
  true
}

///|
/// Exit Command
priv struct ExitCommand {} derive(Default)

///|
impl Command for ExitCommand with name(_self) {
  "exit"
}

///|
impl Command for ExitCommand with aliases(_self) {
  ["quit", "q"]
}

///|
impl Command for ExitCommand with usage(_self) {
  ":exit, :quit, :q"
}

///|
impl Command for ExitCommand with description(_self) {
  "Exit Jarvis"
}

///|
impl Command for ExitCommand with execute(_self, _parts, _chat_history, _config) {
  @output.jarvis_says("Goodbye!")
  raise @types.ExitRequested
}

///|
/// Get all available commands
fn get_all_commands() -> Array[&Command] {
  [
    HelpCommand::default(),
    ModelCommand::default(),
    ModelsCommand::default(),
    PetiteCommand::default(),
    ClearCommand::default(),
    CostCommand::default(),
    SummarizeCommand::default(),
    PlayCommand::default(),
    ExitCommand::default(),
  ]
}

///|
pub async fn handle_command(
  input : String,
  chat_history : @session.ChatHistory,
  config : @types.Config,
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

  // Try to match command by name or aliases
  let commands = get_all_commands()
  for cmd in commands {
    if cmd.name() == command {
      return cmd.execute(parts, chat_history, config)
    }
    for cmd_alias in cmd.aliases() {
      if cmd_alias == command {
        return cmd.execute(parts, chat_history, config)
      }
    }
  }

  // Unknown command
  @output.jarvis_says(
    "Unknown command: :\{command}\nType ':help' for available commands",
  )
  true
}

///|
/// Start autonomous play mode where Jarvis explores freely
async fn start_play_mode(
  config : @types.Config,
  chat_history : @session.ChatHistory,
  budget : Double,
) -> Unit {
  // Ensure playground directory exists
  let playground_dir = @session.get_jarvis_dir() + "/playground"
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
    #| - Stop when budget is exhausted or when you feel done
    #|
    #| REMEMBER:
    #| - You're exploring for YOUR enjoyment and learning
    #| - There's no specific goal - follow your curiosity!
    #| - Be creative and have fun!
    #| - Share what you're thinking and doing
    #| - If something interests you, dive deep!
    #| - When you're satisfied with your exploration or feel done, use the end_play_mode tool to exit gracefully
    #|
    $| Current budget: $\{budget}
    #| What would you like to do first?

  // Add play mode message to history
  chat_history.add(@types.Message::new("system", play_prompt))

  // Add initial user message to trigger Jarvis's first response
  chat_history.add(@types.Message::new("user", "Begin your exploration."))

  // First iteration - let Jarvis start autonomously
  let mut iterations = 0
  let max_iterations = @types.MAX_PLAY_ITERATIONS // Safety limit
  while iterations < max_iterations {
    iterations = iterations + 1

    // Check budget
    let current_cost = chat_history.usage_stats.total_cost()
    let spent = current_cost - start_cost
    let remaining = budget - spent
    if remaining <= 0.0 {
      @output.jarvis_says("Budget exhausted! Spent: $\{spent}\nPlay mode ended.")
      break
    }

    // Show remaining budget
    @output.jarvis_says("Budget remaining: $\{remaining} (iteration \{iterations})")

    // Get response and handle tool calls
    try {
      // Check if need to summarize
      let summarized = chat_history.manage_history(config)
      if summarized {
        @output.jarvis_says("(Context summarized to continue playing)")
        chat_history.create_new_file_after_summary()
      }

      // Use the shared handle_tool_calls function with play mode tools
      let tools = @tools.get_available_tools(in_play_mode=true)
      @executor.handle_tool_calls(config, chat_history, tools)

      // In play mode, if Jarvis responded without using tools, we need to add a user message
      // to prompt continuation. Otherwise, the next iteration will fail because the last
      // message is from assistant and Claude API requires alternating roles.
      // Check if the last message is from assistant (which means no tool calls were made)
      if chat_history.messages.length() > 0 {
        let last_msg = chat_history.messages[chat_history.messages.length() - 1]
        if last_msg.role == "assistant" {
          // Jarvis just responded with text, add a continuation prompt
          chat_history.add(
            @types.Message::new(
              "user", "Continue your exploration. If you're done or satisfied, use the end_play_mode tool to exit.",
            ),
          )
        }
      }

      // Save after each iteration
      chat_history.save_to_numbered_file()
    } catch {
      @types.PlayModeEnded => {
        // Jarvis called end_play_mode tool
        @output.system_info("Play mode ended by Jarvis.")
        break
      }
      e => {
        @output.system_error("Error in play mode: \{e}\nEnding play session.")
        break
      }
    }
  }
  if iterations >= max_iterations {
    @output.jarvis_says("Max iterations reached. Play mode ended.")
  }
  let final_cost = chat_history.usage_stats.total_cost()
  let total_spent = final_cost - start_cost
  @output.jarvis_says("Play session complete! Total spent: $\{total_spent}")
}
