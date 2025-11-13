///| Configuration
/// Jarvis configuration loaded from environment variables
struct Config {
  base_url : String
  auth_token : String
} derive(Show)

///| ANSI Color codes
let color_cyan = "\u001b[36m"
let color_reset = "\u001b[0m"
let color_bold = "\u001b[1m"

///| Print colored Jarvis prefix
async fn print_jarvis_prefix() -> Unit {
  @stdio.stdout.write(color_bold + color_cyan + "Jarvis" + color_reset + ": ")
}

///| Print horizontal separator line
async fn print_separator() -> Unit {
  let size = window_size()
  let mut line = ""
  for i = 0; i < size.col; i = i + 1 {
    line = line + "─"
  }
  println(line)
}

fn Config::new(base_url : String, auth_token : String) -> Config {
  { base_url, auth_token }
}

fn Config::base_url(self : Config) -> String {
  self.base_url
}

fn Config::auth_token(self : Config) -> String {
  self.auth_token
}

///| Message types
/// Represents a chat message
struct Message {
  role : String
  content : String?
  tool_calls : Array[ToolCall]?
  tool_call_id : String?
  name : String?
} derive(ToJson, FromJson)

fn Message::new(role : String, content : String) -> Message {
  { role, content: Some(content), tool_calls: None, tool_call_id: None, name: None }
}

fn Message::tool(content : String, tool_call_id : String, name : String) -> Message {
  {
    role: "tool",
    content: Some(content),
    tool_calls: None,
    tool_call_id: Some(tool_call_id),
    name: Some(name)
  }
}

///| Tool call structures
struct ToolCall {
  id : String
  type_ : String
  function : FunctionCall
} derive(ToJson(fields(type_(rename="type"))), FromJson(fields(type_(rename="type"))))

struct FunctionCall {
  name : String
  arguments : String
} derive(ToJson, FromJson)

///| Tool definition structures
struct Tool {
  type_ : String
  function : FunctionDef
} derive(ToJson(fields(type_(rename="type"))))

struct FunctionDef {
  name : String
  description : String
  parameters : Json
} derive(ToJson)

///| Chat history
/// Manages conversation history
struct ChatHistory {
  messages : Array[Message]
}

fn ChatHistory::new() -> ChatHistory {
  { messages: [] }
}

fn ChatHistory::add(self : ChatHistory, message : Message) -> Unit {
  self.messages.push(message)
}

///| API Request/Response
/// Request body for LLM API
struct ChatRequest {
  model : String
  messages : Array[Message]
  stream : Bool
  tools : Array[Tool]?
} derive(ToJson)

fn ChatRequest::with_tools(
  messages : Array[Message],
  model : String,
  tools : Array[Tool]
) -> ChatRequest {
  { messages, model, stream: false, tools: Some(tools) }
}

///| Response types
struct ChatResponseMessage {
  role : String
  content : String?
  tool_calls : Array[ToolCall]?
}

impl @json.FromJson for ChatResponseMessage with from_json(json, path) raise @json.JsonDecodeError {
  match json {
    Object(map) => {
      let role = match map.get("role") {
        Some(String(s)) => s
        _ => raise @json.JsonDecodeError((path.add_key("role"), "expected string"))
      }

      let content = match map.get("content") {
        Some(Null) | None => None
        Some(String(s)) => Some(s)
        _ => raise @json.JsonDecodeError((path.add_key("content"), "expected string or null"))
      }

      let tool_calls = match map.get("tool_calls") {
        Some(Array(arr)) => {
          let calls : Array[ToolCall] = []
          for i = 0; i < arr.length(); i = i + 1 {
            calls.push(@json.from_json(arr[i], path=path.add_index(i)) catch { e => raise e })
          }
          Some(calls)
        }
        Some(Null) | None => None
        _ => raise @json.JsonDecodeError((path.add_key("tool_calls"), "expected array or null"))
      }

      ignore(role)
      { role, content, tool_calls }
    }
    _ => raise @json.JsonDecodeError((path, "expected object"))
  }
}

struct ChatResponseChoice {
  index : Int
  message : ChatResponseMessage
  finish_reason : String
} derive(FromJson)

struct ChatResponse {
  id : String
  object : String
  created : Int
  model : String
  choices : Array[ChatResponseChoice]
} derive(FromJson)
///|
/// Main entry point for Jarvis
suberror JarvisError {
  EnvVarNotSet(String)
  HttpError(String)
  JsonParseError(String)
  StringViewError(String)
}

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

///| Send chat request with tools support
async fn send_chat_request_with_tools(
  config : Config,
  messages : Array[Message],
  tools : Array[Tool],
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
  let request = ChatRequest::with_tools(messages, "gpt-3.5-turbo", tools)
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
    let error_body = try {
      client.read_all().text()
    } catch {
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
      let text = try {
        body.text()
      } catch {
        _ => "[Failed to read body text]"
      }
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

///| Tool execution
async fn execute_shell_command(command : String) -> String {
  try {
    // Use sh -c to execute the command
    let (exit_code, output) = @process.collect_output_merged("sh", ["-c", command])
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

async fn execute_tool(tool_call : ToolCall) -> String {
  match tool_call.function.name {
    "execute_command" => {
      // Parse arguments JSON
      let args_json = try {
        @json.parse(tool_call.function.arguments)
      } catch {
        e => return "Error: Failed to parse arguments: \{e}"
      }

      // Extract command from arguments
      match args_json {
        Object(map) => {
          match map.get("command") {
            Some(String(cmd)) => execute_shell_command(cmd)
            Some(_) => "Error: 'command' must be a string"
            None => "Error: Missing 'command' argument"
          }
        }
        _ => "Error: Arguments must be a JSON object"
      }
    }
    _ => "Error: Unknown tool '\{tool_call.function.name}'"
  }
}

fn get_available_tools() -> Array[Tool] {
  let params : Json = {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "description": "The shell command to execute"
      }
    },
    "required": ["command"]
  }

  [
    {
      type_: "function",
      function: {
        name: "execute_command",
        description: "Execute a shell command and return the output. Use this when you need to interact with the system, run programs, or access files.",
        parameters: params
      }
    }
  ]
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
        if user_input == "exit" || user_input == "quit" {
          print_jarvis_prefix()
          println("Goodbye!")
          break
        }

        // Add user message to history
        let user_message = Message::new("user", user_input)
        chat_history.add(user_message)

        // Tool calling loop
        try {
          let tools = get_available_tools()
          let mut max_iterations = 10  // Prevent infinite loops

          while max_iterations > 0 {
            max_iterations = max_iterations - 1

            // Send request with tools
            let response = send_chat_request_with_tools(config, chat_history.messages, tools)
            let { choices, id: _, object: _, created: _, model: _ } = response

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
              name: None
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
                  let tool_msg = Message::tool(result, tool_call.id, tool_call.function.name)
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
