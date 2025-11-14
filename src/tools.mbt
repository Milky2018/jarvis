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
    "execute_command" =>
      // Extract command from input JSON
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
    "end_play_mode" => {
      // Extract optional reason
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
    _ => "Error: Unknown tool '\{tool_name}'"
  }
}

///|
fn get_available_tools(in_play_mode~ : Bool = false) -> Array[Tool] {
  let execute_command_schema : Json = {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "description": "The shell command to execute",
      },
    },
    "required": ["command"],
  }
  let tools : Array[Tool] = [
    {
      name: "execute_command",
      description: "Execute a shell command and return the output. Use this when you need to interact with the system, run programs, or access files.",
      input_schema: execute_command_schema,
    },
  ]

  // Add end_play_mode tool only when in play mode
  if in_play_mode {
    let end_play_mode_schema : Json = {
      "type": "object",
      "properties": {
        "reason": {
          "type": "string",
          "description": "Optional reason for ending play mode",
        },
      },
      "required": [],
    }
    tools.push({
      name: "end_play_mode",
      description: "Call this tool when you're finished exploring and want to end play mode. You can optionally provide a reason.",
      input_schema: end_play_mode_schema,
    })
  }

  tools
}

///|
/// Handle special commands starting with ':'
