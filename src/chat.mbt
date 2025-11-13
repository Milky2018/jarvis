///|
/// Chat history
/// Manages conversation history
struct ChatHistory {
  messages : Array[Message]
  max_context_tokens : Int // Maximum tokens for context (e.g., 4096)
  mut current_model : String // Current model to use
  usage_stats : UsageStats // Track API usage
  mut current_file_number : Int // Current conversation file number
}

///|
fn ChatHistory::new() -> ChatHistory {
  {
    messages: [],
    max_context_tokens: 200000,
    current_model: "claude-sonnet-4-5-20250929",
    usage_stats: UsageStats::new(),
    current_file_number: 0, // Will be set when loading/creating conversation
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

  // Use native fs API to write file
  try {
    @fs.write_file(filename, json_str, create=0o644)
  } catch {
    e => {
      print_jarvis_prefix()
      println_async("Warning: Failed to save conversation: \{e}")
    }
  }
}

///|
/// Save conversation to numbered file
async fn ChatHistory::save_to_numbered_file(self : ChatHistory) -> Unit {
  if self.current_file_number == 0 {
    return // Not initialized yet
  }
  let path = get_conversation_file_path(self.current_file_number)
  self.save(path)
}

///|
/// Create a new conversation file after summarization
///|
/// Format conversation file number as 3-digit string
fn format_conv_number(num : Int) -> String {
  if num < 10 {
    "00\{num}"
  } else if num < 100 {
    "0\{num}"
  } else {
    num.to_string()
  }
}

///|
/// Create new conversation file after summarization and print notifications
async fn ChatHistory::create_new_file_after_summary(
  self : ChatHistory
) -> Unit {
  let old_number = self.current_file_number
  let old_num_str = format_conv_number(old_number)

  // Create new file with current messages
  let next_number = create_new_conversation_file(self.messages)
  self.current_file_number = next_number
  let num_str = format_conv_number(next_number)

  // Print notifications
  print_jarvis_prefix()
  println_async("Created new conversation file: conv_\{num_str}.json")
  if old_number > 0 {
    print_jarvis_prefix()
    println_async("(Previous conversation archived in conv_\{old_num_str}.json)")
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
    let short = if c.length() > 100 { c[:100].to_string() + "..." } else { c }
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
  println_async("Generating conversation title...")
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
  println_async("Generating summary...")
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
      println_async("Warning: Failed to generate conversation summary")
      return ("", "")
    }
  }
  let summary = match response.get_text_content() {
    Some(s) => s
    None => {
      print_jarvis_prefix()
      println_async("Warning: Empty summary content")
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
        max_context_tokens: 200000,
        current_model: model,
        usage_stats: UsageStats::new(),
        current_file_number: 0, // Will be set by caller
      })
    }
    _ => None
  }
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
