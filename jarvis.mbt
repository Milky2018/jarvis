///| Configuration
/// Jarvis configuration loaded from environment variables
struct Config {
  base_url : String
  auth_token : String
} derive(Show)

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
  content : String
} derive(ToJson, FromJson)

fn Message::new(role : String, content : String) -> Message {
  { role, content }
}

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
} derive(ToJson)

fn ChatRequest::new(messages : Array[Message], model : String) -> ChatRequest {
  { messages, model, stream: false }
}

///| Response types
struct ChatResponseMessage {
  role : String
  content : String
} derive(FromJson)

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

fn ChatResponse::get_content(self : ChatResponse) -> String? {
  if self.choices.length() > 0 {
    Some(self.choices[0].message.content)
  } else {
    None
  }
}
///|
/// Main entry point for Jarvis
suberror JarvisError {
  EnvVarNotSet(String)
  HttpError(String)
  InvalidResponse(String)
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

///|
async fn send_chat_request(
  config : Config,
  messages : Array[Message],
) -> String raise JarvisError {
  // Parse URL to extract host and path
  let url = config.base_url()

  // Remove protocol prefix
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

  // Split host and path - convert to Array[String]
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

  // Build request JSON
  let request = ChatRequest::new(messages, "gpt-3.5-turbo")
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

  // Extract content
  match chat_response.get_content() {
    Some(content) => content
    None => raise InvalidResponse("No content in response")
  }
}

///|
async fn print(text : String) -> Unit {
  @stdio.stdout.write(text)
}

///|
async fn read_line() -> String {
  let mut result = ""
  let buf = FixedArray::make(1, b'\x00')
  while true {
    let n = @stdio.stdin.read(buf)
    if n == 0 {
      break // EOF
    }
    let byte = buf[0]
    if byte == b'\n' {
      break
    }
    result = result + Int::unsafe_to_char(byte.to_int()).to_string()
  }
  result
}

///|
async fn chat_loop(config : Config) -> Unit {
  let chat_history = ChatHistory::new()
  let command_history = CommandHistory::new(100)
  println(
    "Jarvis: Hello! I'm Jarvis, your AI assistant. How can I help you today?",
  )
  println("(Type 'exit' or 'quit' to end the conversation)")
  println("")
  while true {
    match readline_simple("> ", command_history) {
      Some(user_input) => {
        if user_input.is_empty() {
          continue
        }
        if user_input == "exit" || user_input == "quit" {
          println("Jarvis: Goodbye!")
          break
        }

        // Add user message to history
        let user_message = Message::new("user", user_input)
        chat_history.add(user_message)

        // Send request
        print("Jarvis: ")
        try {
          let response = send_chat_request(config, chat_history.messages)
          println(response)

          // Add assistant message to history
          let assistant_message = Message::new("assistant", response)
          chat_history.add(assistant_message)
        } catch {
          EnvVarNotSet(msg) =>
            println("Error: Environment variable not set: \{msg}")
          HttpError(msg) => println("Error: HTTP error: \{msg}")
          InvalidResponse(msg) => println("Error: Invalid response: \{msg}")
          JsonParseError(msg) => println("Error: JSON parse error: \{msg}")
          StringViewError(msg) => println("Error: String view error: \{msg}")
        }
        println("")
      }
      None => {
        println("\nJarvis: Goodbye!")
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
    InvalidResponse(msg) =>
      @stdio.stderr.write("Error: Invalid response: \{msg}\n")
    JsonParseError(msg) =>
      @stdio.stderr.write("Error: JSON parse error: \{msg}\n")
    StringViewError(msg) =>
      @stdio.stderr.write("Error: String view error: \{msg}\n")
    _ => @stdio.stderr.write("Error: Unknown error occurred\n")
  }
}
