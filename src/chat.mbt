///|
/// Chat history
/// Manages conversation history
struct ChatHistory {
  messages : Array[Message]
  max_context_tokens : Int // Maximum tokens for context (e.g., 32000)
  mut current_model : String // Current model to use
  mut petite_model : String // Petite model for summaries and titles
  usage_stats : UsageStats // Track API usage
  mut current_file_number : Int // Current conversation file number
  mut last_context_tokens : Int // Last accurate input_tokens from API (0 if not available)
}

///|
fn ChatHistory::new() -> ChatHistory {
  {
    messages: [],
    max_context_tokens: MAX_CONTEXT_TOKENS,
    current_model: default_model(),
    petite_model: default_petite_model(),
    usage_stats: UsageStats::new(),
    current_file_number: 0, // Will be set when loading/creating conversation
    last_context_tokens: 0, // Will be updated after first API call
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
    "last_context_tokens": self.last_context_tokens,
  }
  let json_str = json_obj.stringify()

  // Use native fs API to write file
  @fs.write_file(filename, json_str, create=0o644) catch {
    e => system_error("Failed to save conversation: \{e}")
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
async fn ChatHistory::create_new_file_after_summary(self : ChatHistory) -> Unit {
  let old_number = self.current_file_number
  let old_num_str = format_conv_number(old_number)

  // Create new file with current messages
  let next_number = create_new_conversation_file(
    self.messages,
    self.current_model,
    self.last_context_tokens,
  )
  self.current_file_number = next_number
  let num_str = format_conv_number(next_number)

  // Print notifications
  system_info("Created new conversation file: conv_\{num_str}.json")
  if old_number > 0 {
    system_info("(Previous conversation archived in conv_\{old_num_str}.json)")
  }
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
        _ => default_model()
      }
      let last_context_tokens = match map.get("last_context_tokens") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0 // Old files may not have this field
      }
      Some({
        messages,
        max_context_tokens: MAX_CONTEXT_TOKENS,
        current_model: model,
        petite_model: default_petite_model(),
        usage_stats: UsageStats::new(),
        current_file_number: 0, // Will be set by caller
        last_context_tokens,
      })
    }
    _ => None
  }
}

///|
/// Print token usage status with color coding
async fn ChatHistory::print_token_usage(self : ChatHistory) -> Unit {
  // Use accurate token count from last API call (persisted in conversation file)
  let total = self.last_context_tokens
  let percent = total * 100 / self.max_context_tokens

  // Color code based on usage
  let color = if percent >= SUMMARIZE_THRESHOLD_PERCENT {
    "\u{001b}[31m" // Red for >= threshold
  } else if percent >= 30 {
    "\u{001b}[33m" // Yellow for >= 30%
  } else {
    "\u{001b}[32m" // Green for < 30%
  }
  let reset = "\u{001b}[0m"
  @stdio.stdout.write(
    "[\{color}\{total}/\{self.max_context_tokens} tokens (\{percent}%)\{reset}]\n",
  )
}

///|
/// Summarize old messages into a single system message
async fn summarize_messages(
  config : Config,
  messages : Array[Message],
  model : String,
) -> String {
  // Calculate approximate token limit for the summary (40k tokens ≈ 160k characters)
  let max_summary_chars = MAX_SUMMARY_TOKENS * 4
  let summary_prompt = {
    let builder = StringBuilder::new()
    builder.write_string(
      "Please provide a comprehensive summary of the following conversation history. Focus on key points, context, decisions made, and important details. You have up to \{MAX_SUMMARY_TOKENS} tokens for your summary.\n\n",
    )
    for msg in messages {
      let content = msg.get_text()
      if content.is_empty() {
        continue
      }
      builder.write_string(msg.role)
      builder.write_string(": ")
      builder.write_string(content)
      builder.write_string("\n\n")
    }
    builder.write_string(
      "Provide a detailed summary (maximum \{MAX_SUMMARY_TOKENS} tokens).",
    )
    builder.to_string()
  }
  let summary_messages : Array[Message] = [Message::new("user", summary_prompt)]
  // Use non-streaming without tools for summary (we only need text output, no need to show progress)
  let response = send_chat_request_non_streaming(
    config,
    summary_messages,
    [],
    model,
  )
  match response.get_text_content() {
    Some(text) =>
      // Truncate if exceeds the character limit
      if text.length() > max_summary_chars {
        let truncated = text[:max_summary_chars].to_string() catch { _ => text }
        truncated + "\n\n(Summary truncated at \{MAX_SUMMARY_TOKENS} tokens)"
      } else {
        text
      }
    None => "Previous conversation history (summary unavailable)"
  }
}

///|
/// Manage chat history: keep first message, summarize middle, keep recent 4 turns
///  Returns true if history was summarized
async fn ChatHistory::manage_history(
  self : ChatHistory,
  config : Config,
) -> Bool {
  // Use accurate token count from last API call (persisted in conversation file)
  // Note: Add buffer for newly added user message (not yet counted by API)
  let total_tokens = self.last_context_tokens + 100 // rough buffer for new user input
  let max_tokens = self.max_context_tokens

  // If under threshold, no need to manage
  if total_tokens < max_tokens * SUMMARIZE_THRESHOLD_PERCENT / 100 {
    return false
  }

  // Count recent messages to keep
  let recent_keep = SUMMARIZE_KEEP_RECENT
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

  // Replace messages
  self.messages.clear()
  for msg in new_messages {
    self.messages.push(msg)
  }
  true // Indicate that summarization happened
}
