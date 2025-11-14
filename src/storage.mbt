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
/// Get the latest conversation file number
async fn get_latest_conversation_number() -> Int {
  let dir = get_jarvis_dir()
  // Find the highest numbered conv_XXX.json file
  let (exit_code, output) = @process.collect_output_merged("sh", [
    "-c",
    "cd '\{dir}' 2>/dev/null && ls -1 conv_*.json 2>/dev/null | sed 's/conv_\\([0-9]*\\)\\.json/\\1/' | sort -n | tail -1",
  ])
  if exit_code != 0 || output.text().is_blank() {
    return 0 // No conversation files exist yet
  }
  let number_str = output.text().trim(chars=" \n\t\r").to_string()
  // Parse the number
  @strconv.parse_int(number_str) catch {
    _ => 0
  }
}

///|
/// Get the path for a conversation file by number
fn get_conversation_file_path(number : Int) -> String {
  let dir = get_jarvis_dir()
  // Format number as 3-digit with leading zeros
  let num_str = if number < 10 {
    "00\{number}"
  } else if number < 100 {
    "0\{number}"
  } else {
    number.to_string()
  }
  "\{dir}/conv_\{num_str}.json"
}

///|
/// Create a new conversation file with initial messages
async fn create_new_conversation_file(initial_messages : Array[Message]) -> Int {
  ensure_jarvis_dir()
  let next_number = get_latest_conversation_number() + 1
  let path = get_conversation_file_path(next_number)

  // Save the initial messages using native fs API
  let json_obj : Json = { "messages": initial_messages.to_json() }
  let json_str = json_obj.stringify()
  @fs.write_file(path, json_str, create=0o644) catch {
    _ => ()
  }
  next_number
}

///|
/// Load the latest conversation file
/// Returns the loaded history and the file number
async fn load_latest_conversation() -> (ChatHistory, Int)? {
  let latest_number = get_latest_conversation_number()
  if latest_number == 0 {
    return None // No conversation files exist
  }
  let path = get_conversation_file_path(latest_number)
  match ChatHistory::load(path) {
    Some(history) => Some((history, latest_number))
    None => None
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
  let text_view = text.trim(chars=" \n\t\r")
  let text_str = text_view.to_string()
  if text_str.is_empty() {
    return []
  }
  let memories : Array[(String, String)] = []
  let lines : Array[String] = []
  for line in text_view.split("\n") {
    let trimmed_view = line.trim(chars=" \t\r")
    let filename = trimmed_view.to_string()
    if !filename.is_empty() {
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
    if word.length() >= 2 && !stop_words.contains(word) {
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
  let trimmed_indices = relevant_indices.trim(chars=" \n\t\r").to_string()
  if trimmed_indices.is_empty() {
    return ""
  }

  // Parse the indices and collect relevant memories
  let mut relevant_memories = ""
  let indices_view = relevant_indices.trim(chars=" \n\t\r")
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
