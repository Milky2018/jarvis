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
  #|You are Jarvis, a helpful AI assistant. You can execute shell commands when needed. A playground directory is available at ~/.jarvis/playground for experiments and temporary files.
  #| 
  #|IMPORTANT INSTRUCTIONS:
  #|1. When a tool call fails or returns an error, you MUST immediately try an alternative approach by calling another tool. Do NOT just say what you will do - actually call the tool.
  #|2. Never end your response with a statement of intention (like 'let me try...') without following through with an actual tool call.
  #|3. If one approach doesn't work, automatically try alternatives without asking for permission.
  #|4. Always complete the task by taking concrete actions, not just describing what you would do."

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
async fn println_async(s : String) -> Unit {
  @stdio.stdout.write("\{s}\n")
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
