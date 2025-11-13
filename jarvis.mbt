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
/// Save conversation history to file (without summary)
async fn ChatHistory::save(self : ChatHistory, filename : String) -> Unit {
  let json_obj : Json = {
    "messages": self.messages.to_json(),
    "model": self.current_model,
  }
  let json_str = json_obj.stringify()

  // Write to file using shell command
  let (exit_code, _) = @process.collect_output_merged("sh", [
    "-c",
    "echo '\{json_str}' > '\{filename}'",
  ])
  if exit_code != 0 {
    print_jarvis_prefix()
    println("Warning: Failed to save conversation")
  }
}

///|
/// Generate a meaningful title for the conversation
async fn generate_conversation_title(
  chat_history : ChatHistory,
  config : Config,
) -> String {
  // Build conversation preview (first few messages)
  let mut preview = ""
  let limit = if chat_history.messages.length() > 6 {
    6
  } else {
    chat_history.messages.length()
  }
  for i = 0; i < limit; i = i + 1 {
    let msg = chat_history.messages[i]
    guard msg.content is Some(c) else { continue }
    let short = if c.length() > 100 {
      c[:100].to_string() + "..."
    } else {
      c
    }
    preview = preview + short + "\n"
  }
  let title_messages : Array[Message] = [
    {
      role: "user",
      content: Some(
        "请为以下对话生成一个简短的标题（不超过20个字，中文）。只返回标题本身，不要其他内容。\n\n对话内容：\n" +
        preview,
      ),
      tool_calls: None,
      tool_call_id: None,
      name: None,
    },
  ]
  let response = send_chat_request_with_tools(
    config,
    title_messages,
    [],
    chat_history.current_model,
  ) catch {
    _ => return "conversation"
  }
  match response.get_text_content() {
    Some(s) => {
      let trimmed = s[:].trim(chars=" \n\t\r\"\'").to_string()
      // Replace invalid filename characters
      trimmed
      .replace(old="/", new="_")
      .replace(old=":", new="_")
      .replace(old="\\", new="_")
    }
    None => "conversation"
  }
}

///|
/// Generate markdown summary of the conversation with meaningful title
async fn generate_summary_with_title(
  chat_history : ChatHistory,
  config : Config,
) -> (String, String) {
  // Generate title first
  print_jarvis_prefix()
  println("Generating conversation title...")
  let title = generate_conversation_title(chat_history, config)

  // Build conversation text
  let mut conversation_text = ""
  for msg in chat_history.messages {
    let role_text = match msg.role {
      "user" => "用户"
      "assistant" => "Jarvis"
      _ => msg.role
    }
    let content = match msg.content {
      Some(c) => if c.length() > 500 { c[:500].to_string() + "..." } else { c }
      None => "[无内容]"
    }
    conversation_text = conversation_text + "**\{role_text}**: \{content}\n\n"
  }

  // Create prompt for summarization
  print_jarvis_prefix()
  println("Generating summary...")
  let summary_messages : Array[Message] = [
    {
      role: "user",
      content: Some(
        "请总结以下对话内容，用 Markdown 格式输出。包括：\n1. 对话主题\n2. 关键要点（用bullet points）\n3. 重要决定或结论\n4. 需要记住的信息\n\n对话内容：\n\n" +
        conversation_text,
      ),
      tool_calls: None,
      tool_call_id: None,
      name: None,
    },
  ]

  // Call API to generate summary
  let response = send_chat_request_with_tools(
    config,
    summary_messages,
    [],
    chat_history.current_model,
  ) catch {
    _ => {
      print_jarvis_prefix()
      println("Warning: Failed to generate conversation summary")
      return ("", "")
    }
  }
  let summary = match response.get_text_content() {
    Some(s) => s
    None => {
      print_jarvis_prefix()
      println("Warning: Empty summary content")
      return ("", "")
    }
  }
  (title, summary)
}

///|
/// Load conversation history from file
async fn ChatHistory::load(filename : String) -> ChatHistory? {
  // Check if file exists and read it
  let (exit_code, output) = @process.collect_output_merged("sh", [
    "-c",
    "cat '\{filename}' 2>/dev/null",
  ])
  if exit_code != 0 {
    return None
  }
  let content = output.text()
  let json_obj = @json.parse(content) catch { _ => return None }
  match json_obj {
    Object(map) => {
      let messages : Array[Message] = match map.get("messages") {
        Some(arr) => @json.from_json(arr) catch { _ => return None }
        _ => return None
      }
      let model = match map.get("model") {
        Some(String(s)) => s
        _ => "claude-sonnet-4-5-20250929"
      }
      Some({
        messages,
        max_context_tokens: 4000,
        current_model: model,
        usage_stats: UsageStats::new(),
      })
    }
    _ => None
  }
}

///|
/// Get .jarvis directory path
fn get_jarvis_dir() -> String {
  let home = @sys.get_env_vars().get("HOME").unwrap_or(".")
  home + "/.jarvis"
}

///|
/// Ensure .jarvis directory exists
async fn ensure_jarvis_dir() -> Unit {
  let dir = get_jarvis_dir()
  let (_exit_code, _output) = @process.collect_output_merged("sh", [
    "-c",
    "mkdir -p '\{dir}'",
  ])

}

///|
/// Get conversation file path
fn get_conversation_path(name : String) -> String {
  get_jarvis_dir() + "/\{name}.json"
}

///|
/// Find the latest conversation that hasn't been summarized
async fn find_latest_unsummarized_conversation() -> String? {
  let dir = get_jarvis_dir()
  // List all JSON files sorted by modification time (newest first)
  let (exit_code, output) = @process.collect_output_merged("sh", [
    "-c",
    "cd '\{dir}' 2>/dev/null && for f in $(ls -1t *.json 2>/dev/null); do base=${f%.json}; if [ ! -f \"${base}.md\" ]; then echo \"$base\"; exit 0; fi; done",
  ])
  if exit_code != 0 {
    return None
  }
  let text = output.text()
  let trimmed = text[:].trim(chars=" \n\t\r").to_string()
  if trimmed.is_empty() {
    None
  } else {
    Some(trimmed)
  }
}

///|
/// Get all memory summaries from .jarvis directory
async fn get_all_memories() -> Array[(String, String)] {
  let dir = get_jarvis_dir()
  let (exit_code, output) = @process.collect_output_merged("sh", [
    "-c",
    "cd '\{dir}' 2>/dev/null && ls -1 *.md 2>/dev/null || true",
  ])
  if exit_code != 0 {
    return []
  }
  let text = output.text()
  let text_view = text[:].trim(chars=" \n\t\r")
  let text_str = text_view.to_string()
  if text_str.is_empty() {
    return []
  }
  let memories : Array[(String, String)] = []
  let lines : Array[String] = []
  for line in text_view.split("\n") {
    let trimmed_view = line.trim(chars=" \t\r")
    let filename = trimmed_view.to_string()
    if filename.is_empty() == false {
      lines.push(filename)
    }
  }

  // Read each file
  for filename in lines {
    let filepath = dir + "/" + filename
    let (read_code, content_output) = @process.collect_output_merged("sh", [
      "-c",
      "cat '\{filepath}' 2>/dev/null",
    ])
    if read_code == 0 {
      let content = content_output.text()
      memories.push((filename, content))
    }
  }
  memories
}

///|
/// Extract keywords from user input (simple approach: split by space and filter)
fn extract_keywords(text : String) -> Array[String] {
  // Define stop words set for better performance
  let stop_words = @hashset.from_array([
    "的",
    "了",
    "是",
    "我",
    "你",
    "在",
    "有",
    "和",
    "this",
    "that",
    "the",
    "and",
    "for",
  ])
  let keywords : Array[String] = []
  let text_lower = text.to_lower()

  // Split by space and filter
  for word_view in text_lower[:].split(" ") {
    let word = word_view.to_string()
    // Keep words that are >= 2 chars and not stop words
    if word.length() >= 2 && stop_words.contains(word) == false {
      keywords.push(word)
    }
  }
  keywords
}

///|
/// Check if content contains any of the keywords
fn contains_keywords(content : String, keywords : Array[String]) -> Bool {
  let content_lower = content.to_lower()
  for keyword in keywords {
    if content_lower.contains(keyword) {
      return true
    }
  }
  false
}

///|
/// Search for relevant memories based on user input (keyword-based filtering)
async fn search_relevant_memories(
  user_input : String,
  config : Config,
  model : String,
) -> String {
  let memories = get_all_memories()
  if memories.length() == 0 {
    return ""
  }

  // Extract keywords from user input
  let keywords = extract_keywords(user_input)
  if keywords.length() == 0 {
    return ""
  }

  // Filter memories by keyword matching
  let filtered_memories : Array[(String, String)] = []
  for i = 0; i < memories.length(); i = i + 1 {
    let (filename, content) = memories[i]
    if contains_keywords(content, keywords) {
      filtered_memories.push((filename, content))
    }
  }

  // If no matches, return early
  if filtered_memories.length() == 0 {
    return ""
  }

  // If only 1-2 matches, return them directly without AI
  if filtered_memories.length() <= 2 {
    let mut relevant_memories = ""
    for i = 0; i < filtered_memories.length(); i = i + 1 {
      let (filename, content) = filtered_memories[i]
      relevant_memories = relevant_memories +
        "\n\n--- 相关记忆 [\{filename}] ---\n" +
        content
    }
    return relevant_memories
  }

  // If more than 2 matches, use AI to rank them (limit to first 10)
  let mut memories_text = ""
  let limit = if filtered_memories.length() > 10 {
    10
  } else {
    filtered_memories.length()
  }
  for i = 0; i < limit; i = i + 1 {
    let (filename, content) = filtered_memories[i]
    // Limit each memory to 300 chars for the search
    let preview = if content.length() > 300 {
      content[:300].to_string() + "..."
    } else {
      content
    }
    memories_text = memories_text + "\{i + 1}. [\{filename}]\n\{preview}\n\n"
  }
  let search_messages : Array[Message] = [
    {
      role: "user",
      content: Some(
        "用户说：\{user_input}\n\n以下是可能相关的历史对话总结：\n\n\{memories_text}\n\n请选出最相关的1-3个对话编号（用逗号分隔，如\"1,3\"）。如果都不相关，请回复\"无\"。",
      ),
      tool_calls: None,
      tool_call_id: None,
      name: None,
    },
  ]
  let response = send_chat_request_with_tools(
    config,
    search_messages,
    [],
    model,
  ) catch {
    _ => return ""
  }
  let relevant_indices = match response.get_text_content() {
    Some(s) => s
    None => return ""
  }
  if relevant_indices.contains("无") {
    return ""
  }
  let trimmed_indices = relevant_indices[:].trim(chars=" \n\t\r").to_string()
  if trimmed_indices.is_empty() {
    return ""
  }

  // Parse the indices and collect relevant memories
  let mut relevant_memories = ""
  let indices_view = relevant_indices[:].trim(chars=" \n\t\r")
  for part in indices_view.split(",") {
    let num_str = part.trim(chars=" \t\r\n").to_string()
    let idx = match num_str {
      "1" => 1
      "2" => 2
      "3" => 3
      "4" => 4
      "5" => 5
      "6" => 6
      "7" => 7
      "8" => 8
      "9" => 9
      "10" => 10
      _ => 0
    }
    if idx > 0 && idx <= limit {
      let (filename, content) = filtered_memories[idx - 1]
      relevant_memories = relevant_memories +
        "\n\n--- 相关记忆 [\{filename}] ---\n" +
        content
    }
  }
  relevant_memories
}

///|
/// Estimate token count for a message (rough approximation: 1 token ≈ 4 chars)
fn estimate_tokens(message : Message) -> Int {
  let mut total = 0
  guard message.content is Some(content) else { return 10 }
  total = total + content.length() / 4
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
      guard msg.content is Some(content) else { continue }
      text = text + msg.role + ": " + content + "\n\n"
    }
    text + "Provide a brief summary in 2-3 sentences."
  }
  let summary_messages : Array[Message] = [Message::new("user", summary_prompt)]
  let tools = get_available_tools()
  let response = send_chat_request_with_tools(
    config, summary_messages, tools, model,
  )
  match response.get_text_content() {
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
      "/v1/messages"
    } else {
      p
    }
  } else {
    "/v1/messages"
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
/// Send streaming chat request (outputs content in real-time)
async fn send_streaming_chat_request(
  config : Config,
  messages : Array[Message],
  tools : Array[Tool],
  model : String,
) -> ChatResponse raise JarvisError {
  // Parse URL
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
      "/v1/messages"
    } else {
      p
    }
  } else {
    "/v1/messages"
  }

  // Build request JSON with streaming enabled
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
  let request_with_stream : Json = if system_content.is_empty() {
    {
      "model": model,
      "messages": non_system_messages.to_json(),
      "max_tokens": 4096,
      "stream": true,
    }
  } else {
    {
      "model": model,
      "messages": non_system_messages.to_json(),
      "max_tokens": 4096,
      "stream": true,
      "system": system_content,
    }
  }
  let json_body = request_with_stream.stringify()

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

  // Read streaming response (SSE format)
  // Note: read_all() waits for complete response, but we output chunks as we parse them
  let mut full_content = ""
  let mut finish_reason = ""
  let body_text = client.read_all().text() catch {
      e => raise HttpError("Failed to read response: \{e}")
    }

  // Parse SSE format and output chunks
  let lines : Array[String] = []
  for line_view in body_text[:].split("\n") {
    lines.push(line_view.to_string())
  }
  for line in lines {
    if line.has_prefix("data: ") {
      let json_str_view = line[6:] catch { _ => continue }
      let json_str = json_str_view.to_string()
      let trimmed = json_str[:].trim(chars=" \t\r\n").to_string()
      if trimmed == "[DONE]" {
        break
      }
      let chunk_json = @json.parse(json_str) catch { _ => continue }
      match chunk_json {
        Object(map) =>
          match map.get("choices") {
            Some(Array(choices)) if choices.length() > 0 =>
              match choices[0] {
                Object(choice_map) => {
                  match choice_map.get("delta") {
                    Some(Object(delta_map)) =>
                      match delta_map.get("content") {
                        Some(String(content)) => {
                          full_content = full_content + content
                          // Output immediately after parsing (ignore write errors)
                          let _ = @stdio.stdout.write(content) catch { _ => () }

                        }
                        _ => ()
                      }
                    _ => ()
                  }
                  match choice_map.get("finish_reason") {
                    Some(String(reason)) => finish_reason = reason
                    _ => ()
                  }
                }
                _ => ()
              }
            _ => ()
          }
        _ => ()
      }
    }
  }

  // Construct ChatResponse from accumulated data (Claude format)
  let content_blocks : Array[ContentBlock] = [
    { type_: "text", text: Some(full_content), id: None, name: None, input: None },
  ]
  {
    id: "",
    type_: "message",
    role: "assistant",
    content: content_blocks,
    model,
    stop_reason: Some(finish_reason),
    usage: None,
  }
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
/// Execute tool with Claude API format (takes tool name and input JSON directly)
async fn execute_tool_claude(tool_name : String, input : Json) -> String {
  match tool_name {
    "execute_command" => {
      // Extract command from input JSON
      match input {
        Object(map) =>
          match map.get("command") {
            Some(String(cmd)) => {
              print_jarvis_prefix()
              println("Executing: \{cmd}")
              execute_shell_command(cmd)
            }
            Some(_) => "Error: 'command' must be a string"
            None => "Error: Missing 'command' argument"
          }
        _ => "Error: Input must be a JSON object"
      }
    }
    _ => "Error: Unknown tool '\{tool_name}'"
  }
}

///|
fn get_available_tools() -> Array[Tool] {
  let input_schema : Json = {
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
      name: "execute_command",
      description: "Execute a shell command and return the output. Use this when you need to interact with the system, run programs, or access files.",
      input_schema,
    },
  ]
}

///|
/// Handle special commands starting with ':'
///  Returns true if command was handled, false if it's a normal message
async fn handle_command(
  input : String,
  chat_history : ChatHistory,
  config : Config,
) -> Bool {
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
      println("  :summarize          - Summarize and save current conversation")
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
      println("  claude-sonnet-4-5-20250929   - Claude Sonnet 4.5 (default, $3/$15 per 1M tokens)")
      println("  claude-haiku-4-5-20251001    - Claude Haiku 4.5 (fastest, $0.8/$4 per 1M tokens)")
      println("  claude-opus-4-1-20250805     - Claude Opus 4.1 (most capable, $15/$75 per 1M tokens)")
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
    "summarize" | "sum" => {
      if chat_history.messages.length() == 0 {
        print_jarvis_prefix()
        println("No messages to summarize")
        return true
      }
      print_jarvis_prefix()
      println("Summarizing conversation...")
      let (title, summary) = generate_summary_with_title(chat_history, config)
      if title.is_empty() || summary.is_empty() {
        print_jarvis_prefix()
        println("Failed to generate summary")
        return true
      }
      // Save JSON with title as filename
      let json_filename = get_conversation_path(title)
      chat_history.save(json_filename)
      // Save markdown summary
      let md_filename = get_jarvis_dir() + "/" + title + ".md"
      let escaped_summary = summary.replace(old="'", new="'\\''")
      let (exit_code, _) = @process.collect_output_merged("sh", [
        "-c",
        "echo '\{escaped_summary}' > '\{md_filename}'",
      ])
      if exit_code == 0 {
        print_jarvis_prefix()
        println("Conversation summarized and saved as: \{title}")
      } else {
        print_jarvis_prefix()
        println("Warning: Failed to save summary file")
      }
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
  let mut first_request = true // Use streaming for first request only
  let mut used_streaming = false // Track if we used streaming
  try {
    while max_iterations > 0 {
      max_iterations = max_iterations - 1

      // Send request (use streaming for first request)
      let response = if first_request && tools.length() > 0 {
        // First request with tools: use non-streaming to check for tool calls
        send_chat_request_with_tools(
          config,
          chat_history.messages,
          tools,
          chat_history.current_model,
        )
      } else if first_request {
        // First request without tools: use streaming
        print_jarvis_prefix()
        used_streaming = true
        let resp = send_streaming_chat_request(
          config,
          chat_history.messages,
          tools,
          chat_history.current_model,
        )
        println("") // Add newline after streaming
        resp
      } else {
        // Subsequent requests: non-streaming
        send_chat_request_with_tools(
          config,
          chat_history.messages,
          tools,
          chat_history.current_model,
        )
      }
      first_request = false

      // Record usage statistics
      match response.usage {
        Some(u) =>
          chat_history.usage_stats.add_request(
            u.input_tokens,
            u.output_tokens,
            u.input_tokens + u.output_tokens,
            chat_history.current_model,
          )
        None => ()
      }

      // Extract text content and tool uses from response
      let content_text = response.get_text_content()
      let tool_uses = response.get_tool_uses()

      // Display text content if present and not using streaming
      if tool_uses.length() == 0 {
        match content_text {
          Some(content_str) =>
            if used_streaming == false {
              print_jarvis_prefix()
              println(content_str)
            }
          None =>
            if used_streaming == false {
              print_jarvis_prefix()
              println("Error: No content in response")
            }
        }
        // No tool calls, add message to history and break
        let assistant_msg = {
          role: "assistant",
          content: content_text,
          tool_calls: None,
          tool_call_id: None,
          name: None,
        }
        chat_history.add(assistant_msg)
        break
      }

      // We have tool calls to execute
      // First, display any text content
      match content_text {
        Some(content_str) =>
          if content_str.is_empty() == false {
            print_jarvis_prefix()
            println(content_str)
          }
        None => ()
      }

      // Build assistant message with the full response for history
      // Note: We store the text content, Claude API requires full conversation history
      let assistant_msg = {
        role: "assistant",
        content: content_text,
        tool_calls: None,
        tool_call_id: None,
        name: None,
      }
      chat_history.add(assistant_msg)

      // Execute each tool and collect results
      let tool_results : Array[Json] = []
      for i = 0; i < tool_uses.length(); i = i + 1 {
        let (tool_id, tool_name, tool_input) = tool_uses[i]
        let result = execute_tool_claude(tool_name, tool_input)

        // Create tool_result content block
        let tool_result : Json = {
          "type": "tool_result",
          "tool_use_id": tool_id,
          "content": result,
        }
        tool_results.push(tool_result)
      }

      // Send tool results back as a user message
      // Claude API expects tool results as plain string for now
      // Ideally should be content blocks, but Message structure needs updating
      let mut results_text = ""
      for i = 0; i < tool_uses.length(); i = i + 1 {
        let (tool_id, tool_name, _) = tool_uses[i]
        let result_json = tool_results[i]
        // Extract the content from tool_result
        match result_json {
          Object(map) =>
            match map.get("content") {
              Some(String(content)) => {
                if i > 0 {
                  results_text = results_text + "\n\n"
                }
                results_text = results_text +
                  "Tool: \{tool_name} (ID: \{tool_id})\nResult: \{content}"
              }
              _ => ()
            }
          _ => ()
        }
      }
      let user_msg_with_results = {
        role: "user",
        content: Some(results_text),
        tool_calls: None,
        tool_call_id: None,
        name: None,
      }
      chat_history.add(user_msg_with_results)

      // Continue loop to get final response after tool execution
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
  // Search for relevant memories before processing
  let relevant_memories = search_relevant_memories(
    user_input,
    config,
    chat_history.current_model,
  )

  // If we found relevant memories, inject them as a system message
  if relevant_memories.is_empty() == false {
    print_jarvis_prefix()
    println("(Found relevant memories from past conversations)")
    let memory_message = Message::new(
      "system",
      "以下是与当前话题相关的历史记忆：" + relevant_memories,
    )
    chat_history.add(memory_message)
  }

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
  // Ensure .jarvis directory exists
  ensure_jarvis_dir()

  // Try to load the latest unsummarized conversation
  let chat_history = match find_latest_unsummarized_conversation() {
    Some(conversation_name) => {
      let path = get_conversation_path(conversation_name)
      match ChatHistory::load(path) {
        Some(loaded) => {
          print_jarvis_prefix()
          println("Continuing from previous conversation: \{conversation_name}")
          loaded
        }
        None => {
          print_jarvis_prefix()
          println("Failed to load previous conversation, starting new one")
          ChatHistory::new()
        }
      }
    }
    None => ChatHistory::new()
  }
  let command_history = CommandHistory::new(100)
  println("")
  print_jarvis_prefix()
  println("Hello! I'm Jarvis, your AI assistant. How can I help you today?")
  println("(Type 'exit' or 'quit' to end the conversation)")
  println("")
  let mut should_save = false
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
          should_save = true
          print_jarvis_prefix()
          println("Goodbye!")
          break
        }

        // Handle special commands
        if handle_command(user_input, chat_history, config) {
          println("")
          continue
        }

        // Handle normal user input
        should_save = true
        handle_user_input(config, chat_history, user_input)
        println("")
      }
      None => {
        should_save = true
        println("")
        print_jarvis_prefix()
        println("Goodbye!")
        break
      }
    }
  }

  // Save conversation on exit if there were messages (without summary)
  if should_save && chat_history.messages.length() > 0 {
    // Generate timestamp-based filename
    let (exit_code, output) = @process.collect_output_merged("sh", [
      "-c", "date +%Y%m%d_%H%M%S",
    ])
    let timestamp = if exit_code == 0 {
      output.text()[:].trim(chars=" \n\t\r").to_string()
    } else {
      "conversation"
    }
    let filename = get_conversation_path(timestamp)
    chat_history.save(filename)
    print_jarvis_prefix()
    println("Conversation saved (use :summarize to generate summary)")
  }
}

///|
/// Execute a single prompt and exit (for -e flag)
async fn execute_prompt(config : Config, prompt : String) -> Unit {
  ensure_jarvis_dir()
  let chat_history = ChatHistory::new()

  print_jarvis_prefix()
  println("Processing: \{prompt}")
  println("")

  handle_user_input(config, chat_history, prompt)
}

///|
async fn main {
  // Parse command line arguments
  let args = @sys.get_cli_args()

  // Simple argument parsing: check for -e flag
  let execute_mode = args.length() >= 2 && (args[1] == "-e" || args[1] == "--execute")
  let prompt = if execute_mode && args.length() >= 3 {
    Some(args[2])
  } else {
    None
  }

  try {
    let config = load_config()

    // Check if -e flag is used
    match prompt {
      Some(p) => execute_prompt(config, p)
      None => {
        if execute_mode {
          @stdio.stderr.write("Error: -e flag requires a prompt argument\n")
          @stdio.stderr.write("Usage: jarvis -e \"<prompt>\"\n")
        } else {
          chat_loop(config)
        }
      }
    }
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
