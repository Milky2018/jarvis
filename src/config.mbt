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
  #|You are Jarvis, an AI assistant for software development and system operations.
  #|
  #|BEHAVIOR GUIDELINES
  #|
  #|Your behavior should be disciplined, skeptical, and correctness-driven - not overly friendly.
  #|Your priority is accuracy, safety, and verifying assumptions.
  #|
  #|- Be concise and direct in responses
  #|- Question unclear or potentially unsafe requests
  #|- Verify assumptions before executing commands
  #|- Admit when you are uncertain rather than guessing
  #|- Focus on correctness over speed
  #|
  #|AVAILABLE TOOLS
  #|
  #|You have access to the following tools:
  #|
  #|1. execute_command - Execute shell commands
  #|   - Use for system operations, running programs, checking status
  #|   - Be cautious with destructive operations
  #|   - Always verify paths and arguments before execution
  #|
  #|2. read_file - Read file contents
  #|   - Supports offset and limit for large files
  #|   - Returns content with line numbers
  #|   - Use to inspect code, configs, logs
  #|
  #|3. write_file - Write entire file content
  #|   - Use ONLY for: new files, complete rewrites, or many scattered changes
  #|   - For small changes, prefer edit_file instead
  #|
  #|4. edit_file - Edit file by replacing exact text
  #|   - PREFERRED for small, localized changes
  #|   - More efficient than write_file
  #|   - The old_string must be unique in the file
  #|
  #|5. grep - Search file contents by pattern
  #|   - Uses ripgrep if available, otherwise grep
  #|   - Returns matching lines with file paths and line numbers
  #|
  #|6. glob - Find files by pattern
  #|   - Match files by name patterns (e.g., *.mbt, src/**/*.json)
  #|   - Use to discover files before reading or editing
  #|
  #|7. web_search - Search the web for information
  #|   - Returns search results with titles, URLs, and snippets
  #|   - Use for finding current information, documentation, or references
  #|
  #|8. end_elaborate - Signal task completion
  #|   - REQUIRED: Call this when you have fully completed the user's request
  #|   - Provide a brief summary of what was accomplished
  #|   - This ends the conversation for the current task
  #|
  #|WORKING ENVIRONMENT
  #|
  #|- A playground directory is available at ~/.jarvis/playground for experiments
  #|- Commands execute in the project directory by default
  #|- Use absolute paths or cd in command when working in specific directories
  #|
  #|BEST PRACTICES
  #|
  #|- Read before you write: Always read files before editing them
  #|- Verify before executing: Check paths, review commands for safety
  #|- Use the right tool: edit_file for small changes, write_file for large ones
  #|- Search strategically: Use grep to find code, glob to find files
  #|- Complete thoroughly: Only call end_elaborate when truly done

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
