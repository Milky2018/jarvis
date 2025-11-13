///|
/// Configuration
/// Jarvis configuration loaded from environment variables
struct Config {
  base_url : String
  auth_token : String
} derive(Show)

///|
/// ANSI Color codes
let color_cyan = "\u001b[36m"

///|
let color_reset = "\u001b[0m"

///|
let color_bold = "\u001b[1m"

///|
/// Print colored Jarvis prefix
async fn print_jarvis_prefix() -> Unit {
  @stdio.stdout.write(color_bold + color_cyan + "Jarvis" + color_reset + ": ")
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
  println(line)
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
/// Message types
/// Represents a chat message
struct Message {
  role : String
  content : String?
  tool_calls : Array[ToolCall]?
  tool_call_id : String?
  name : String?
} derive(ToJson, FromJson)

///|
fn Message::new(role : String, content : String) -> Message {
  {
    role,
    content: Some(content),
    tool_calls: None,
    tool_call_id: None,
    name: None,
  }
}

///|
fn Message::tool(
  content : String,
  tool_call_id : String,
  name : String,
) -> Message {
  {
    role: "tool",
    content: Some(content),
    tool_calls: None,
    tool_call_id: Some(tool_call_id),
    name: Some(name),
  }
}

///|
/// Tool call structures
struct ToolCall {
  id : String
  type_ : String
  function : FunctionCall
} derive (
  ToJson(fields(type_(rename="type"))),
  FromJson(fields(type_(rename="type"))),
)

///|
struct FunctionCall {
  name : String
  arguments : String
} derive(ToJson, FromJson)

///|
/// Tool definition structures
struct Tool {
  type_ : String
  function : FunctionDef
} derive(ToJson(fields(type_(rename="type"))))

///|
struct FunctionDef {
  name : String
  description : String
  parameters : Json
} derive(ToJson)

///|
/// Usage statistics for API calls
struct UsageStats {
  mut total_requests : Int
  mut total_input_tokens : Int
  mut total_output_tokens : Int
  cost_by_model : @hashmap.HashMap[String, Double]  // Store costs per model
}

///|
fn UsageStats::new() -> UsageStats {
  {
    total_requests: 0,
    total_input_tokens: 0,
    total_output_tokens: 0,
    cost_by_model: @hashmap.new(),
  }
}

///|
fn UsageStats::add_request(
  self : UsageStats,
  input_tokens : Int,
  output_tokens : Int,
  model : String,
) -> Unit {
  self.total_requests = self.total_requests + 1
  self.total_input_tokens = self.total_input_tokens + input_tokens
  self.total_output_tokens = self.total_output_tokens + output_tokens

  // Calculate cost based on model (prices per 1M tokens in USD)
  let (input_price, output_price) = match model {
    "claude-sonnet-4-5-20250929" => (3.0, 15.0) // $3/$15 per 1M tokens
    "gpt-4o" => (2.5, 10.0) // $2.5/$10 per 1M tokens
    "gpt-4-turbo" => (10.0, 30.0) // $10/$30 per 1M tokens
    "gpt-4" => (30.0, 60.0) // $30/$60 per 1M tokens
    "gpt-3.5-turbo" => (0.5, 1.5) // $0.5/$1.5 per 1M tokens
    _ => (3.0, 15.0) // Default to Claude pricing
  }

  let cost = input_tokens.to_double() / 1000000.0 * input_price +
             output_tokens.to_double() / 1000000.0 * output_price

  // Update cost for this model
  let current_cost = self.cost_by_model.get(model).unwrap_or(0.0)
  self.cost_by_model.set(model, current_cost + cost)
}

///|
fn UsageStats::total_cost(self : UsageStats) -> Double {
  let mut total = 0.0
  self.cost_by_model.each(fn(_model, cost) { total = total + cost })
  total
}

///|
/// Chat history
/// Manages conversation history
struct ChatHistory {
  messages : Array[Message]
  max_context_tokens : Int // Maximum tokens for context (e.g., 4096)
  mut current_model : String // Current model to use
  usage_stats : UsageStats // Track API usage
}

///|
fn ChatHistory::new() -> ChatHistory {
  {
    messages: [],
    max_context_tokens: 4000,
    current_model: "claude-sonnet-4-5-20250929",
    usage_stats: UsageStats::new(),
  } // Leave some room for response
}

///|
fn ChatHistory::add(self : ChatHistory, message : Message) -> Unit {
  self.messages.push(message)
}

///|
fn ChatHistory::set_model(self : ChatHistory, model : String) -> Unit {
  self.current_model = model
}

///|
/// Estimate token count for a message (rough approximation: 1 token ≈ 4 chars)
fn estimate_tokens(message : Message) -> Int {
  let mut total = 0
  match message.content {
    Some(content) => total = total + content.length() / 4
    None => ()
  }
  // Add overhead for role, tool calls, etc.
  total + 10
}

///|
/// Estimate total tokens for a message array
fn estimate_total_tokens(messages : Array[Message]) -> Int {
  let mut total = 0
  for i = 0; i < messages.length(); i = i + 1 {
    total = total + estimate_tokens(messages[i])
  }
  total
}

///|
/// Summarize old messages into a single system message
async fn summarize_messages(
  config : Config,
  messages : Array[Message],
  model : String,
) -> String raise JarvisError {
  let summary_prompt = {
    let mut text = "Please summarize the following conversation history concisely, focusing on key points and context:\n\n"
    for msg in messages {
      match msg.content {
        Some(content) => text = text + msg.role + ": " + content + "\n\n"
        None => ()
      }
    }
    text + "Provide a brief summary in 2-3 sentences."
  }
  let summary_messages : Array[Message] = [Message::new("user", summary_prompt)]
  let tools = get_available_tools()
  let response = send_chat_request_with_tools(
    config, summary_messages, tools, model,
  )
  let { choices, usage: _, id: _, object: _, created: _, model: _ } = response
  if choices.length() == 0 {
    return "Previous conversation history (summary unavailable)"
  }
  let { message, index: _, finish_reason: _ } = choices[0]
  let { content, tool_calls: _, role: _ } = message
  match content {
    Some(text) => text
    None => "Previous conversation history (summary unavailable)"
  }
}

///|
/// Manage chat history: keep first message, summarize middle, keep recent 4 turns
///  Returns true if history was summarized
async fn ChatHistory::manage_history(
  self : ChatHistory,
  config : Config,
) -> Bool raise JarvisError {
  let total_tokens = estimate_total_tokens(self.messages)
  let max_tokens = self.max_context_tokens

  // If under 80% of max tokens, no need to manage
  if total_tokens < max_tokens * 8 / 10 {
    return false
  }

  // Count recent messages to keep (4 turns = 8 messages, but may include tool messages)
  let recent_keep = 8
  let messages_count = self.messages.length()
  if messages_count <= recent_keep + 1 {
    // Not enough messages to summarize
    return false
  }

  // Separate messages: first + middle + recent
  let first_message = self.messages[0]
  let recent_start = messages_count - recent_keep

  // Middle messages to summarize (skip first, keep recent)
  let middle_messages : Array[Message] = []
  for i = 1; i < recent_start; i = i + 1 {
    middle_messages.push(self.messages[i])
  }

  // If no middle messages, nothing to summarize
  if middle_messages.length() == 0 {
    return false
  }

  // Generate summary (no notification to avoid error type mismatch)
  let summary_text = summarize_messages(
    config,
    middle_messages,
    self.current_model,
  )
  let summary_message = Message::new(
    "system",
    "Previous conversation summary: " + summary_text,
  )

  // Rebuild messages array: first + summary + recent
  let new_messages : Array[Message] = [first_message, summary_message]
  for i = recent_start; i < messages_count; i = i + 1 {
    new_messages.push(self.messages[i])
  }

  // Replace messages (we need to clear and repopulate since we can't reassign)
  while self.messages.length() > 0 {
    ignore(self.messages.pop())
  }
  for msg in new_messages {
    self.messages.push(msg)
  }
  true // Indicate that summarization happened
}

///|
/// API Request/Response
/// Request body for LLM API
struct ChatRequest {
  model : String
  messages : Array[Message]
  stream : Bool
  tools : Array[Tool]?
} derive(ToJson)

///|
fn ChatRequest::with_tools(
  messages : Array[Message],
  model : String,
  tools : Array[Tool],
) -> ChatRequest {
  { messages, model, stream: false, tools: Some(tools) }
}

///|
/// Response types
struct ChatResponseMessage {
  role : String
  content : String?
  tool_calls : Array[ToolCall]?
}

///|
impl @json.FromJson for ChatResponseMessage with from_json(json, path) raise @json.JsonDecodeError {
  match json {
    Object(map) => {
      let role = match map.get("role") {
        Some(String(s)) => s
        _ =>
          raise @json.JsonDecodeError((path.add_key("role"), "expected string"))
      }
      let content = match map.get("content") {
        Some(Null) | None => None
        Some(String(s)) => Some(s)
        _ =>
          raise @json.JsonDecodeError(
            (path.add_key("content"), "expected string or null"),
          )
      }
      let tool_calls = match map.get("tool_calls") {
        Some(Array(arr)) => {
          let calls : Array[ToolCall] = []
          for i = 0; i < arr.length(); i = i + 1 {
            calls.push(
              @json.from_json(arr[i], path=path.add_index(i)) catch {
                e => raise e
              },
            )
          }
          Some(calls)
        }
        Some(Null) | None => None
        _ =>
          raise @json.JsonDecodeError(
            (path.add_key("tool_calls"), "expected array or null"),
          )
      }
      ignore(role)
      { role, content, tool_calls }
    }
    _ => raise @json.JsonDecodeError((path, "expected object"))
  }
}

///|
struct ChatResponseChoice {
  index : Int
  message : ChatResponseMessage
  finish_reason : String
} derive(FromJson)

///|
struct ResponseUsage {
  prompt_tokens : Int
  completion_tokens : Int
  total_tokens : Int
} derive(FromJson)

///|
struct ChatResponse {
  id : String
  object : String
  created : Int
  model : String
  choices : Array[ChatResponseChoice]
  usage : ResponseUsage?
} derive(FromJson)

///|
/// Main entry point for Jarvis
suberror JarvisError {
  EnvVarNotSet(String)
  HttpError(String)
  JsonParseError(String)
  StringViewError(String)
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

///|
/// Send chat request with tools support
async fn send_chat_request_with_tools(
  config : Config,
  messages : Array[Message],
  tools : Array[Tool],
  model : String,
) -> ChatResponse raise JarvisError {
  // Parse URL to extract host and path (same as send_chat_request)
  let url = config.base_url()
  let host_and_path : StringView = if url.has_prefix("https://") {
    url[8:] catch {
      IndexOutOfBounds(_) | InvalidIndex(_) =>
        raise StringViewError(
          "Invalid URL format when removing HTTPS prefix\nURL: \{url}",
        )
    }
  } else if url.has_prefix("http://") {
    url[7:] catch {
      IndexOutOfBounds(_) | InvalidIndex(_) =>
        raise StringViewError(
          "Invalid URL format when removing HTTP prefix\nURL: \{url}",
        )
    }
  } else {
    url[:]
  }
  let parts_view = host_and_path.split("/")
  let parts_array : Array[String] = []
  for part in parts_view {
    parts_array.push(part.to_string())
  }
  let host = parts_array[0]
  let path = if parts_array.length() > 1 {
    let mut p = ""
    for i = 1; i < parts_array.length(); i = i + 1 {
      p = p + "/" + parts_array[i]
    }
    if p.is_empty() {
      "/v1/chat/completions"
    } else {
      p
    }
  } else {
    "/v1/chat/completions"
  }

  // Build request JSON with tools
  let request = ChatRequest::with_tools(messages, model, tools)
  let json_body = request.to_json().stringify()

  // Create HTTP client
  let client = @http.Client::connect(host, headers={
    "Authorization": "Bearer \{config.auth_token()}",
  }) catch {
    e =>
      raise HttpError(
        "Failed to connect to host '\{host}': \{e}\nFull URL: \{url}",
      )
  }
  defer client.close()

  // Send POST request
  let response = client.post(path, json_body, extra_headers={
    "Content-Type": "application/json",
  }) catch {
    e =>
      raise HttpError(
        "Failed to send POST request to '\{host}\{path}': \{e}\nRequest body: \{json_body}",
      )
  }
  if response.code != 200 {
    let error_body = client.read_all().text() catch {
        _ => "[Failed to read error body]"
      }
    raise HttpError(
      "HTTP request failed with status: \{response.code}\nResponse body: \{error_body}",
    )
  }

  // Read response body
  let body = client.read_all() catch {
    e => raise HttpError("Failed to read response: \{e}")
  }

  // Parse JSON response
  let json_obj = body.json() catch {
    e => {
      let text = body.text() catch { _ => "[Failed to read body text]" }
      raise JsonParseError("Failed to parse JSON: \{e}\nResponse body: \{text}")
    }
  }
  let chat_response : ChatResponse = @json.from_json(json_obj) catch {
    @json.JsonDecodeError(e) => {
      let json_str = json_obj.stringify()
      raise JsonParseError(
        "Failed to decode response: \{e}\nJSON object: \{json_str}",
      )
    }
  }

  // Return full response (including tool_calls)
  chat_response
}

///|
/// Tool execution
async fn execute_shell_command(command : String) -> String {
  try {
    // Use sh -c to execute the command
    let (exit_code, output) = @process.collect_output_merged("sh", [
      "-c", command,
    ])
    let output_text = output.text()
    if exit_code == 0 {
      if output_text.is_empty() {
        "Command executed successfully (no output)"
      } else {
        output_text
      }
    } else {
      "Command failed with exit code \{exit_code}\nOutput:\n\{output_text}"
    }
  } catch {
    e => "Error executing command: \{e}"
  }
}

///|
async fn execute_tool(tool_call : ToolCall) -> String {
  match tool_call.function.name {
    "execute_command" => {
      // Parse arguments JSON
      let args_json = @json.parse(tool_call.function.arguments) catch {
        e => return "Error: Failed to parse arguments: \{e}"
      }

      // Extract command from arguments
      match args_json {
        Object(map) =>
          match map.get("command") {
            Some(String(cmd)) => execute_shell_command(cmd)
            Some(_) => "Error: 'command' must be a string"
            None => "Error: Missing 'command' argument"
          }
        _ => "Error: Arguments must be a JSON object"
      }
    }
    _ => "Error: Unknown tool '\{tool_call.function.name}'"
  }
}

///|
fn get_available_tools() -> Array[Tool] {
  let params : Json = {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "description": "The shell command to execute",
      },
    },
    "required": ["command"],
  }
  [
    {
      type_: "function",
      function: {
        name: "execute_command",
        description: "Execute a shell command and return the output. Use this when you need to interact with the system, run programs, or access files.",
        parameters: params,
      },
    },
  ]
}

///|
/// Handle special commands starting with ':'
///  Returns true if command was handled, false if it's a normal message
async fn handle_command(input : String, chat_history : ChatHistory) -> Bool {
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
      println("  claude-sonnet-4-5-20250929  - Claude Sonnet 4.5 (default)")
      println("  gpt-3.5-turbo               - Fast, cost-effective")
      println("  gpt-4                       - More capable, higher quality")
      println(
        "  gpt-4-turbo                 - GPT-4 with optimized performance",
      )
      println("  gpt-4o                      - Latest GPT-4 optimized model")
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
/// Execute tool calls in a loop until we get a final response
async fn handle_tool_calls(
  config : Config,
  chat_history : ChatHistory,
  tools : Array[Tool],
) -> Unit {
  let mut max_iterations = 10 // Prevent infinite loops
  try {
    while max_iterations > 0 {
      max_iterations = max_iterations - 1

      // Send request with tools
      let response = send_chat_request_with_tools(
        config,
        chat_history.messages,
        tools,
        chat_history.current_model,
      )
      let { choices, usage, id: _, object: _, created: _, model: _ } = response

      // Record usage statistics
      match usage {
        Some(u) =>
          chat_history.usage_stats.add_request(
            u.prompt_tokens,
            u.completion_tokens,
            chat_history.current_model,
          )
        None => ()
      }

      // Check if there are tool calls
      if choices.length() == 0 {
        print_jarvis_prefix()
        println("Error: Empty response from API")
        break
      }
      let { message, index: _, finish_reason: _ } = choices[0]
      let { content, tool_calls, role: _ } = message

      // Add assistant message to history (even if it has tool_calls)
      let assistant_msg = {
        role: "assistant",
        content,
        tool_calls,
        tool_call_id: None,
        name: None,
      }
      chat_history.add(assistant_msg)

      // Check if we have tool calls
      match tool_calls {
        Some(calls) if calls.length() > 0 => {
          // Execute each tool call
          for tool_call in calls {
            print_jarvis_prefix()
            println("Executing tool: \{tool_call.function.name}")
            let result = execute_tool(tool_call)

            // Add tool result to history
            let tool_msg = Message::tool(
              result,
              tool_call.id,
              tool_call.function.name,
            )
            chat_history.add(tool_msg)
          }
          // Continue loop to get final response
          continue
        }
        _ => {
          // No tool calls, display the content
          match content {
            Some(content) => {
              print_jarvis_prefix()
              println(content)
            }
            None => {
              print_jarvis_prefix()
              println("Error: No content in response")
            }
          }
          break
        }
      }
    }
    if max_iterations == 0 {
      print_jarvis_prefix()
      println("Warning: Maximum tool calling iterations reached")
    }
  } catch {
    EnvVarNotSet(msg) => {
      print_jarvis_prefix()
      println("Error: Environment variable not set: \{msg}")
    }
    HttpError(msg) => {
      print_jarvis_prefix()
      println("Error: HTTP error: \{msg}")
    }
    JsonParseError(msg) => {
      print_jarvis_prefix()
      println("Error: JSON parse error: \{msg}")
    }
    StringViewError(msg) => {
      print_jarvis_prefix()
      println("Error: String view error: \{msg}")
    }
    _ => {
      print_jarvis_prefix()
      println("Error: Unknown error occurred")
    }
  }
}

///|
/// Handle user input and generate response
async fn handle_user_input(
  config : Config,
  chat_history : ChatHistory,
  user_input : String,
) -> Unit {
  // Add user message to history
  let user_message = Message::new("user", user_input)
  chat_history.add(user_message)

  // Manage history before sending request
  try {
    let summarized = chat_history.manage_history(config)
    if summarized {
      print_jarvis_prefix()
      println("(Summarized old conversation history to manage context length)")
    }
  } catch {
    e => {
      // If history management fails, just log and continue
      print_jarvis_prefix()
      println("Warning: History management failed: \{e}")
    }
  }

  // Tool calling loop
  let tools = get_available_tools()
  handle_tool_calls(config, chat_history, tools)
}

///|
/// Check if input is an exit command
fn is_exit_command(input : String) -> Bool {
  input == "exit" ||
  input == "quit" ||
  input.has_prefix(":exit") ||
  input.has_prefix(":quit") ||
  input.has_prefix(":q")
}

///|
async fn chat_loop(config : Config) -> Unit {
  let chat_history = ChatHistory::new()
  let command_history = CommandHistory::new(100)
  print_jarvis_prefix()
  println("Hello! I'm Jarvis, your AI assistant. How can I help you today?")
  println("(Type 'exit' or 'quit' to end the conversation)")
  println("")
  while true {
    print_separator()
    match readline_simple("> ", command_history) {
      Some(user_input) => {
        print_separator()
        if user_input.is_empty() {
          continue
        }

        // Check for exit commands first
        if is_exit_command(user_input) {
          print_jarvis_prefix()
          println("Goodbye!")
          break
        }

        // Handle special commands
        if handle_command(user_input, chat_history) {
          println("")
          continue
        }

        // Handle normal user input
        handle_user_input(config, chat_history, user_input)
        println("")
      }
      None => {
        println("")
        print_jarvis_prefix()
        println("Goodbye!")
        break
      }
    }
  }
}

///|
async fn main {
  try {
    let config = load_config()
    chat_loop(config)
  } catch {
    EnvVarNotSet(msg) =>
      @stdio.stderr.write("Error: Environment variable not set: \{msg}\n")
    HttpError(msg) => @stdio.stderr.write("Error: HTTP error: \{msg}\n")
    JsonParseError(msg) =>
      @stdio.stderr.write("Error: JSON parse error: \{msg}\n")
    StringViewError(msg) =>
      @stdio.stderr.write("Error: String view error: \{msg}\n")
    _ => @stdio.stderr.write("Error: Unknown error occurred\n")
  }
}
