///|
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
      if msg.content is Some(content) {
        if !system_content.is_empty() {
          system_content = system_content + "\n\n"
        }
        system_content = system_content + content
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
    tools: Some(tools), // Claude API supports tools with input_schema format
    system: system_param,
  }
}

///|
struct ResponseUsage {
  input_tokens : Int
  output_tokens : Int
} derive (
  FromJson(
    fields(
      input_tokens(rename="input_tokens"),
      output_tokens(rename="output_tokens"),
    ),
  ),
)

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
} derive(FromJson(fields(type_(rename="type"))))

///|
/// Extract text content from Claude response
fn ChatResponse::get_text_content(self : ChatResponse) -> String? {
  if self.content.length() == 0 {
    return None
  }
  // Concatenate all text blocks
  let mut result = ""
  for block in self.content {
    if block.type_ == "text" && block.text is Some(t) {
      result = result + t
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
fn ChatResponse::get_tool_uses(
  self : ChatResponse,
) -> Array[(String, String, Json)] {
  ignore(self.id)
  ignore(self.model)
  ignore(self.role)
  ignore(self.stop_reason)
  ignore(self.type_)
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
