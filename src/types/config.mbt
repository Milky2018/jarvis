///|
/// Configuration
pub(all) struct Config {
  base_url : String
  auth_token : String
} derive(Show)

///|
pub fn Config::new(base_url : String, auth_token : String) -> Config {
  { base_url, auth_token }
}

///|
pub fn Config::base_url(self : Config) -> String {
  self.base_url
}

///|
pub fn Config::auth_token(self : Config) -> String {
  self.auth_token
}

///|
/// Global debug flag
pub let debug_mode : Ref[Bool] = { val: false }

///|
/// Color constants
pub const COLOR_CYAN : String = "\u001b[36m"

///|
pub const COLOR_RESET : String = "\u001b[0m"

///|
pub const COLOR_BOLD : String = "\u001b[1m"

///|
pub const COLOR_RED : String = "\u001b[31m"

///|
pub const COLOR_GREEN : String = "\u001b[32m"

///|
pub const COLOR_GRAY : String = "\u001b[38;2;90;90;90m"

///|
/// Summarization configuration
pub const SUMMARIZE_KEEP_RECENT : Int = 8

///|
pub const SUMMARIZE_THRESHOLD_PERCENT : Int = 80

///|
pub const MAX_SUMMARY_TOKENS : Int = 40000

///|
/// Model information
pub(all) struct ModelInfo {
  id : String
  name : String
  description : String
  input_price : Double
  output_price : Double
}

///|
pub fn available_models() -> Array[ModelInfo] {
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
pub fn default_model() -> String {
  available_models()[0].id
}

///|
pub fn default_petite_model() -> String {
  available_models()[1].id
}

///|
pub fn get_model_info(model_id : String) -> ModelInfo? {
  for model in available_models() {
    if model.id == model_id {
      return Some(model)
    }
  }
  None
}

///|
/// API configuration
pub const MAX_CONTEXT_TOKENS : Int = 200000

///|
pub const MAX_RESPONSE_TOKENS : Int = 32000

///|
pub const MAX_TOOL_ITERATIONS : Int = 200

///|
pub const MAX_PLAY_ITERATIONS : Int = 100

///|
pub const DEFAULT_PLAY_BUDGET : Double = 10.0

///|
/// System prompt for Jarvis
pub const SYSTEM_PROMPT : String =
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
/// Error types
pub(all) suberror JarvisError {
  EnvVarNotSet(String)
  HttpError(String)
  StringViewError(String)
  ExitRequested
} derive(Show)

///|
/// Signal types for control flow
pub(all) suberror JarvisSignal {
  ActionFinished
  PlayModeEnded
}

///|
/// Load configuration from environment variables
pub fn load_config() -> Config raise JarvisError {
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
