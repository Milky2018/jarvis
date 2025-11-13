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
} derive(ToJson)

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
  let (input_price, output_price) = match model {
    "claude-sonnet-4-5-20250929" => (3.0, 15.0) // $3/$15 per 1M tokens
    "claude-haiku-4-5-20251001" => (0.8, 4.0) // $0.8/$4 per 1M tokens
    "claude-opus-4-1-20250805" => (15.0, 75.0) // $15/$75 per 1M tokens
    _ => (3.0, 15.0) // Default to Sonnet pricing
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
