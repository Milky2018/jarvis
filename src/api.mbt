///|
/// Parse URL into host and path components.
/// Returns (host, path) where path is empty string if no path is provided in URL.
/// Examples:
///   "https://api.example.com/v1/messages" -> ("api.example.com", "/v1/messages")
///   "https://api.example.com" -> ("api.example.com", "")
///   "https://api.example.com/" -> ("api.example.com", "")
///   "api.example.com/api" -> ("api.example.com", "/api")
fn parse_url(url : String) -> (String, String) raise JarvisError {
  // Remove protocol prefix if present
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

  // Split by "/" to separate host and path
  let parts_view = host_and_path.split("/")
  let parts_array : Array[String] = []
  for part in parts_view {
    parts_array.push(part.to_string())
  }

  // First part is always the host
  let host = parts_array[0]

  // Reconstruct path from remaining parts
  let path = if parts_array.length() > 1 {
    let builder = StringBuilder::new()
    for i = 1; i < parts_array.length(); i = i + 1 {
      builder.write_string("/")
      builder.write_string(parts_array[i])
    }
    let p = builder.to_string()
    // If path is just "/" (from trailing slash), return empty
    if p == "/" {
      ""
    } else {
      p
    }
  } else {
    // No path provided
    ""
  }
  (host, path)
}

///|
test "parse_url_with_https_and_path" {
  let (host, path) = parse_url("https://api.anthropic.com/v1/messages")
  inspect(host, content="api.anthropic.com")
  inspect(path, content="/v1/messages")
}

///|
test "parse_url_with_http_and_path" {
  let (host, path) = parse_url("http://localhost:8080/v1/messages")
  inspect(host, content="localhost:8080")
  inspect(path, content="/v1/messages")
}

///|
test "parse_url_without_protocol" {
  let (host, path) = parse_url("api.anthropic.com/v1/chat")
  inspect(host, content="api.anthropic.com")
  inspect(path, content="/v1/chat")
}

///|
test "parse_url_host_only_https" {
  let (host, path) = parse_url("https://api.anthropic.com")
  inspect(host, content="api.anthropic.com")
  inspect(path, content="")
}

///|
test "parse_url_host_only_no_protocol" {
  let (host, path) = parse_url("api.anthropic.com")
  inspect(host, content="api.anthropic.com")
  inspect(path, content="")
}

///|
test "parse_url_with_trailing_slash" {
  let (host, path) = parse_url("https://api.anthropic.com/")
  inspect(host, content="api.anthropic.com")
  inspect(path, content="")
}

///|
test "parse_url_with_existing_path" {
  let (host, path) = parse_url("https://api.anthropic.com/api")
  inspect(host, content="api.anthropic.com")
  inspect(path, content="/api")
}

///|
test "parse_url_with_multiple_path_segments" {
  let (host, path) = parse_url("https://api.example.com/v2/chat/completions")
  inspect(host, content="api.example.com")
  inspect(path, content="/v2/chat/completions")
}

///|
test "parse_url_localhost_with_port" {
  let (host, path) = parse_url("http://localhost:3000/api/messages")
  inspect(host, content="localhost:3000")
  inspect(path, content="/api/messages")
}

///|
/// Parse redirect location (could be absolute URL or relative path)
/// Returns (host, path) tuple

///|
/// Send non-streaming chat request (for tool calls)
async fn send_chat_request_non_streaming(
  config : Config,
  messages : Array[Message],
  tools : Array[Tool],
  model : String,
) -> ChatResponse {
  // Parse URL
  let url = config.base_url()
  let (host, base_path) = parse_url(url)
  let path = base_path + "/v1/messages"

  // Build request body (with stream: false)
  let json_body = build_request_body_non_streaming(messages, tools, model)

  // Debug: print request details
  system_debug("=== HTTP REQUEST (NON-STREAMING) ===")
  system_debug("POST https://\{host}\{path}")
  let preview = json_body[:500].to_string() catch { _ => json_body }
  system_debug("Request body preview: \{preview}...")
  system_debug("====================================")

  // Send POST request with proxy support
  let (response, body_data) = post_with_proxy("https://\{host}\{path}", json_body, headers={
    "Authorization": "Bearer \{config.auth_token()}",
    "x-api-key": config.auth_token(),
    "anthropic-version": "2023-06-01",
    "anthropic-dangerous-direct-browser-access": "true",
    "Accept": "application/json",
    "x-app": "cli",
    "User-Agent": "jarvis/1.0.0",
    "anthropic-beta": "interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14",
    "accept-language": "*",
    "sec-fetch-mode": "cors",
    "Content-Type": "application/json",
    "X-Stainless-Retry-Count": "0",
    "X-Stainless-Timeout": "600",
    "X-Stainless-Lang": "js",
    "X-Stainless-Package-Version": "0.60.0",
    "X-Stainless-OS": "MacOS",
    "X-Stainless-Arch": "arm64",
    "X-Stainless-Runtime": "node",
    "X-Stainless-Runtime-Version": "v24.8.0",
  })

  // Debug: print response status
  system_debug("=== HTTP RESPONSE (NON-STREAMING) ===")
  system_debug("Status: \{response.code}")
  system_debug("=====================================")
  if response.code != 200 {
    let error_text = body_data.text() catch {
      _ => "[Failed to read error body]"
    }
    raise HttpError(
      "HTTP request failed with status: \{response.code}\n" +
      "Response body: \{error_text}",
    )
  }

  // Parse JSON response
  let json_obj = body_data.json() catch {
    e => {
      let text = body_data.text() catch { _ => "[binary data]" }
      raise HttpError("Failed to parse JSON: \{e}\nResponse body: \{text}")
    }
  }

  // Log response for debugging
  log_model_response(json_obj.stringify())
  let chat_response : ChatResponse = @json.from_json(json_obj) catch {
    @json.JsonDecodeError(e) => {
      let json_str = json_obj.stringify()
      raise HttpError(
        "Failed to decode response: \{e}\nJSON object: \{json_str}",
      )
    }
  }
  chat_response
}

///|
/// Log model response to file for debugging
async fn log_model_response(json_str : String) -> Unit {
  let env_vars = @sys.get_env_vars()
  let home = match env_vars.get("HOME") {
    Some(h) => h
    None => return // Skip if HOME not set
  }
  let log_path = "\{home}/.jarvis/model_responses.log"

  // Format log entry with separator
  let log_entry = "\n========== Response ==========\n\{json_str}\n"

  // Append to log file
  @fs.write_file(log_path, log_entry, create=0o644, append=true, truncate=false) catch {
    e => system_error("Log model response: \{e}")
  }
}

///|
/// Build request body JSON for Claude API (non-streaming)
fn build_request_body_non_streaming(
  messages : Array[Message],
  tools : Array[Tool],
  model : String,
) -> String {
  // Build system content blocks array
  let system_blocks : Array[Json] = [{ "type": "text", "text": SYSTEM_PROMPT }]
  let non_system_messages : Array[Message] = []
  for msg in messages {
    if msg.role == "system" {
      let text = msg.get_text()
      if !text.is_empty() {
        system_blocks.push({ "type": "text", "text": text })
      }
    } else {
      non_system_messages.push(msg)
    }
  }

  // Build request with streaming DISABLED
  let mut request : Json = {
    "model": model,
    "messages": non_system_messages.to_json(),
    "max_tokens": MAX_RESPONSE_TOKENS,
    "stream": false,
    "system": system_blocks.to_json(),
    "metadata": { "user_id": "jarvis-user" },
  }

  // Add tools if present
  if tools.length() > 0 {
    request = {
      "model": model,
      "messages": non_system_messages.to_json(),
      "max_tokens": MAX_RESPONSE_TOKENS,
      "stream": false,
      "system": system_blocks.to_json(),
      "tools": tools.to_json(),
      "metadata": { "user_id": "jarvis-user" },
    }
  }
  request.stringify()
}

///|
/// Build request body JSON for Claude API
fn build_request_body(
  messages : Array[Message],
  tools : Array[Tool],
  model : String,
) -> String {
  // Build system content blocks array
  let system_blocks : Array[Json] = [{ "type": "text", "text": SYSTEM_PROMPT }]
  let non_system_messages : Array[Message] = []
  for msg in messages {
    if msg.role == "system" {
      let text = msg.get_text()
      if !text.is_empty() {
        system_blocks.push({ "type": "text", "text": text })
      }
    } else {
      non_system_messages.push(msg)
    }
  }

  // Build request with streaming enabled
  let mut request_with_stream : Json = {
    "model": model,
    "messages": non_system_messages.to_json(),
    "max_tokens": MAX_RESPONSE_TOKENS,
    "stream": true,
    "system": system_blocks.to_json(),
    "metadata": { "user_id": "jarvis-user" },
  }

  // Add tools if present
  if tools.length() > 0 {
    request_with_stream = {
      "model": model,
      "messages": non_system_messages.to_json(),
      "max_tokens": MAX_RESPONSE_TOKENS,
      "stream": true,
      "system": system_blocks.to_json(),
      "tools": tools.to_json(),
      "metadata": { "user_id": "jarvis-user" },
    }
  }
  request_with_stream.stringify()
}

///|
/// Get POST request extra headers
fn get_post_headers() -> Map[String, String] {
  {
    "Content-Type": "application/json",
    "X-Stainless-Retry-Count": "0",
    "X-Stainless-Timeout": "600",
    "X-Stainless-Lang": "js",
    "X-Stainless-Package-Version": "0.60.0",
    "X-Stainless-OS": "MacOS",
    "X-Stainless-Arch": "arm64",
    "X-Stainless-Runtime": "node",
    "X-Stainless-Runtime-Version": "v24.8.0",
    "x-stainless-helper-method": "stream",
  }
}

///|
/// Create HTTP client with authentication headers
async fn create_http_client(host : String, config : Config) -> @http.Client {
  let proxy = get_proxy_config()
  match proxy {
    Some(p) =>
      @http.Client::connect(host, headers={
        "Authorization": "Bearer \{config.auth_token()}",
        "x-api-key": config.auth_token(),
        "anthropic-version": "2023-06-01",
        "anthropic-dangerous-direct-browser-access": "true",
        "Accept": "application/json",
        "x-app": "cli",
        "User-Agent": "jarvis/1.0.0",
        "anthropic-beta": "interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14",
        "accept-language": "*",
        "sec-fetch-mode": "cors",
      }, proxy=p)
    None =>
      @http.Client::connect(host, headers={
        "Authorization": "Bearer \{config.auth_token()}",
        "x-api-key": config.auth_token(),
        "anthropic-version": "2023-06-01",
        "anthropic-dangerous-direct-browser-access": "true",
        "Accept": "application/json",
        "x-app": "cli",
        "User-Agent": "jarvis/1.0.0",
        "anthropic-beta": "interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14",
        "accept-language": "*",
        "sec-fetch-mode": "cors",
      })
  }
}

///|
/// Send POST request and follow redirects
async fn send_post_with_redirects(
  client : @http.Client,
  path : String,
  json_body : String,
) -> @http.Response {
  let extra_headers = get_post_headers()
  let mut current_response = client.post(path, json_body, extra_headers~)

  // Follow redirects (up to 10 times)
  let mut redirects_count = 0
  let max_redirects = 10
  while redirects_count < max_redirects {
    if current_response.code == 301 ||
      current_response.code == 302 ||
      current_response.code == 307 ||
      current_response.code == 308 {
      let location = match current_response.headers.get("location") {
        Some(loc) => loc
        None =>
          match current_response.headers.get("Location") {
            Some(loc) => loc
            None => ""
          }
      }
      if location.is_empty() {
        raise HttpError(
          "HTTP redirect response (\{current_response.code}) missing Location header",
        )
      }
      system_debug(
        "Following HTTP redirect: \{current_response.code} -> \{location}",
      )

      // Skip current response body before following redirect
      client.skip_response_body() catch {
        _ => ()
      }

      // Follow redirect
      redirects_count = redirects_count + 1
      current_response = client.post(location, json_body, extra_headers~)
    } else {
      break
    }
  }
  if redirects_count >= max_redirects {
    raise HttpError("Too many redirects (exceeded \{max_redirects})")
  }
  current_response
}

///|
/// Extract complete lines from accumulated data
fn extract_lines_from_chunk(
  accumulated_data : String,
) -> (Array[String], String) {
  let lines : Array[String] = []
  let mut last_newline_pos = 0
  for i in 0..<accumulated_data.length() {
    match accumulated_data.get_char(i) {
      Some('\n') => {
        let line_view = accumulated_data[last_newline_pos:i] catch {
            _ => continue
          }
        let line = line_view.to_string().trim(chars=" \t\r\n").to_string()
        if line.length() > 0 {
          lines.push(line)
        }
        last_newline_pos = i + 1
      }
      _ => ()
    }
  }

  // Return lines and remaining incomplete data
  let remaining = if last_newline_pos > 0 {
    let remaining_view = accumulated_data[last_newline_pos:] catch { _ => "" }
    remaining_view.to_string()
  } else {
    accumulated_data
  }
  (lines, remaining)
}

///|
/// SSE line processing result
struct SSELineResult {
  text_delta : String?
  finish_reason : String?
  block_start : ContentBlockStart?
  input_json_delta : String?
  input_tokens : Int? // from message_start
  output_tokens : Int? // from message_delta
}

///|
/// Content block start event
struct ContentBlockStart {
  type_ : String // "text" or "tool_use"
  id : String? // tool_use id
  name : String? // tool_use name
}

///|
/// Process a single SSE line and extract content/finish_reason
async fn process_sse_line(
  line : String,
  has_printed_prefix : Ref[Bool],
) -> SSELineResult {
  let empty_result = {
    text_delta: None,
    finish_reason: None,
    block_start: None,
    input_json_delta: None,
    input_tokens: None,
    output_tokens: None,
  }

  // Skip SSE event metadata lines
  if line.has_prefix("event:") {
    return empty_result
  }
  if !line.has_prefix("data: ") {
    return empty_result
  }
  let json_str_view = line[6:] catch {
      _ => {
        system_error("Failed to extract JSON from SSE line: \{line}")
        return empty_result
      }
    }
  let json_str = json_str_view.to_string()
  let trimmed = json_str.trim(chars=" \t\r\n").to_string()
  if trimmed == "[DONE]" {
    return empty_result
  }
  let chunk_json = @json.parse(json_str) catch {
    _ => {
      system_error("Failed to parse streaming JSON chunk: \{json_str}")
      return empty_result
    }
  }

  // Parse Claude native streaming format
  guard chunk_json is Object(map) else {
    system_error("Streaming chunk is not a JSON object")
    return empty_result
  }

  // Check event type
  match map.get("type") {
    Some(String("message_start")) =>
      // Extract input tokens from message_start
      if map.get("message") is Some(Object(msg_map)) {
        if msg_map.get("usage") is Some(Object(usage_map)) {
          if usage_map.get("input_tokens") is Some(Number(n, ..)) {
            return {
              text_delta: None,
              finish_reason: None,
              block_start: None,
              input_json_delta: None,
              input_tokens: Some(n.to_int()),
              output_tokens: None,
            }
          }
        }
      }
    Some(String("content_block_start")) =>
      // New content block starting
      if map.get("content_block") is Some(Object(block_map)) {
        let type_ = match block_map.get("type") {
          Some(String(t)) => t
          _ => ""
        }
        let id = match block_map.get("id") {
          Some(String(i)) => Some(i)
          _ => None
        }
        let name = match block_map.get("name") {
          Some(String(n)) => Some(n)
          _ => None
        }
        return {
          text_delta: None,
          finish_reason: None,
          block_start: Some({ type_, id, name }),
          input_json_delta: None,
          input_tokens: None,
          output_tokens: None,
        }
      }
    Some(String("content_block_delta")) =>
      // Content block delta
      if map.get("delta") is Some(Object(delta_map)) {
        match delta_map.get("type") {
          Some(String("text_delta")) =>
            if delta_map.get("text") is Some(String(text)) {
              // Print "Jarvis: " prefix on first text output
              if !has_printed_prefix.val {
                print_jarvis_prefix()
                has_printed_prefix.val = true
              }
              // Output immediately (ignore write errors)
              @stdio.stdout.write(text) catch {
                _ => ()
              }
              return {
                text_delta: Some(text),
                finish_reason: None,
                block_start: None,
                input_json_delta: None,
                input_tokens: None,
                output_tokens: None,
              }
            }
          Some(String("input_json_delta")) =>
            if delta_map.get("partial_json") is Some(String(json)) {
              return {
                text_delta: None,
                finish_reason: None,
                block_start: None,
                input_json_delta: Some(json),
                input_tokens: None,
                output_tokens: None,
              }
            }
          _ => ()
        }
      }
    Some(String("message_delta")) =>
      // Extract finish reason and output tokens from message_delta
      if map.get("delta") is Some(Object(delta_map)) {
        let reason = match delta_map.get("stop_reason") {
          Some(String(r)) => Some(r)
          _ => None
        }
        // Also check for usage.output_tokens in message_delta
        let output_tokens = if map.get("usage") is Some(Object(usage_map)) {
          match usage_map.get("output_tokens") {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          }
        } else {
          None
        }
        if reason is Some(_) || output_tokens is Some(_) {
          return {
            text_delta: None,
            finish_reason: reason,
            block_start: None,
            input_json_delta: None,
            input_tokens: None,
            output_tokens,
          }
        }
      }
    _ => ()
  }
  {
    text_delta: None,
    finish_reason: None,
    block_start: None,
    input_json_delta: None,
    input_tokens: None,
    output_tokens: None,
  }
}

///|
/// Send streaming chat request (outputs content in real-time)
async fn send_streaming_chat_request(
  config : Config,
  messages : Array[Message],
  tools : Array[Tool],
  model : String,
) -> ChatResponse {
  // Parse URL
  let url = config.base_url()
  let (host, base_path) = parse_url(url)
  let path = base_path + "/v1/messages"

  // Build request body
  let json_body = build_request_body(messages, tools, model)

  // Debug: print request details
  system_debug("=== HTTP REQUEST ===")
  system_debug("POST https://\{host}\{path}")
  system_debug("Request body:")
  system_debug(json_body)
  system_debug("===================")

  // Create HTTP client
  let client = create_http_client(host, config)
  defer client.close()

  // Send POST request with redirect handling
  let response = send_post_with_redirects(client, path, json_body)

  // Debug: print response status
  system_debug("=== HTTP RESPONSE ===")
  system_debug("Status: \{response.code}")
  system_debug("Response headers:")
  for header in response.headers {
    system_debug("  \{header.0}: \{header.1}")
  }
  system_debug("====================")
  if response.code != 200 {
    let error_body = client.read_all().text() catch {
        _ => "[Failed to read error body]"
      }
    raise HttpError(
      "HTTP request failed with status: \{response.code}\n" +
      "Request URL: https://\{host}\{path}\n" +
      "Request body: \{json_body}\n" +
      "Response body: \{error_body}",
    )
  }

  // Read streaming response (SSE format)
  let content_blocks : Array[ContentBlock] = []
  let mut current_text_builder : StringBuilder? = None
  let mut current_tool_use : (String, String, StringBuilder)? = None // (id, name, json_builder)
  let mut finish_reason = ""
  let mut total_chunks = 0
  let mut input_tokens_count = 0
  let mut output_tokens_count = 0
  let has_printed_prefix : Ref[Bool] = { val: false }

  // Buffer for reading chunks
  let buffer = FixedArray::make(1024, b'\x00')
  let mut accumulated_data = ""
  let mut total_bytes_read = 0
  for {
    let bytes_read = client.read(buffer) catch {
      e =>
        raise HttpError(
          "Failed to read streaming response from \{host}\{path}: \{e}\n" +
          "Request body: \{json_body}",
        )
    }
    if bytes_read == 0 {
      break // End of stream
    }
    total_bytes_read = total_bytes_read + bytes_read

    // Convert bytes to string using UTF-8 decode
    let buffer_view = buffer[:bytes_read]
    let chunk_bytes = Bytes::from_array(buffer_view)
    let chunk = @encoding/utf8.decode(chunk_bytes)
    accumulated_data = accumulated_data + chunk

    // Extract complete lines from accumulated data
    let (lines, remaining) = extract_lines_from_chunk(accumulated_data)
    accumulated_data = remaining

    // Process each complete line
    for line in lines {
      let result = process_sse_line(line, has_printed_prefix)

      // Handle block start
      match result.block_start {
        Some(block_start) =>
          if block_start.type_ == "text" {
            current_text_builder = Some(StringBuilder::new())
          } else if block_start.type_ == "tool_use" {
            match (block_start.id, block_start.name) {
              (Some(id), Some(name)) =>
                current_tool_use = Some((id, name, StringBuilder::new()))
              _ => ()
            }
          }
        None => ()
      }

      // Handle text delta
      match result.text_delta {
        Some(text) => {
          match current_text_builder {
            Some(builder) => builder.write_string(text)
            None => {
              let builder = StringBuilder::new()
              builder.write_string(text)
              current_text_builder = Some(builder)
            }
          }
          total_chunks = total_chunks + 1
        }
        None => ()
      }

      // Handle input_json delta
      match result.input_json_delta {
        Some(json) =>
          match current_tool_use {
            Some((_id, _name, builder)) => builder.write_string(json)
            None => ()
          }
        None => ()
      }

      // Handle token counts
      match result.input_tokens {
        Some(tokens) => input_tokens_count = tokens
        None => ()
      }
      match result.output_tokens {
        Some(tokens) => output_tokens_count = tokens
        None => ()
      }

      // Handle finish reason
      match result.finish_reason {
        Some(reason) => {
          finish_reason = reason
          // Finalize current blocks
          match current_text_builder {
            Some(builder) => {
              content_blocks.push({
                type_: "text",
                text: Some(builder.to_string()),
                id: None,
                name: None,
                input: None,
              })
              current_text_builder = None
            }
            None => ()
          }
          match current_tool_use {
            Some((id, name, builder)) => {
              let json_str = builder.to_string()
              let input_json = @json.parse(json_str) catch { _ => {} }
              content_blocks.push({
                type_: "tool_use",
                text: None,
                id: Some(id),
                name: Some(name),
                input: Some(input_json),
              })
              current_tool_use = None
            }
            None => ()
          }
        }
        None => ()
      }
    }
  }

  // Debug: streaming summary
  system_debug("=== STREAMING END ===")
  system_debug(
    "Total bytes: \{total_bytes_read}, chunks: \{total_chunks}, blocks: \{content_blocks.length()}",
  )
  system_debug("Finish reason: \{finish_reason}")
  system_debug("====================")

  // Construct ChatResponse from accumulated data
  let usage_info = if input_tokens_count > 0 || output_tokens_count > 0 {
    Some({
      input_tokens: input_tokens_count,
      output_tokens: output_tokens_count,
    })
  } else {
    None
  }
  let response : ChatResponse = {
    id: "",
    type_: "message",
    role: "assistant",
    content: content_blocks,
    model,
    stop_reason: Some(finish_reason),
    usage: usage_info,
  }

  // Log response for debugging
  let log_json = response.to_json()
  log_model_response(log_json.stringify())
  response
}
