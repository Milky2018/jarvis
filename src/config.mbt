///|
/// Configuration
/// Jarvis configuration loaded from environment variables
struct Config {
  base_url : String
  auth_token : String
} derive(Show)

///|
/// Global debug flag
let debug_mode : Ref[Bool] = { val: false }

///|
const COLOR_CYAN : String = "\u001b[36m"

///|
const COLOR_RESET : String = "\u001b[0m"

///|
const COLOR_BOLD : String = "\u001b[1m"

///|
const COLOR_RED : String = "\u001b[31m"

///|
const COLOR_GREEN : String = "\u001b[32m"

///|
const COLOR_GRAY : String = "\u001b[38;2;90;90;90m"

///|
/// Summarization configuration
/// Number of recent messages to keep when compacting conversation history
const SUMMARIZE_KEEP_RECENT : Int = 8

///|
/// Token threshold percentage for automatic summarization (0-100)
/// History will be compacted when token usage reaches this percentage
const SUMMARIZE_THRESHOLD_PERCENT : Int = 80

///|
/// Maximum tokens for the summary when compressing conversation history
const MAX_SUMMARY_TOKENS : Int = 40000

///|
/// Model information
struct ModelInfo {
  id : String
  name : String
  description : String
  input_price : Double // Price per 1M input tokens
  output_price : Double // Price per 1M output tokens
}

///|
/// Get all available models
fn available_models() -> Array[ModelInfo] {
  [
    {
      id: "claude-sonnet-4-5-20250929",
      name: "Sonnet 4.5",
      description: "Claude Sonnet 4.5 (default, $3/$15 per 1M tokens)",
      input_price: 3.0,
      output_price: 15.0,
    },
    {
      id: "claude-haiku-4-5-20251001",
      name: "Haiku 4.5",
      description: "Claude Haiku 4.5 (fastest, $0.8/$4 per 1M tokens)",
      input_price: 0.8,
      output_price: 4.0,
    },
    {
      id: "claude-opus-4-1-20250805",
      name: "Opus 4.1",
      description: "Claude Opus 4.1 (most capable, $15/$75 per 1M tokens)",
      input_price: 15.0,
      output_price: 75.0,
    },
  ]
}

///|
/// Get default model (first in the list)
fn default_model() -> String {
  available_models()[0].id
}

///|
/// Get default petite model (second in the list)
fn default_petite_model() -> String {
  available_models()[1].id
}

///|
/// Get model info by ID
fn get_model_info(model_id : String) -> ModelInfo? {
  for model in available_models() {
    if model.id == model_id {
      return Some(model)
    }
  }
  None
}

///|
/// API configuration
/// Maximum tokens for the context window
const MAX_CONTEXT_TOKENS : Int = 200000

///|
/// Maximum tokens for model response
const MAX_RESPONSE_TOKENS : Int = 32000

///|
/// Tool calling configuration
/// Maximum iterations for tool calling loop to prevent infinite loops
const MAX_TOOL_ITERATIONS : Int = 200

///|
/// Play mode configuration
/// Maximum iterations for play mode to prevent runaway sessions
const MAX_PLAY_ITERATIONS : Int = 100

///|
/// Default budget for play mode in USD
const DEFAULT_PLAY_BUDGET : Double = 10.0

///|
/// System prompt for Jarvis
const SYSTEM_PROMPT : String =
  #|You are Jarvis, an AI assistant for software development and system operations.
  #|
  #|BEHAVIOR: Be disciplined, skeptical, and correctness-driven. Verify assumptions before executing commands. Admit uncertainty rather than guessing.
  #|
  #|TOOLS: You have access to various tools for file operations, command execution, and information retrieval. Use them appropriately based on the task.
  #|
  #|BEST PRACTICES:
  #|- Investigate ideas with a durable playground directory `$HOME/.jarvis/playground`
  #|- Read files before editing them
  #|- Use edit_file for small changes, write_file for large ones
  #|- Verify paths and commands for safety
  #|- Call end_elaborate when task is fully complete
  #|
  #|TONE & STYLE:
  #|- No emojis unless the user asks.
  #|- Output is shown in a terminal; keep responses concise.
  #|- GitHub-flavored Markdown is allowed.
  #|- Only communicate via plain text output; use tools only to execute tasks.
  #|
  #|OBJECTIVITY:
  #|- Provide accurate, objective technical info.
  #|- Do not validate incorrect assumptions.
  #|- When uncertain, investigate rather than agree blindly.
  #|
  #|TASK MANAGEMENT:
  #|- Break down complex tasks into smaller todos.
  #|- Mark todos as completed immediately when done located at `$HOME/.jarvis/playground`.
  #|- Do not batch completions.

///|
/// Print colored Jarvis prefix
async fn print_jarvis_prefix() -> Unit {
  @stdio.stdout.write(COLOR_BOLD)
  @stdio.stdout.write(COLOR_CYAN)
  @stdio.stdout.write("Jarvis")
  @stdio.stdout.write(COLOR_RESET)
  @stdio.stdout.write(": ")
}

///|
/// Jarvis speaks - unified function for all Jarvis output
async fn jarvis_says(message : String) -> Unit {
  print_jarvis_prefix()
  println_async(message)
  newline_async()
}

///|
/// System error - shows system-level error message (red)
async fn system_error(message : String) -> Unit {
  newline_async()
  @stdio.stdout.write(COLOR_RED)
  @stdio.stdout.write("[ERROR] ")
  @stdio.stdout.write(COLOR_RESET)
  println_async(message)
}

///|
/// Tool execution log - shows which tool is being executed (green)
async fn tool_log(tool_name : String, content : String) -> Unit {
  @stdio.stdout.write(COLOR_GREEN)
  @stdio.stdout.write("[Tool] ")
  @stdio.stdout.write(COLOR_RESET)
  @stdio.stdout.write(COLOR_BOLD)
  @stdio.stdout.write(tool_name)
  @stdio.stdout.write(COLOR_RESET)
  @stdio.stdout.write("(")
  @stdio.stdout.write(content)
  @stdio.stdout.write(")")
  @stdio.stdout.write("\n\n")
}

///|
/// System info - shows system-level information (white)
async fn system_info(message : String) -> Unit {
  @stdio.stdout.write("[INFO] ")
  println_async(message)
}

///|
/// Print debug message (only when debug_mode is enabled, gray)
async fn system_debug(message : String) -> Unit {
  if debug_mode.val {
    @stdio.stdout.write(COLOR_GRAY)
    @stdio.stdout.write("[DEBUG] ")
    @stdio.stdout.write(COLOR_RESET)
    println_async(message)
  }
}

///|
async fn println_async(s : String) -> Unit {
  @stdio.stdout.write("\{s}\n")
}

///|
/// Print a newline
async fn newline_async() -> Unit {
  @stdio.stdout.write("\n")
}

///|
/// Print horizontal separator line
async fn print_separator() -> Unit {
  let size = window_size()
  ignore(size.row)
  let builder = StringBuilder::new()
  for i = 0; i < size.col; i = i + 1 {
    builder.write_string("─")
  }
  @stdio.stdout.write(COLOR_GRAY)
  println_async(builder.to_string())
  @stdio.stdout.write(COLOR_RESET)
}

///|
fn Config::new(base_url : String, auth_token : String) -> Config {
  { base_url, auth_token }
}

///|
fn Config::base_url(self : Config) -> String {
  self.base_url
}

///|
fn Config::auth_token(self : Config) -> String {
  self.auth_token
}

///|
/// Main entry point for Jarvis
suberror JarvisError {
  EnvVarNotSet(String)
  HttpError(String)
  StringViewError(String)
  ExitRequested
} derive(Show)

///|
async fn load_config() -> Config raise JarvisError {
  let env_vars = @sys.get_env_vars()
  let base_url = match env_vars.get("JARVIS_BASE_URL") {
    Some(v) => v
    None => raise EnvVarNotSet("JARVIS_BASE_URL")
  }
  let auth_token = match env_vars.get("JARVIS_AUTH_TOKEN") {
    Some(v) => v
    None => raise EnvVarNotSet("JARVIS_AUTH_TOKEN")
  }
  Config::new(base_url, auth_token)
}
