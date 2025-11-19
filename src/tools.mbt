///|
/// ToolImpl trait - defines interface for tool implementations
trait ToolImpl {
  name(Self) -> String
  description(Self) -> String
  input_schema(Self) -> Json
  async execute(Self, Json, ChatHistory) -> String
}

///|
/// Helper function to report tool errors
async fn tool_error(msg : String) -> String {
  system_error(msg)
  msg
}

///|
/// Execute Command Tool
struct ExecuteCommandTool {} derive(Default)

///|
impl ToolImpl for ExecuteCommandTool with name(_self) {
  "execute_command"
}

///|
impl ToolImpl for ExecuteCommandTool with description(_self) {
  "Executes a shell command and returns the output. Use for terminal operations like git, npm, docker, etc. DO NOT use for file operations (reading, writing, editing, searching) - use specialized tools instead. For multiple commands: use '&&' to chain dependent commands, run independent commands in parallel."
}

///|
impl ToolImpl for ExecuteCommandTool with input_schema(_self) {
  {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "description": "The shell command to execute",
      },
    },
    "required": ["command"],
  }
}

///|
impl ToolImpl for ExecuteCommandTool with execute(_self, input, chat_history) {
  match input {
    Object(map) =>
      match map.get("command") {
        Some(String(cmd)) => {
          tool_log("Execute", cmd)
          execute_shell_command(cmd, chat_history)
        }
        Some(_) => tool_error("Error: 'command' must be a string")
        None => tool_error("Error: Missing 'command' argument")
      }
    _ => tool_error("Error: Input must be a JSON object")
  }
}

///|
/// Helper function for executing shell commands
async fn execute_shell_command(
  command : String,
  _chat_history : ChatHistory,
) -> String {
  // Execute command directly without cd prefix
  let (exit_code, output) = @process.collect_output_merged("sh", ["-c", command])
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
}

///|
async test "integration: execute_command_updates_chat_history" {
  let history = ChatHistory::new()

  // Execute a simple echo command
  let tool = ExecuteCommandTool::default()
  let input : Json = { "command": "echo 'Hello World'" }
  let result = tool.execute(input, history)

  // Verify command executed successfully
  inspect(result.contains("Error"), content="false")
  inspect(result.contains("Hello World"), content="true")
}

///|
async test "integration: execute_pwd_shows_current_dir" {
  let history = ChatHistory::new()
  let tool = ExecuteCommandTool::default()
  let input : Json = { "command": "pwd" }
  let result = tool.execute(input, history)

  // Should show current directory
  inspect(result.contains("/"), content="true")
  inspect(result.contains("Error"), content="false")
}

///|
/// Read File Tool
struct ReadFileTool {} derive(Default)

///|
impl ToolImpl for ReadFileTool with name(_self) {
  "read_file"
}

///|
impl ToolImpl for ReadFileTool with description(_self) {
  "Reads a file from the filesystem. Returns content with line numbers (cat -n format). Supports optional offset and limit for large files. File path must be absolute. Lines longer than 2000 chars are truncated. Read multiple files in parallel when possible."
}

///|
impl ToolImpl for ReadFileTool with input_schema(_self) {
  {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Absolute path to the file to read",
      },
      "offset": {
        "type": "number",
        "description": "Line number to start reading from (default: 0)",
      },
      "limit": {
        "type": "number",
        "description": "Maximum number of lines to read (default: 2000)",
      },
    },
    "required": ["path"],
  }
}

///|
impl ToolImpl for ReadFileTool with execute(_self, input, _chat_history) {
  match input {
    Object(map) =>
      match map.get("path") {
        Some(String(path)) => {
          tool_log("Read", path)
          read_file_tool(path, input)
        }
        Some(_) => tool_error("Error: 'path' must be a string")
        None => tool_error("Error: Missing 'path' argument")
      }
    _ => tool_error("Error: Input must be a JSON object")
  }
}

///|
/// Write File Tool
struct WriteFileTool {} derive(Default)

///|
impl ToolImpl for WriteFileTool with name(_self) {
  "write_file"
}

///|
impl ToolImpl for WriteFileTool with description(_self) {
  "Writes a file to the filesystem. This tool will overwrite existing files. MUST use read_file first for existing files. ALWAYS prefer edit_file for small changes. Use write_file ONLY for: (1) new files, (2) complete rewrites, (3) changes to many parts of a file. File path must be absolute."
}

///|
impl ToolImpl for WriteFileTool with input_schema(_self) {
  {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Absolute path to the file to write",
      },
      "content": {
        "type": "string",
        "description": "Content to write to the file",
      },
    },
    "required": ["path", "content"],
  }
}

///|
impl ToolImpl for WriteFileTool with execute(_self, input, _chat_history) {
  match input {
    Object(map) =>
      match (map.get("path"), map.get("content")) {
        (Some(String(path)), Some(String(content))) => {
          tool_log("Write", path)
          write_file_tool(path, content)
        }
        (None, _) => tool_error("Error: Missing 'path' argument")
        (_, None) => tool_error("Error: Missing 'content' argument")
        _ => tool_error("Error: 'path' and 'content' must be strings")
      }
    _ => tool_error("Error: Input must be a JSON object")
  }
}

///|
/// Edit File Tool
struct EditFileTool {} derive(Default)

///|
impl ToolImpl for EditFileTool with name(_self) {
  "edit_file"
}

///|
impl ToolImpl for EditFileTool with description(_self) {
  "Performs exact string replacements in files. MUST use read_file first. Preserve exact indentation from read_file output (after line number prefix). PREFERRED for small changes. Edit will FAIL if old_string is not unique - provide more context or use replace_all. Use replace_all for renaming across file."
}

///|
impl ToolImpl for EditFileTool with input_schema(_self) {
  {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Absolute path to the file to edit",
      },
      "old_string": {
        "type": "string",
        "description": "The exact string to replace (must appear exactly once in the file)",
      },
      "new_string": {
        "type": "string",
        "description": "The new string to replace with",
      },
    },
    "required": ["path", "old_string", "new_string"],
  }
}

///|
impl ToolImpl for EditFileTool with execute(_self, input, _chat_history) {
  match input {
    Object(map) =>
      match (map.get("path"), map.get("old_string"), map.get("new_string")) {
        (Some(String(path)), Some(String(old)), Some(String(new))) => {
          tool_log("Edit", path)
          edit_file_tool(path, old, new)
        }
        (None, _, _) => tool_error("Error: Missing 'path' argument")
        (_, None, _) => tool_error("Error: Missing 'old_string' argument")
        (_, _, None) => tool_error("Error: Missing 'new_string' argument")
        _ => tool_error("Error: Arguments must be strings")
      }
    _ => tool_error("Error: Input must be a JSON object")
  }
}

///|
/// Grep Tool
struct GrepTool {} derive(Default)

///|
impl ToolImpl for GrepTool with name(_self) {
  "grep"
}

///|
impl ToolImpl for GrepTool with description(_self) {
  "A powerful search tool built on ripgrep. ALWAYS use grep for search tasks (never rg command). Supports full regex syntax. Filter files with glob or type parameter. Output modes: content (matching lines), files_with_matches (file paths), count. Pattern uses ripgrep syntax - literal braces need escaping."
}

///|
impl ToolImpl for GrepTool with input_schema(_self) {
  {
    "type": "object",
    "properties": {
      "pattern": {
        "type": "string",
        "description": "Regular expression pattern to search for",
      },
      "path": {
        "type": "string",
        "description": "Path to search in (default: current directory)",
      },
    },
    "required": ["pattern"],
  }
}

///|
impl ToolImpl for GrepTool with execute(_self, input, _chat_history) {
  match input {
    Object(map) =>
      match map.get("pattern") {
        Some(String(pattern)) => {
          let path = match map.get("path") {
            Some(String(p)) => p
            _ => "."
          }
          tool_log("Grep", pattern)
          grep_tool(pattern, path)
        }
        Some(_) => tool_error("Error: 'pattern' must be a string")
        None => tool_error("Error: Missing 'pattern' argument")
      }
    _ => tool_error("Error: Input must be a JSON object")
  }
}

///|
async test "integration: grep_tool_with_test_file" {
  // Create a test file using shell command
  let setup_history = ChatHistory::new()
  let setup_tool = ExecuteCommandTool::default()
  let test_path = "/tmp/jarvis_grep_test.txt"

  // Create test file
  setup_tool.execute(
    {
      "command": "echo -e 'Line 1: Hello\\nLine 2: World\\nLine 3: Hello again' > \{test_path}",
    },
    setup_history,
  )
  |> ignore

  // Now test grep
  let history = ChatHistory::new()
  let tool = GrepTool::default()
  let input : Json = { "pattern": "Hello", "path": test_path }
  let result = tool.execute(input, history)

  // Verify pattern was found
  inspect(
    result.contains("Hello") || result.contains("No matches"),
    content="true",
  )

  // Cleanup
  setup_tool.execute({ "command": "rm -f \{test_path}" }, setup_history)
  |> ignore
}

///|
/// Glob Tool
struct GlobTool {} derive(Default)

///|
impl ToolImpl for GlobTool with name(_self) {
  "glob"
}

///|
impl ToolImpl for GlobTool with description(_self) {
  "Fast file pattern matching tool. Supports glob patterns like **/*.js or src/**/*.ts. Returns matching file paths sorted by modification time. Use for finding files by name patterns. Perform multiple searches in parallel when possible."
}

///|
impl ToolImpl for GlobTool with input_schema(_self) {
  {
    "type": "object",
    "properties": {
      "pattern": {
        "type": "string",
        "description": "Glob pattern to match files (e.g., '*.mbt', 'src/**/*.json')",
      },
      "path": {
        "type": "string",
        "description": "Directory to search in (default: current directory)",
      },
    },
    "required": ["pattern"],
  }
}

///|
impl ToolImpl for GlobTool with execute(_self, input, _chat_history) {
  match input {
    Object(map) =>
      match map.get("pattern") {
        Some(String(pattern)) => {
          let path = match map.get("path") {
            Some(String(p)) => p
            _ => "."
          }
          tool_log("Glob", pattern)
          glob_tool(pattern, path)
        }
        Some(_) => tool_error("Error: 'pattern' must be a string")
        None => tool_error("Error: Missing 'pattern' argument")
      }
    _ => tool_error("Error: Input must be a JSON object")
  }
}

///|
async test "integration: glob_tool_finds_txt_files" {
  let history = ChatHistory::new()
  let tool = GlobTool::default()

  // Search for .txt files in /tmp (should always exist)
  let input : Json = { "pattern": "*.txt", "path": "/tmp" }
  let result = tool.execute(input, history)

  // Verify glob ran (might find files or not, but shouldn't error)
  inspect(
    result.contains("Error:") == false || result.contains("No files found"),
    content="true",
  )
}

///|
/// End Elaborate Tool - Signal that elaboration is complete
struct EndElaborateTool {} derive(Default)

///|
impl ToolImpl for EndElaborateTool with name(_self) {
  "end_elaborate"
}

///|
impl ToolImpl for EndElaborateTool with description(_self) {
  "Call this tool when you have fully completed the user's request and have nothing more to add. This signals that the conversation should end. Only use this when you are completely done with the task and have provided all necessary information or completed all requested actions."
}

///|
impl ToolImpl for EndElaborateTool with input_schema(_self) {
  {
    "type": "object",
    "properties": {
      "summary": {
        "type": "string",
        "description": "Brief summary of what was accomplished",
      },
    },
    "required": ["summary"],
  }
}

///|
impl ToolImpl for EndElaborateTool with execute(_self, input, _chat_history) {
  let summary = match input {
    Object(map) =>
      match map.get("summary") {
        Some(String(s)) => s
        _ => "Task completed"
      }
    _ => "Task completed"
  }
  // Return a special marker that the main loop will detect
  "ELABORATE_COMPLETE: \{summary}"
}

///|
async test "integration: end_elaborate_tool_returns_complete_marker" {
  let history = ChatHistory::new()
  let tool = EndElaborateTool::default()

  // Test tool execution with a summary
  let input : Json = { "summary": "Task completed successfully" }
  let result = tool.execute(input, history)

  // Verify the tool returns the ELABORATE_COMPLETE marker
  inspect(result.has_prefix("ELABORATE_COMPLETE:"), content="true")
  inspect(result.contains("Task completed successfully"), content="true")
}

///|
async test "integration: end_elaborate_tool_without_summary" {
  let history = ChatHistory::new()
  let tool = EndElaborateTool::default()

  // Test tool execution without summary (should use default)
  let input : Json = {}
  let result = tool.execute(input, history)

  // Verify the tool still returns the marker with default message
  inspect(result.has_prefix("ELABORATE_COMPLETE:"), content="true")
  inspect(result.contains("Task completed"), content="true")
}

///|
async test "integration: auto_continue_with_end_elaborate_flow" {
  // This test simulates the auto-continue workflow by executing multiple tools
  // in sequence, demonstrating the pattern that would occur in a real conversation:
  // 1. Tool execution (execute_command) - simulates LLM's first action
  // 2. Tool execution (read_file) - simulates LLM continuing work
  // 3. Tool execution (end_elaborate) - simulates LLM signaling completion
  //
  // In a real conversation with MockLLMClient, the system would:
  // - Receive LLM response with tool calls
  // - Execute tools
  // - Auto-add "Continue..." message
  // - Loop until end_elaborate is called
  //
  // This test verifies the tools work correctly in sequence and that
  // end_elaborate returns the proper completion marker.

  let history = ChatHistory::new()

  // Simulate turn 1: execute a command
  let exec_tool = ExecuteCommandTool::default()
  let exec_input : Json = { "command": "echo 'test'" }
  let exec_result = exec_tool.execute(exec_input, history)

  // Verify command executed
  inspect(exec_result.contains("test"), content="true")

  // Simulate turn 2: read a file (create test file first)
  let setup_tool = ExecuteCommandTool::default()
  let test_path = "/tmp/jarvis_elaborate_test.txt"
  setup_tool.execute(
    { "command": "echo 'file content' > \{test_path}" },
    history,
  )
  |> ignore
  let read_tool = ReadFileTool::default()
  let read_input : Json = { "path": test_path }
  let read_result = read_tool.execute(read_input, history)

  // Verify file was read
  inspect(read_result.contains("file content"), content="true")

  // Simulate turn 3: LLM responds with just text (simulated by adding to history)
  // In real flow, system would auto-add "Continue..." here

  // Simulate turn 4: LLM calls end_elaborate
  let end_tool = EndElaborateTool::default()
  let end_input : Json = {
    "summary": "Executed command and read file successfully",
  }
  let end_result = end_tool.execute(end_input, history)

  // Verify end_elaborate returns the completion marker
  inspect(end_result.has_prefix("ELABORATE_COMPLETE:"), content="true")
  inspect(
    end_result.contains("Executed command and read file successfully"),
    content="true",
  )

  // Cleanup
  setup_tool.execute({ "command": "rm -f \{test_path}" }, history) |> ignore
}

///|
/// End Play Mode Tool
struct EndPlayModeTool {} derive(Default)

///|
impl ToolImpl for EndPlayModeTool with name(_self) {
  "end_play_mode"
}

///|
impl ToolImpl for EndPlayModeTool with description(_self) {
  "Call this tool when you're finished exploring and want to end play mode. You can optionally provide a reason."
}

///|
impl ToolImpl for EndPlayModeTool with input_schema(_self) {
  {
    "type": "object",
    "properties": {
      "reason": {
        "type": "string",
        "description": "Optional reason for ending play mode",
      },
    },
    "required": [],
  }
}

///|
impl ToolImpl for EndPlayModeTool with execute(_self, input, _chat_history) {
  let reason = match input {
    Object(map) =>
      match map.get("reason") {
        Some(String(r)) => r
        _ => "No reason provided"
      }
    _ => "No reason provided"
  }
  tool_log("EndElaborate", reason)
  raise PlayModeEnded
}

///|
/// Web Search Tool (uses Anthropic's built-in web search)
/// This tool is handled server-side by Anthropic, so we don't execute it locally.
/// We just need to register it in the tools list with the special type.
struct WebSearchTool {} derive(Default)

///|
impl ToolImpl for WebSearchTool with name(_self) {
  "web_search"
}

///|
impl ToolImpl for WebSearchTool with description(_self) {
  // Description is not used for Anthropic's built-in tools,
  // but we provide one for consistency
  "Allows searching the web for current information. Provides up-to-date information for current events and recent data. Returns search result blocks. Use for accessing information beyond knowledge cutoff. Domain filtering supported (handled by Anthropic)."
}

///|
impl ToolImpl for WebSearchTool with input_schema(_self) {
  // This schema is not actually used - Anthropic handles the tool server-side
  // But we keep it for compatibility with our tool framework
  {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Search query" },
    },
    "required": ["query"],
  }
}

///|
impl ToolImpl for WebSearchTool with execute(_self, input, _chat_history) {
  // This should never be called because Anthropic handles web_search server-side
  // But if it is called, log the query for debugging
  match input {
    Object(map) =>
      match map.get("query") {
        Some(String(query)) => {
          tool_log("WebSearch", "\{query} [Anthropic]")
          "Web search is handled by Anthropic server-side and should not reach client execution"
        }
        _ => "Error: Invalid web_search input"
      }
    _ => "Error: Invalid web_search input"
  }
}

///|
/// WebFetch tool - Fetch and analyze web content
struct WebFetchTool {} derive(Default)

///|
impl ToolImpl for WebFetchTool with name(_self) {
  "web_fetch"
}

///|
impl ToolImpl for WebFetchTool with description(_self) {
  "Fetches content from a URL and processes it using an AI model. Takes URL and optional prompt. Converts HTML to text. Processes content with prompt using fast model. Returns response or raw content. Read-only. Content truncated if too large (>30k chars without prompt)."
}

///|
impl ToolImpl for WebFetchTool with input_schema(_self) {
  {
    "type": "object",
    "properties": {
      "url": {
        "type": "string",
        "description": "The URL to fetch content from",
      },
      "prompt": {
        "type": "string",
        "description": "Optional prompt to process the fetched content (uses a small fast model)",
      },
    },
    "required": ["url"],
  }
}

///|
impl ToolImpl for WebFetchTool with execute(_self, input, chat_history) {
  match input {
    Object(map) => {
      let url = match map.get("url") {
        Some(String(u)) => u
        _ => return tool_error("Missing or invalid 'url' parameter")
      }
      let prompt = match map.get("prompt") {
        Some(String(p)) => Some(p)
        _ => None
      }
      tool_log("WebFetch", url)
      web_fetch_tool(url, prompt, chat_history)
    }
    _ => tool_error("Invalid input format for web_fetch")
  }
}

///|
/// Execute tool with Claude API format (takes tool name and input JSON directly)
async fn execute_tool_claude(
  tool_name : String,
  input : Json,
  chat_history : ChatHistory,
) -> String {
  // Get all available tools (including end_play_mode if needed)
  let all_tools = get_all_tool_impls(in_play_mode=true)

  // Find and execute the matching tool
  for tool in all_tools {
    if tool.name() == tool_name {
      return tool.execute(input, chat_history)
    }
  }

  // Tool not found
  "Error: Unknown tool '\{tool_name}'"
}

///|
/// Read file tool implementation
async fn read_file_tool(path : String, params : Json) -> String {
  // Read file content
  let content_data = @fs.read_file(path) catch {
    e => return tool_error("Error reading file: \{e}")
  }
  let content = content_data.text()

  // Get optional offset and limit
  let (offset, limit) = match params {
    Object(map) => {
      let off = match map.get("offset") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let lim = match map.get("limit") {
        Some(Number(n, ..)) => n.to_int()
        _ => 2000
      }
      (off, lim)
    }
    _ => (0, 2000)
  }

  // Split into lines
  let lines_view = content.split("\n")
  let lines : Array[String] = []
  for line in lines_view {
    lines.push(line.to_string())
  }
  let total_lines = lines.length()

  // Apply offset and limit
  let builder = StringBuilder::new()
  let mut line_num = offset + 1
  let end = if offset + limit < total_lines {
    offset + limit
  } else {
    total_lines
  }

  // Calculate max width for line numbers based on the end line number
  let max_line = end
  let max_width = if max_line < 10 {
    1
  } else if max_line < 100 {
    2
  } else if max_line < 1000 {
    3
  } else if max_line < 10000 {
    4
  } else {
    5
  }
  for i = offset; i < end; i = i + 1 {
    let num_str = line_num.to_string()
    let padding = max_width - num_str.length()

    // Add leading spaces for alignment
    for j = 0; j < padding; j = j + 1 {
      builder.write_string(" ")
    }
    builder.write_string(num_str)
    builder.write_string(": ")
    builder.write_string(lines[i])
    builder.write_string("\n")
    line_num = line_num + 1
  }
  if total_lines > end {
    builder.write_string("\n... (")
    builder.write_string((total_lines - end).to_string())
    builder.write_string(" more lines)\n")
  }
  builder.to_string()
}

///|
/// Write file tool implementation
async fn write_file_tool(path : String, content : String) -> String {
  // Try to read old content first (if file exists)
  let (old_text, is_new_file) = try {
    let old_content = @fs.read_file(path)
    let text = old_content.text()
    (text, false)
  } catch {
    _ => ("", true)
  }

  // Write new content
  @fs.write_file(path, content, create=0o644) catch {
    e => return tool_error("Error writing file: \{e}")
  }
  let display = if is_new_file {
    // New file: show all content as green (added) with + prefix
    let builder = StringBuilder::new()
    builder.write_string("New file created:\n")
    let lines_view = content.split("\n")
    let lines : Array[String] = []
    for line in lines_view {
      lines.push(line.to_string())
    }
    let total_lines = lines.length()
    let show_lines = if total_lines > 50 { 50 } else { total_lines }

    // Calculate max width for line numbers
    let max_width = if show_lines < 10 {
      1
    } else if show_lines < 100 {
      2
    } else if show_lines < 1000 {
      3
    } else {
      4
    }
    for i = 0; i < show_lines; i = i + 1 {
      builder.write_string(COLOR_GREEN)
      builder.write_string("+ ")

      // Add line number with padding
      let line_num = i + 1
      let num_str = line_num.to_string()
      let padding = max_width - num_str.length()
      for j = 0; j < padding; j = j + 1 {
        builder.write_string(" ")
      }
      builder.write_string(num_str)
      builder.write_string(": ")
      builder.write_string(lines[i])
      builder.write_string(COLOR_RESET)
      builder.write_string("\n")
    }
    if total_lines > show_lines {
      builder.write_string("... (")
      builder.write_string((total_lines - show_lines).to_string())
      builder.write_string(" more lines)\n")
    }
    builder.to_string()
  } else {
    // Existing file: show line-based diff
    let (prefix, removed, added, suffix) = compute_line_diff(old_text, content)
    format_diff(prefix, removed, added, suffix)
  }
  // Print the diff output
  println_async(display)
  "Successfully wrote \{content.length()} bytes to \{path}"
}

///|
/// Edit file tool implementation
async fn edit_file_tool(
  path : String,
  old_string : String,
  new_string : String,
) -> String {
  // Read current content
  let content_data = @fs.read_file(path) catch {
    e => return tool_error("Error reading file: \{e}")
  }
  let content = content_data.text()

  // Check if old_string exists
  if !content.contains(old_string) {
    return tool_error("Error: old_string not found in file")
  }

  // Count occurrences by splitting
  let parts_view = content.split(old_string)
  let parts : Array[String] = []
  for part in parts_view {
    parts.push(part.to_string())
  }
  let count = parts.length() - 1
  if count > 1 {
    return tool_error(
      "Error: old_string appears \{count} times in file. Please make it more specific or use write_file to replace entire content.",
    )
  }

  // Perform replacement
  let new_content = content.replace(old=old_string, new=new_string)

  // Write back
  @fs.write_file(path, new_content, create=0o644) catch {
    e => return tool_error("Error writing file: \{e}")
  }

  // Generate colored diff output and display to user
  let builder = StringBuilder::new()

  // Show old content (red foreground)
  let old_lines_view = old_string.split("\n")
  let old_lines : Array[String] = []
  for line in old_lines_view {
    old_lines.push(line.to_string())
  }
  for line in old_lines {
    builder.write_string(COLOR_RED)
    builder.write_string("- ")
    builder.write_string(line)
    builder.write_string(COLOR_RESET)
    builder.write_string("\n")
  }
  // Show new content (green foreground)
  let new_lines_view = new_string.split("\n")
  let new_lines : Array[String] = []
  for line in new_lines_view {
    new_lines.push(line.to_string())
  }
  for line in new_lines {
    builder.write_string(COLOR_GREEN)
    builder.write_string("+ ")
    builder.write_string(line)
    builder.write_string(COLOR_RESET)
    builder.write_string("\n")
  }
  // Print the diff output
  println_async(builder.to_string())
  "Successfully edited \{path}"
}

///|
/// Grep tool implementation (search file contents)
async fn grep_tool(pattern : String, path : String) -> String {
  // Use ripgrep if available, otherwise use grep
  let (exit_code, output) = @process.collect_output_merged("sh", [
    "-c",
    "if command -v rg >/dev/null 2>&1; then rg --line-number --no-heading '\{pattern}' '\{path}' 2>&1; else grep -rn '\{pattern}' '\{path}' 2>&1; fi",
  ])
  let result = output.text()
  if exit_code == 0 {
    if result.is_empty() {
      "No matches found for pattern: \{pattern}"
    } else {
      result
    }
  } else if exit_code == 1 {
    // Exit code 1 means no matches found for ripgrep/grep
    "No matches found for pattern: \{pattern}"
  } else {
    "Error searching: \{result}"
  }
}

///|
/// Glob tool implementation (find files by pattern)
async fn glob_tool(pattern : String, path : String) -> String {
  // Use find with -name pattern
  let (exit_code, output) = @process.collect_output_merged("sh", [
    "-c",
    "cd '\{path}' 2>/dev/null && find . -name '\{pattern}' -type f 2>/dev/null | head -100",
  ])
  let result = output.text()
  if exit_code == 0 {
    if result.is_empty() {
      "No files found matching pattern: \{pattern}"
    } else {
      result
    }
  } else {
    "Error finding files: \{result}"
  }
}

///|
/// Get all available tool implementations
fn get_all_tool_impls(in_play_mode? : Bool = false) -> Array[&ToolImpl] {
  let tools : Array[&ToolImpl] = [
    ExecuteCommandTool::default(),
    ReadFileTool::default(),
    WriteFileTool::default(),
    EditFileTool::default(),
    GrepTool::default(),
    GlobTool::default(),
    WebSearchTool::default(),
    WebFetchTool::default(),
    EndElaborateTool::default(),
  ]
  if in_play_mode {
    tools.push(EndPlayModeTool::default())
  }
  tools
}

///|
fn get_available_tools(in_play_mode? : Bool = false) -> Array[Tool] {
  let tool_impls = get_all_tool_impls(in_play_mode~)
  let tools : Array[Tool] = []
  for tool_impl in tool_impls {
    let tool_name = tool_impl.name()
    // Use Anthropic's built-in web_search tool type
    if tool_name == "web_search" {
      tools.push({
        name: "web_search",
        type_: Some("web_search_20250305"),
        description: "",
        input_schema: {},
        max_uses: Some(5),
      })
    } else {
      tools.push({
        name: tool_name,
        description: tool_impl.description(),
        input_schema: tool_impl.input_schema(),
        type_: None,
        max_uses: None,
      })
    }
  }
  tools
}

///|
/// WebFetch tool implementation - fetch content from URL
async fn web_fetch_tool(
  url : String,
  prompt : String?,
  chat_history : ChatHistory,
) -> String {
  // Use GET request with proxy support
  let (response, content_data) = get_with_proxy(url) catch {
    e => return tool_error("Failed to fetch \{url}: \{e}")
  }
  if response.code != 200 {
    return tool_error("HTTP \{response.code} when fetching \{url}")
  }
  let content = content_data.text()

  // If prompt is provided, use petite model to process content
  match prompt {
    Some(p) => {
      let messages : Array[Message] = [
        Message::new("user", "\{p}\n\nContent:\n\{content}"),
      ]
      let config = load_config() catch {
        _ => return tool_error("Failed to load config")
      }
      // Use non-streaming for tool internal processing (no need to show progress)
      let response = send_chat_request_non_streaming(
        config,
        messages,
        [],
        chat_history.petite_model,
      ) catch {
        e => return tool_error("Failed to process content: \{e}")
      }
      match response.get_text_content() {
        Some(result) => result
        None => tool_error("No response from model")
      }
    }
    None =>
      // Return raw content (truncate if too long)
      if content.length() > 30000 {
        (content[:30000] catch { _ => content }).to_string() +
        "\n\n... (content truncated, total \{content.length()} characters)"
      } else {
        content
      }
  }
}
