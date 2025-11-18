///|
/// Configuration
/// Jarvis configuration loaded from environment variables
struct Config {
  base_url : String
  auth_token : String
} derive(Show)

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
/// Default model IDs for convenience
const MODEL_SONNET_4_5 : String = "claude-sonnet-4-5-20250929"

///|
const MODEL_HAIKU_4_5 : String = "claude-haiku-4-5-20251001"

///|
const MODEL_OPUS_4_1 : String = "claude-opus-4-1-20250805"

///|
/// Get all available models
fn available_models() -> Array[ModelInfo] {
  [
    {
      id: MODEL_SONNET_4_5,
      name: "Sonnet 4.5",
      description: "Claude Sonnet 4.5 (default, $3/$15 per 1M tokens)",
      input_price: 3.0,
      output_price: 15.0,
    },
    {
      id: MODEL_HAIKU_4_5,
      name: "Haiku 4.5",
      description: "Claude Haiku 4.5 (fastest, $0.8/$4 per 1M tokens)",
      input_price: 0.8,
      output_price: 4.0,
    },
    {
      id: MODEL_OPUS_4_1,
      name: "Opus 4.1",
      description: "Claude Opus 4.1 (most capable, $15/$75 per 1M tokens)",
      input_price: 15.0,
      output_price: 75.0,
    },
  ]
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
const MAX_RESPONSE_TOKENS : Int = 4096

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
  #|TOOLS:
  #|1. execute_command - Run shell commands (be cautious with destructive operations)
  #|2. read_file - Read file contents with line numbers (supports offset/limit)
  #|3. write_file - Write entire file (use ONLY for new files or complete rewrites)
  #|4. edit_file - Replace exact text (PREFERRED for small changes, old_string must be unique)
  #|5. grep - Search file contents by pattern
  #|6. glob - Find files by name patterns
  #|7. web_search - Search web for current information
  #|8. end_elaborate - REQUIRED: Call when task is fully complete with brief summary
  #|
  #|BEST PRACTICES:
  #|- Read files before editing them
  #|- Use edit_file for small changes, write_file for large ones
  #|- Verify paths and commands for safety
  #|- Only call end_elaborate when truly done

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
}

///|
/// Jarvis cries (error output) - shows error in red
async fn jarvis_cries(message : String) -> Unit {
  print_jarvis_prefix()
  @stdio.stdout.write(COLOR_RED)
  println_async(message)
  @stdio.stdout.write(COLOR_RESET)
}

///|
/// Tool execution log - shows which tool is being executed
/// Uses gray color to distinguish from Jarvis responses
async fn tool_log(message : String) -> Unit {
  @stdio.stdout.write(COLOR_GRAY)
  @stdio.stdout.write("[Tool] ")
  @stdio.stdout.write(COLOR_RESET)
  println_async(message)
}

///|
/// System notification - shows system-level information
/// Uses gray color and brackets to distinguish from Jarvis responses
async fn system_notify(message : String) -> Unit {
  @stdio.stdout.write(COLOR_GRAY)
  @stdio.stdout.write("[System] ")
  @stdio.stdout.write(COLOR_RESET)
  println_async(message)
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
  let mut line = ""
  for i = 0; i < size.col; i = i + 1 {
    line = line + "─"
  }
  @stdio.stdout.write(COLOR_GRAY)
  println_async(line)
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
  JsonParseError(String)
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
