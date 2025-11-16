///|
/// Command trait - defines interface for all commands
trait Command {
  name(Self) -> String
  aliases(Self) -> Array[String]
  usage(Self) -> String
  description(Self) -> String
  async execute(Self, Array[String], ChatHistory, Config) -> Bool
}

///|
/// Help Command
struct HelpCommand {} derive(Default)

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
  jarvis_says(help_text.trim(chars=" \n\t\r").to_string())
  true
}

///|
/// Model Command
struct ModelCommand {} derive(Default)

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
    jarvis_says("Current model: \{chat_history.current_model}")
  } else {
    let new_model = parts[1]
    chat_history.set_model(new_model)
    jarvis_says("Model changed to: \{new_model}")
  }
  true
}

///|
/// Models Command
struct ModelsCommand {} derive(Default)

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
  let sonnet_marker = if current == "claude-sonnet-4-5-20250929" {
    " (current)"
  } else if petite == "claude-sonnet-4-5-20250929" {
    " (petite)"
  } else {
    ""
  }
  let haiku_marker = if current == "claude-haiku-4-5-20251001" {
    " (current)"
  } else if petite == "claude-haiku-4-5-20251001" {
    " (petite)"
  } else {
    ""
  }
  let opus_marker = if current == "claude-opus-4-1-20250805" {
    " (current)"
  } else if petite == "claude-opus-4-1-20250805" {
    " (petite)"
  } else {
    ""
  }
  jarvis_says(
    (
      $| Available models:
      $|   claude-sonnet-4-5-20250929   - Claude Sonnet 4.5 (default, $3/$15 per 1M tokens)\{sonnet_marker}
      $|   claude-haiku-4-5-20251001    - Claude Haiku 4.5 (fastest, $0.8/$4 per 1M tokens)\{haiku_marker}
      $|   claude-opus-4-1-20250805     - Claude Opus 4.1 (most capable, $15/$75 per 1M tokens)\{opus_marker}
      $|
      $| Use ':model <name>' to switch models
    ),
  )
  true
}

///|
/// Petite Command
struct PetiteCommand {} derive(Default)

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
    jarvis_says("Current petite model: \{chat_history.petite_model}")
  } else {
    let new_model = parts[1]
    chat_history.petite_model = new_model
    jarvis_says("Petite model changed to: \{new_model}")
  }
  true
}

///|
/// Clear Command
struct ClearCommand {} derive(Default)

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
  while chat_history.messages.length() > 0 {
    ignore(chat_history.messages.pop())
  }
  jarvis_says("Conversation history cleared")
  true
}

///|
/// Cost Command
struct CostCommand {} derive(Default)

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
  stats.cost_by_model.each(fn(model, cost) {
    let short_name = match model {
      "claude-sonnet-4-5-20250929" => "Sonnet 4.5"
      "claude-haiku-4-5-20251001" => "Haiku 4.5"
      "claude-opus-4-1-20250805" => "Opus 4.1"
      _ => model
    }
    cost_breakdown = cost_breakdown +
      "  " +
      short_name +
      ": $" +
      cost.to_string() +
      "\n"
  })
  jarvis_says(
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
struct SummarizeCommand {} derive(Default)

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
  "Summarize and save current conversation"
}

///|
impl Command for SummarizeCommand with execute(
  _self,
  _parts,
  chat_history,
  config,
) {
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
  let md_filename = get_jarvis_dir() + "/" + timestamp + "_" + title + ".md"
  try {
    @fs.write_file(md_filename, summary, create=0o644)
    jarvis_says("Summary saved as: \{timestamp}_\{title}.md")
  } catch {
    e => jarvis_cries("Failed to save summary file: \{e}")
  }

  // Compress the conversation history by replacing old messages with summary
  // Force compression regardless of token count since user explicitly requested summarization
  let messages_count = chat_history.messages.length()
  let recent_keep = SUMMARIZE_KEEP_RECENT
  if messages_count > recent_keep + 1 {
    // Separate messages: first + middle + recent
    let first_message = chat_history.messages[0]
    let recent_start = messages_count - recent_keep

    // Middle messages to summarize (skip first, keep recent)
    let middle_messages : Array[Message] = []
    for i = 1; i < recent_start; i = i + 1 {
      middle_messages.push(chat_history.messages[i])
    }
    if middle_messages.length() > 0 {
      // Generate summary
      let summary_text = summarize_messages(
        config,
        middle_messages,
        chat_history.current_model,
      )
      let summary_message = Message::new(
        "system",
        "Previous conversation summary: " + summary_text,
      )

      // Rebuild messages array: first + summary + recent
      let new_messages : Array[Message] = [first_message, summary_message]
      for i = recent_start; i < messages_count; i = i + 1 {
        new_messages.push(chat_history.messages[i])
      }

      // Replace messages
      while chat_history.messages.length() > 0 {
        ignore(chat_history.messages.pop())
      }
      for msg in new_messages {
        chat_history.messages.push(msg)
      }
      jarvis_says("(Conversation history compressed)")
    }
  }

  // Create new file and print notifications
  chat_history.create_new_file_after_summary()
  true
}

///|
/// Play Command
struct PlayCommand {} derive(Default)

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
      _ => DEFAULT_PLAY_BUDGET
    }
  } else {
    DEFAULT_PLAY_BUDGET
  }
  jarvis_says("Entering play mode with budget: $\{budget}")
  println_async("")

  // Start autonomous play session
  start_play_mode(config, chat_history, budget)
  true
}

///|
/// Exit Command
struct ExitCommand {} derive(Default)

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
  jarvis_says("Goodbye!")
  raise ExitRequested
}

///|
/// Plan Command
struct PlanCommand {} derive(Default)

///|
impl Command for PlanCommand with name(_self) {
  "plan"
}

///|
impl Command for PlanCommand with aliases(_self) {
  []
}

///|
impl Command for PlanCommand with usage(_self) {
  ":plan <task description>"
}

///|
impl Command for PlanCommand with description(_self) {
  "Create a plan for a task before executing"
}

///|
impl Command for PlanCommand with execute(_self, parts, chat_history, config) {
  if parts.length() < 2 {
    jarvis_says("Usage: :plan <task description>")
    return true
  }

  // Join all parts after ":plan" as the task description
  let mut task = ""
  for i = 1; i < parts.length(); i = i + 1 {
    if i > 1 {
      task = task + " "
    }
    task = task + parts[i]
  }
  jarvis_says("Entering plan mode for task: \{task}")
  println_async("")

  // Start plan mode
  start_plan_mode(config, chat_history, task)
  true
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
    PlanCommand::default(),
    ExitCommand::default(),
  ]
}

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
  jarvis_says("Unknown command: :\{command}")
  println_async("Type ':help' for available commands")
  true
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
  chat_history.add(Message::new("system", play_prompt))

  // Add initial user message to trigger Jarvis's first response
  chat_history.add(Message::new("user", "Begin your exploration."))
  jarvis_says("Play mode initialized. Jarvis is now autonomous!")
  println_async("")

  // First iteration - let Jarvis start autonomously
  let mut iterations = 0
  let max_iterations = MAX_PLAY_ITERATIONS // Safety limit
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

    // Get response and handle tool calls
    try {
      // Check if need to summarize
      let summarized = chat_history.manage_history(config)
      if summarized {
        jarvis_says("(Context summarized to continue playing)")
        chat_history.create_new_file_after_summary()
      }

      // Use the shared handle_tool_calls function with play mode tools
      let tools = get_available_tools(in_play_mode=true)
      let success = handle_tool_calls(config, chat_history, tools)

      // If handle_tool_calls returned false, it means there was an error (like empty response)
      // Break out of the loop to avoid infinite iterations
      if !success {
        jarvis_says("Encountered error in play mode, ending session.")
        break
      }

      // In play mode, if Jarvis responded without using tools, we need to add a user message
      // to prompt continuation. Otherwise, the next iteration will fail because the last
      // message is from assistant and Claude API requires alternating roles.
      // Check if the last message is from assistant (which means no tool calls were made)
      if chat_history.messages.length() > 0 {
        let last_msg = chat_history.messages[chat_history.messages.length() - 1]
        if last_msg.role == "assistant" {
          // Jarvis just responded with text, add a continuation prompt
          chat_history.add(
            Message::new(
              "user", "Continue your exploration. If you're done or satisfied, use the end_play_mode tool to exit.",
            ),
          )
        }
      }

      // Save after each iteration
      chat_history.save_to_numbered_file()
    } catch {
      PlayModeEnded => {
        // Jarvis called end_play_mode tool
        println_async("Play mode ended by Jarvis.")
        break
      }
      e => {
        jarvis_cries("Error in play mode: \{e}")
        println_async("Ending play session.")
        break
      }
    }
  }
  if iterations >= max_iterations {
    jarvis_says("Max iterations reached. Play mode ended.")
  }
  let final_cost = chat_history.usage_stats.total_cost()
  let total_spent = final_cost - start_cost
  jarvis_says("Play session complete! Total spent: $\{total_spent}")
}

///|
/// Start plan mode where Jarvis creates a plan and waits for approval
async fn start_plan_mode(
  config : Config,
  chat_history : ChatHistory,
  task : String,
) -> Unit {
  // Create plan mode system message
  let plan_prompt =
    #| === PLAN MODE ACTIVATED ===
    #|
    #| You are now in plan mode. Your task is to create a detailed execution plan before taking any action.
    #|
    #| INSTRUCTIONS:
    #| 1. Analyze the user's task carefully
    #| 2. Break it down into clear, numbered steps
    #| 3. For each step, specify:
    #|    - What you will do
    #|    - Which tools you will use
    #|    - Estimated complexity (simple/medium/complex)
    #| 4. Present the complete plan in a clear format
    #| 5. DO NOT execute anything yet - just present the plan
    #|
    #| PLAN FORMAT:
    #| Use markdown with clear numbering:
    #|
    #| # Plan: [Task Title]
    #|
    #| ## Steps:
    #| 1. [Step description]
    #|    - Tools: [tool1, tool2]
    #|    - Complexity: [simple/medium/complex]
    #|
    #| 2. [Next step...]
    #|    - Tools: [...]
    #|    - Complexity: [...]
    #|
    #| ## Estimated Total Time: [estimate]
    #|
    $| USER TASK: {task}
    #|
    #| Please create a detailed plan for this task.

  // Add plan mode message to history
  chat_history.add(Message::new("system", plan_prompt))

  // Add user task message
  chat_history.add(Message::new("user", "Create a plan for: \{task}"))

  // Generate the plan
  jarvis_says("Generating plan...")
  println_async("")
  try {
    // Get plan from Jarvis
    let tools = get_available_tools()
    let success = handle_tool_calls(config, chat_history, tools)
    if !success {
      jarvis_cries("Failed to generate plan")
      return
    }

    // The plan should now be in the last assistant message
    if chat_history.messages.length() > 0 {
      let last_msg = chat_history.messages[chat_history.messages.length() - 1]
      if last_msg.role == "assistant" {
        match last_msg.content {
          Some(plan_text) => {
            // Display the plan
            print_separator()
            println_async(plan_text)
            print_separator()
            println_async("")

            // Wait for user approval
            jarvis_says("Do you approve this plan? (yes/no/modify)")

            // Wait for approval using the same pattern as main loop
            let approval = @async.with_task_group(fn(group) {
              let approval_queue : @aqueue.Queue[String] = @aqueue.Queue::new()

              // Start readline in background
              group.spawn_bg(fn() {
                let rl = ReadlineInterface::with_history(0, [])
                while rl.read_to_queue(approval_queue) {

                }
              })

              // Wait for input
              let response = approval_queue
                .get()
                .trim(chars=" \n\t\r")
                .to_string()
                .to_lower()
              println_async("") // Print newline after input
              response
            })
            match approval {
              "yes" => {
                jarvis_says("Plan approved! Executing...")
                println_async("")
                execute_approved_plan(config, chat_history, task)
              }
              "no" => jarvis_says("Plan rejected. Exiting plan mode.")
              _ => {
                // User wants to modify
                jarvis_says(
                  "Plan modification requested. Please provide your changes:",
                )
                // For now, just exit - we can enhance this later
                jarvis_says(
                  "Plan mode ended. You can start a new plan with your modifications.",
                )
              }
            }
          }
          None => jarvis_cries("No plan was generated")
        }
      }
    }

    // Save conversation
    chat_history.save_to_numbered_file()
  } catch {
    e => jarvis_cries("Error in plan mode: \{e}")
  }
}

///|
/// Execute the approved plan
async fn execute_approved_plan(
  config : Config,
  chat_history : ChatHistory,
  _task : String,
) -> Unit {
  // Add execution instruction message
  let execute_msg = Message::new(
    "user", "The plan is approved. Please proceed with execution step by step. After each step, report your progress.",
  )
  chat_history.add(execute_msg)

  // Execute with normal tools
  let tools = get_available_tools()
  let mut max_iterations = 50 // Reasonable limit for plan execution
  while max_iterations > 0 {
    max_iterations = max_iterations - 1
    let success = handle_tool_calls(config, chat_history, tools)
    if !success {
      jarvis_cries("Encountered error during execution")
      break
    }

    // Check if Jarvis finished execution
    // If the last message is from assistant and doesn't request tools, we're done
    if chat_history.messages.length() > 0 {
      let last_msg = chat_history.messages[chat_history.messages.length() - 1]
      if last_msg.role == "assistant" {
        // Check if the response indicates completion
        match last_msg.content {
          Some(text) =>
            if text.contains("completed") ||
              text.contains("finished") ||
              text.contains("done") {
              break
            }
          None => ()
        }

        // Add continuation message
        chat_history.add(
          Message::new(
            "user", "Continue with the next step, or say DONE if finished.",
          ),
        )
      }
    }

    // Save progress after each iteration
    chat_history.save_to_numbered_file()
  }
  if max_iterations == 0 {
    jarvis_says("Plan execution reached iteration limit")
  }
  jarvis_says("Plan execution complete!")
  chat_history.save_to_numbered_file()
}

///|
