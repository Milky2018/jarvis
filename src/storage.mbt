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
    "的", "了", "是", "我", "你", "在", "有", "和", "this", "that", "the",
    "and", "for",
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
