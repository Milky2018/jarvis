///|
/// ToolImpl trait - defines interface for tool implementations
trait ToolImpl {
  name(Self) -> String
  description(Self) -> String
  input_schema(Self) -> Json
  async execute(Self, Json) -> String
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
  "Execute a shell command and return the output. Use this when you need to interact with the system, run programs, or perform file operations."
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
impl ToolImpl for ExecuteCommandTool with execute(_self, input) {
  match input {
    Object(map) =>
      match map.get("command") {
        Some(String(cmd)) => {
          jarvis_says("Executing: \{cmd}")
          execute_shell_command(cmd)
        }
        Some(_) => "Error: 'command' must be a string"
        None => "Error: Missing 'command' argument"
      }
    _ => "Error: Input must be a JSON object"
  }
}

///|
/// Helper function for executing shell commands
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
/// Read File Tool
struct ReadFileTool {} derive(Default)

///|
impl ToolImpl for ReadFileTool with name(_self) {
  "read_file"
}

///|
impl ToolImpl for ReadFileTool with description(_self) {
  "Read a file from the filesystem. Returns the file content with line numbers. Supports optional offset and limit parameters for reading large files."
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
impl ToolImpl for ReadFileTool with execute(_self, input) {
  match input {
    Object(map) =>
      match map.get("path") {
        Some(String(path)) => {
          jarvis_says("Reading: \{path}")
          read_file_tool(path, input)
        }
        Some(_) => "Error: 'path' must be a string"
        None => "Error: Missing 'path' argument"
      }
    _ => "Error: Input must be a JSON object"
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
  "Write content to a file. This will overwrite the file if it exists or create a new file if it doesn't exist."
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
impl ToolImpl for WriteFileTool with execute(_self, input) {
  match input {
    Object(map) =>
      match (map.get("path"), map.get("content")) {
        (Some(String(path)), Some(String(content))) => {
          jarvis_says("Writing: \{path}")
          write_file_tool(path, content)
        }
        (None, _) => "Error: Missing 'path' argument"
        (_, None) => "Error: Missing 'content' argument"
        _ => "Error: 'path' and 'content' must be strings"
      }
    _ => "Error: Input must be a JSON object"
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
  "Write content to a file. This will overwrite the file if it exists or create a new file if it doesn't exist."
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
impl ToolImpl for EditFileTool with execute(_self, input) {
  match input {
    Object(map) =>
      match (map.get("path"), map.get("old_string"), map.get("new_string")) {
        (Some(String(path)), Some(String(old)), Some(String(new))) => {
          jarvis_says("Editing: \{path}")
          edit_file_tool(path, old, new)
        }
        (None, _, _) => "Error: Missing 'path' argument"
        (_, None, _) => "Error: Missing 'old_string' argument"
        (_, _, None) => "Error: Missing 'new_string' argument"
        _ => "Error: Arguments must be strings"
      }
    _ => "Error: Input must be a JSON object"
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
  "Search for a pattern in files. Uses ripgrep (rg) if available, otherwise falls back to grep. Returns matching lines with line numbers and file paths."
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
impl ToolImpl for GrepTool with execute(_self, input) {
  match input {
    Object(map) =>
      match map.get("pattern") {
        Some(String(pattern)) => {
          let path = match map.get("path") {
            Some(String(p)) => p
            _ => "."
          }
          jarvis_says("Searching for: \{pattern}")
          grep_tool(pattern, path)
        }
        Some(_) => "Error: 'pattern' must be a string"
        None => "Error: Missing 'pattern' argument"
      }
    _ => "Error: Input must be a JSON object"
  }
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
  "Find files matching a glob pattern. Returns a list of file paths. Useful for discovering files before reading or editing them."
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
impl ToolImpl for GlobTool with execute(_self, input) {
  match input {
    Object(map) =>
      match map.get("pattern") {
        Some(String(pattern)) => {
          let path = match map.get("path") {
            Some(String(p)) => p
            _ => "."
          }
          jarvis_says("Finding files: \{pattern}")
          glob_tool(pattern, path)
        }
        Some(_) => "Error: 'pattern' must be a string"
        None => "Error: Missing 'pattern' argument"
      }
    _ => "Error: Input must be a JSON object"
  }
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
impl ToolImpl for EndPlayModeTool with execute(_self, input) {
  let reason = match input {
    Object(map) =>
      match map.get("reason") {
        Some(String(r)) => r
        _ => "No reason provided"
      }
    _ => "No reason provided"
  }
  jarvis_says("Ending play mode: \{reason}")
  raise PlayModeEnded
}

///|
/// Execute tool with Claude API format (takes tool name and input JSON directly)
async fn execute_tool_claude(tool_name : String, input : Json) -> String {
  // Get all available tools (including end_play_mode if needed)
  let all_tools = get_all_tool_impls(in_play_mode=true)

  // Find and execute the matching tool
  for tool in all_tools {
    if tool.name() == tool_name {
      return tool.execute(input)
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
    e => return "Error reading file: \{e}"
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
  let mut result = ""
  let mut line_num = offset + 1
  let end = if offset + limit < total_lines {
    offset + limit
  } else {
    total_lines
  }
  for i = offset; i < end; i = i + 1 {
    result = result + "\{line_num}→" + lines[i] + "\n"
    line_num = line_num + 1
  }
  if total_lines > end {
    result = result + "\n... (\{total_lines - end} more lines)\n"
  }
  result
}

///|
/// Write file tool implementation
async fn write_file_tool(path : String, content : String) -> String {
  @fs.write_file(path, content, create=0o644) catch {
    e => return "Error writing file: \{e}"
  }
  "Successfully wrote \{content.length()} bytes to \{path}"
}

///|
/// Edit file tool implementation
async fn edit_file_tool(
  path : String,
  old_string : String,
  new_string : String,
) -> String {
  try {
    // Read current content
    let content_data = @fs.read_file(path) catch {
      e => return "Error reading file: \{e}"
    }
    let content = content_data.text()

    // Check if old_string exists
    if !content.contains(old_string) {
      return "Error: old_string not found in file"
    }

    // Count occurrences by splitting
    let parts_view = content.split(old_string)
    let parts : Array[String] = []
    for part in parts_view {
      parts.push(part.to_string())
    }
    let count = parts.length() - 1
    if count > 1 {
      return "Error: old_string appears \{count} times in file. Please make it more specific or use write_file to replace entire content."
    }

    // Perform replacement
    let new_content = content.replace(old=old_string, new=new_string)

    // Write back
    @fs.write_file(path, new_content, create=0o644) catch {
      e => return "Error writing file: \{e}"
    }
    "Successfully edited \{path}: replaced \{old_string.length()} bytes with \{new_string.length()} bytes"
  } catch {
    e => "Error: \{e}"
  }
}

///|
/// Grep tool implementation (search file contents)
async fn grep_tool(pattern : String, path : String) -> String {
  try {
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
  } catch {
    e => "Error: \{e}"
  }
}

///|
/// Glob tool implementation (find files by pattern)
async fn glob_tool(pattern : String, path : String) -> String {
  try {
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
  } catch {
    e => "Error: \{e}"
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
    tools.push({
      name: tool_impl.name(),
      description: tool_impl.description(),
      input_schema: tool_impl.input_schema(),
    })
  }
  tools
}
