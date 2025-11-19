///|
/// Content block for message content
struct ContentBlockItem {
  type_ : String
  text : String
} derive (
  ToJson(fields(type_(rename="type"))),
  FromJson(fields(type_(rename="type"))),
)

///|
/// Message types
/// Represents a chat message
struct Message {
  role : String
  content : Array[ContentBlockItem]?
  tool_calls : Array[ToolCall]?
  tool_call_id : String?
  name : String?
} derive(ToJson, FromJson)

///|
fn Message::new(role : String, content : String) -> Message {
  {
    role,
    content: Some([{ type_: "text", text: content }]),
    tool_calls: None,
    tool_call_id: None,
    name: None,
  }
}

///|
/// Extract text content from message (concatenate all text blocks)
fn Message::get_text(self : Message) -> String {
  match self.content {
    Some(blocks) => {
      let builder = StringBuilder::new()
      let mut first = true
      for block in blocks {
        if block.type_ == "text" {
          if !first {
            builder.write_string("\n")
          }
          builder.write_string(block.text)
          first = false
        }
      }
      builder.to_string()
    }
    None => ""
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
/// Tool definition structures for Claude API
struct Tool {
  name : String
  description : String
  input_schema : Json
  type_ : String? // Optional type for Anthropic built-in tools (e.g., "web_search_20250305")
  max_uses : Int? // Optional max_uses for built-in tools (e.g., web_search can be set to 5)
}

///|
/// Custom ToJson for Tool to handle optional type field
/// For Anthropic built-in tools (with type field), only include type, name, and optionally max_uses
impl ToJson for Tool with to_json(self) {
  match self.type_ {
    Some(type_val) => {
      // Anthropic built-in tools need type and name, optionally max_uses
      let mut tool_json : Json = { "type": type_val, "name": self.name }
      // Add max_uses if present
      match self.max_uses {
        Some(max) =>
          tool_json = { "type": type_val, "name": self.name, "max_uses": max }
        None => ()
      }
      tool_json
    }
    None =>
      {
        // Custom tools need name, description, and input_schema
        "name": self.name,
        "description": self.description,
        "input_schema": self.input_schema,
      }
  }
}

///|
/// Usage statistics for API calls
struct UsageStats {
  mut total_requests : Int
  mut total_input_tokens : Int
  mut total_output_tokens : Int
  cost_by_model : @hashmap.HashMap[String, Double] // Store costs per model
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
  total_tokens : Int,
  model : String,
) -> Unit {
  ignore(total_tokens)
  self.total_requests = self.total_requests + 1
  self.total_input_tokens = self.total_input_tokens + input_tokens
  self.total_output_tokens = self.total_output_tokens + output_tokens

  // Calculate cost based on model (prices per 1M tokens in USD)
  let (input_price, output_price) = match get_model_info(model) {
    Some(info) => (info.input_price, info.output_price)
    None => (3.0, 15.0) // Default to Sonnet pricing if model not found
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
