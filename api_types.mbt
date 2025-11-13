/// API Request/Response
/// Request body for Claude API
struct ChatRequest {
  model : String
  messages : Array[Message]
  max_tokens : Int
  stream : Bool
  tools : Array[Tool]?
  system : String?
} derive(ToJson)

///|
fn ChatRequest::with_tools(
  messages : Array[Message],
  model : String,
  tools : Array[Tool],
) -> ChatRequest {
  // Extract system messages
  let mut system_content = ""
  let non_system_messages : Array[Message] = []
  for msg in messages {
    if msg.role == "system" {
      match msg.content {
        Some(content) => {
          if system_content.is_empty() == false {
            system_content = system_content + "\n\n"
          }
          system_content = system_content + content
        }
        None => ()
      }
    } else {
      non_system_messages.push(msg)
    }
  }
  let system_param = if system_content.is_empty() {
    None
  } else {
    Some(system_content)
  }
  {
    messages: non_system_messages,
    model,
    max_tokens: 4096,
    stream: false,
    tools: Some(tools),  // Claude API supports tools with input_schema format
    system: system_param,
  }
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
  input_tokens : Int
  output_tokens : Int
} derive(FromJson(fields(input_tokens(rename="input_tokens"), output_tokens(rename="output_tokens"))))

///|
struct ChatResponse {
  id : String
  type_ : String
  role : String
  content : Array[ContentBlock]
  model : String
  stop_reason : String?
  usage : ResponseUsage?
} derive(FromJson(fields(type_(rename="type"))))

///|
struct ContentBlock {
  type_ : String
  text : String?
  id : String?
  name : String?
  input : Json?
}

///|
impl @json.FromJson for ContentBlock with from_json(json, path) raise @json.JsonDecodeError {
  match json {
    Object(map) => {
      let type_ = match map.get("type") {
        Some(String(s)) => s
        _ =>
          raise @json.JsonDecodeError((path.add_key("type"), "expected string"))
      }
      let text = match map.get("text") {
        Some(String(s)) => Some(s)
        Some(Null) | None => None
        _ =>
          raise @json.JsonDecodeError(
            (path.add_key("text"), "expected string or null"),
          )
      }
      let id = match map.get("id") {
        Some(String(s)) => Some(s)
        Some(Null) | None => None
        _ => None
      }
      let name = match map.get("name") {
        Some(String(s)) => Some(s)
        Some(Null) | None => None
        _ => None
      }
      let input = match map.get("input") {
        Some(obj) => Some(obj)
        None => None
        _ => None
      }
      { type_, text, id, name, input }
    }
    _ => raise @json.JsonDecodeError((path, "expected object"))
  }
}

///|
/// Extract text content from Claude response
fn ChatResponse::get_text_content(self : ChatResponse) -> String? {
  if self.content.length() == 0 {
    return None
  }
  // Concatenate all text blocks
  let mut result = ""
  for block in self.content {
    if block.type_ == "text" {
      match block.text {
        Some(t) => result = result + t
        None => ()
      }
    }
  }
  if result.is_empty() {
    None
  } else {
    Some(result)
  }
}

///|
/// Extract tool uses from Claude response
fn ChatResponse::get_tool_uses(self : ChatResponse) -> Array[(String, String, Json)] {
  let tool_uses : Array[(String, String, Json)] = []
  for block in self.content {
    if block.type_ == "tool_use" {
      match (block.id, block.name, block.input) {
        (Some(id), Some(name), Some(input)) => tool_uses.push((id, name, input))
        _ => ()
      }
    }
  }
  tool_uses
}
