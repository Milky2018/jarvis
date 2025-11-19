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
    let mut p = ""
    for i = 1; i < parts_array.length(); i = i + 1 {
      p = p + "/" + parts_array[i]
    }
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
fn parse_redirect_location(
  location : String,
  original_host : String,
  _original_path : String
) -> (String, String) raise JarvisError {
  if location.has_prefix("http://") || location.has_prefix("https://") {
    // Absolute URL - parse it
    parse_url(location)
  } else if location.has_prefix("/") {
    // Absolute path on same host
    (original_host, location)
  } else {
    // Relative path - resolve against original path
    // For simplicity, treat as absolute path on same host
    (original_host, "/" + location)
  }
}

///|
/// Send chat request with tools support
async fn send_chat_request_with_tools(
  config : Config,
  messages : Array[Message],
  tools : Array[Tool],
  model : String,
) -> ChatResponse raise {
  // Parse URL to extract host and path
  let url = config.base_url()
  let (host, base_path) = parse_url(url)
  let path = base_path + "/v1/messages"

  // Build request JSON with tools
  let request = ChatRequest::with_tools(messages, model, tools)
  let json_body = request.to_json().stringify()

  // Debug: print request body (first 500 chars)
  let preview = if json_body.length() > 500 {
    json_body[:500].to_string() catch { _ => json_body }
  } else {
    json_body
  }
  system_info("Request body preview: \{preview}...")

  // Follow redirects (up to 10 times)
  let mut current_host = host
  let mut current_path = path
  let mut redirects_count = 0
  let max_redirects = 10
  let mut final_response : ChatResponse? = None

  while final_response is None {
    // Send POST request and read response (use @http.post to get body automatically)
    let (current_response, body_data) = @http.post(
      "https://\{current_host}\{current_path}",
      json_body,
      headers={
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
      },
    ) catch {
      e =>
        raise HttpError(
          "Failed to send POST request to '\{current_host}\{current_path}': \{e}\nRequest body: \{json_body}",
        )
    }

    // Check for redirect
    if current_response.code == 301 ||
      current_response.code == 302 ||
      current_response.code == 307 ||
      current_response.code == 308 {
      if redirects_count >= max_redirects {
        raise HttpError("Too many redirects (exceeded \{max_redirects})")
      }

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

      system_info(
        "Following HTTP redirect: \{current_response.code} -> \{location}",
      )

      // Parse redirect location
      let (new_host, new_path) = parse_redirect_location(location, current_host, current_path)
      current_host = new_host
      current_path = new_path
      redirects_count = redirects_count + 1

      // body_data is already read, just continue to next iteration
      continue
    }

    // Not a redirect, parse response body
    system_info("Response code: \{current_response.code}, parsing body...")

    // Debug: print response headers
    let mut header_info = "Response headers:\n"
    current_response.headers.each(fn(k, v) {
      header_info = header_info + "  \{k}: \{v}\n"
    })
    system_info(header_info)

    let body_length = body_data.binary().length()
    system_info("Body length: \{body_length} bytes")

    if body_length == 0 {
      system_info("WARNING: Response body is empty! This is unexpected for a 200 response.")
    }

    if current_response.code != 200 {
      let error_text = body_data.text() catch { _ => "[Failed to read error body]" }
      raise HttpError(
        "HTTP request failed with status: \{current_response.code}\n" +
        "Request URL: https://\{current_host}\{current_path}\n" +
        "Request body: \{json_body}\n" +
        "Response body: \{error_text}",
      )
    }

    // Parse JSON response
    let json_obj = body_data.json() catch {
      e => {
        let text = body_data.text() catch { _ => "[binary] \{body_data.binary()}" }
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

    final_response = Some(chat_response)
  }

  // Return full response (including tool_calls)
  match final_response {
    Some(r) => r
    None => raise HttpError("Failed to get response after redirect handling")
  }
}

///|
/// Send streaming chat request (outputs content in real-time)
async fn send_streaming_chat_request(
  config : Config,
  messages : Array[Message],
  _tools : Array[Tool],
  model : String,
) -> ChatResponse raise {
  // Parse URL
  let url = config.base_url()
  let (host, base_path) = parse_url(url)
  let path = base_path + "/v1/messages"

  // Build request JSON with streaming enabled
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
  let request_with_stream : Json = {
    "model": model,
    "messages": non_system_messages.to_json(),
    "max_tokens": MAX_RESPONSE_TOKENS,
    "stream": true,
    "system": system_blocks.to_json(),
    "metadata": { "user_id": "jarvis-user" },
  }
  let json_body = request_with_stream.stringify()

  // Create HTTP client
  let client = @http.Client::connect(host, headers={
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
  }) catch {
    e =>
      raise HttpError(
        "Failed to connect to host '\{host}': \{e}\nFull URL: \{url}",
      )
  }
  defer client.close()

  // Send POST request with redirect handling
  let mut current_response = client.post(path, json_body, extra_headers={
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
  }) catch {
    e =>
      raise HttpError(
        "Failed to send POST request to '\{host}\{path}': \{e}\nRequest body: \{json_body}",
      )
  }

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
      system_info(
        "Following HTTP redirect: \{current_response.code} -> \{location}",
      )

      // Skip current response body before following redirect
      client.skip_response_body() catch {
        _ => ()
      }

      // Follow redirect
      redirects_count = redirects_count + 1
      current_response = client.post(location, json_body, extra_headers={
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
      }) catch {
        e =>
          raise HttpError(
            "Failed to follow redirect to '\{location}': \{e}",
          )
      }
    } else {
      break
    }
  }

  if redirects_count >= max_redirects {
    raise HttpError("Too many redirects (exceeded \{max_redirects})")
  }

  let response = current_response

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
  // Use true streaming: read chunks as they arrive
  let mut full_content = ""
  let mut finish_reason = ""

  // Buffer for reading chunks
  let buffer = FixedArray::make(1024, b'\x00')
  let mut accumulated_data = ""
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

    // Convert bytes to string using Bytes::from_array
    let buffer_view = buffer[:bytes_read]
    let chunk_bytes = Bytes::from_array(buffer_view)
    let chunk = chunk_bytes.to_string()
    accumulated_data = accumulated_data + chunk

    // Process complete lines (SSE format: "data: {json}\n\n")
    let lines : Array[String] = []
    let mut last_newline_pos = 0
    for i = 0; i < accumulated_data.length(); i = i + 1 {
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

    // Keep remaining incomplete line in buffer
    if last_newline_pos > 0 {
      let remaining_view = accumulated_data[last_newline_pos:] catch { _ => "" }
      accumulated_data = remaining_view.to_string()
    }

    // Process each complete line
    for line in lines {
      if line.has_prefix("data: ") {
        let json_str_view = line[6:] catch { _ => continue }
        let json_str = json_str_view.to_string()
        let trimmed = json_str.trim(chars=" \t\r\n").to_string()
        if trimmed == "[DONE]" {
          break
        }
        let chunk_json = @json.parse(json_str) catch { _ => continue }

        // Use guard statements to flatten nested match expressions
        guard chunk_json is Object(map) else { continue }
        guard map.get("choices") is Some(Array(choices)) else { continue }
        guard choices.length() > 0 else { continue }
        guard choices[0] is Object(choice_map) else { continue }

        // Extract delta content
        if choice_map.get("delta") is Some(Object(delta_map)) {
          if delta_map.get("content") is Some(String(content)) {
            full_content = full_content + content
            // Output immediately after parsing (ignore write errors)
            @stdio.stdout.write(content) catch {
              _ => ()
            }
          }
        }

        // Extract finish reason
        if choice_map.get("finish_reason") is Some(String(reason)) {
          finish_reason = reason
          break
        }
      }
    }
  }

  // Construct ChatResponse from accumulated data (Claude format)
  let content_blocks : Array[ContentBlock] = [
    {
      type_: "text",
      text: Some(full_content),
      id: None,
      name: None,
      input: None,
    },
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
