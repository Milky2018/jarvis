///|
/// Get .jarvis directory path
pub fn get_jarvis_dir() -> String {
  let home = @sys.get_env_vars().get("HOME").unwrap_or(".")
  home + "/.jarvis"
}

///|
/// Ensure .jarvis directory exists
pub async fn ensure_jarvis_dir() -> Unit {
  let dir = get_jarvis_dir()
  let (_exit_code, _output) = @process.collect_output_merged("sh", [
    "-c",
    "mkdir -p '\{dir}'",
  ])

}

///|
/// Get the latest conversation file number
pub async fn get_latest_conversation_number() -> Int {
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
pub fn get_conversation_file_path(number : Int) -> String {
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
pub async fn create_new_conversation_file(
  initial_messages : Array[@types.Message],
  model : String,
  last_context_tokens : Int,
) -> Int {
  ensure_jarvis_dir()
  let next_number = get_latest_conversation_number() + 1
  let path = get_conversation_file_path(next_number)

  // Save the initial messages using native fs API
  let json_obj : Json = {
    "messages": initial_messages.to_json(),
    "model": model,
    "last_context_tokens": last_context_tokens,
  }
  let json_str = json_obj.stringify()
  @fs.write_file(path, json_str, create=0o644) catch {
    e => @output.system_error("Failed to create conversation file: \{e}")
  }
  next_number
}

///|
/// Load the latest conversation file
pub async fn load_latest_conversation() -> ChatHistory? {
  let latest_number = get_latest_conversation_number()
  if latest_number == 0 {
    return None // No conversation files exist
  }
  let path = get_conversation_file_path(latest_number)
  match ChatHistory::load(path) {
    Some(history) => {
      history.current_file_number = latest_number
      Some(history)
    }
    None => None
  }
}

///|
/// Get user input history file path
pub fn get_input_history_path() -> String {
  get_jarvis_dir() + "/input_history.txt"
}

///|
/// Load user input history from file
pub async fn load_user_input_history() -> Array[String] {
  let path = get_input_history_path()
  // Use sh to read file
  let (exit_code, output) = @process.collect_output_merged("sh", [
    "-c",
    "cat '\{path}' 2>/dev/null",
  ])
  if exit_code != 0 {
    return [] // File doesn't exist yet
  }
  let content = output.text()
  let lines : Array[String] = []
  for line in content.split("\n") {
    let trimmed = line.trim(chars=" \t\r\n").to_string()
    if !trimmed.is_empty() {
      lines.push(trimmed)
    }
  }
  lines
}

///|
/// Save entire user input history to file
pub async fn save_user_input_history(history : Array[String]) -> Unit {
  let path = get_input_history_path()
  let mut content = ""
  for line in history {
    content = content + line + "\n"
  }
  @fs.write_file(path, content, create=0o644) catch {
    e => @output.system_error("Failed to save user input history: \{e}")
  }
}
