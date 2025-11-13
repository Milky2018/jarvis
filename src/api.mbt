///|
/// Parse URL into host and path components
fn parse_url(url : String) -> (String, String) raise JarvisError {
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
  let parts_view = host_and_path.split("/")
  let parts_array : Array[String] = []
  for part in parts_view {
    parts_array.push(part.to_string())
  }
  let host = parts_array[0]
  let path = if parts_array.length() > 1 {
    let mut p = ""
    for i = 1; i < parts_array.length(); i = i + 1 {
      p = p + "/" + parts_array[i]
    }
    if p.is_empty() {
      "/v1/messages"
    } else {
      p
    }
  } else {
    "/v1/messages"
  }
  (host, path)
}

///|
/// Send chat request with tools support
async fn send_chat_request_with_tools(
  config : Config,
  messages : Array[Message],
  tools : Array[Tool],
  model : String,
) -> ChatResponse raise JarvisError {
  // Parse URL to extract host and path
  let url = config.base_url()
  let (host, path) = parse_url(url)

  // Build request JSON with tools
  let request = ChatRequest::with_tools(messages, model, tools)
  let json_body = request.to_json().stringify()

  // Create HTTP client
  let client = @http.Client::connect(host, headers={
    "Authorization": "Bearer \{config.auth_token()}",
  }) catch {
    e =>
      raise HttpError(
        "Failed to connect to host '\{host}': \{e}\nFull URL: \{url}",
      )
  }
  defer client.close()

  // Send POST request
  let response = client.post(path, json_body, extra_headers={
    "Content-Type": "application/json",
  }) catch {
    e =>
      raise HttpError(
        "Failed to send POST request to '\{host}\{path}': \{e}\nRequest body: \{json_body}",
      )
  }
  if response.code != 200 {
    let error_body = client.read_all().text() catch {
        _ => "[Failed to read error body]"
      }
    raise HttpError(
      "HTTP request failed with status: \{response.code}\nResponse body: \{error_body}",
    )
  }

  // Read response body
  let body = client.read_all() catch {
    e => raise HttpError("Failed to read response: \{e}")
  }

  // Parse JSON response
  let json_obj = body.json() catch {
    e => {
      let text = body.text() catch { _ => "[Failed to read body text]" }
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

  // Return full response (including tool_calls)
  chat_response
}

///|
/// Send streaming chat request (outputs content in real-time)
async fn send_streaming_chat_request(
  config : Config,
  messages : Array[Message],
  _tools : Array[Tool],
  model : String,
) -> ChatResponse raise JarvisError {
  // Parse URL
  let url = config.base_url()
  let (host, path) = parse_url(url)

  // Build request JSON with streaming enabled
  // Extract system messages
  let mut system_content = ""
  let non_system_messages : Array[Message] = []
  for msg in messages {
    if msg.role == "system" && msg.content is Some(content) {
      if system_content.is_empty() == false {
        system_content = system_content + "\n\n"
      }
      system_content = system_content + content
    } else {
      non_system_messages.push(msg)
    }
  }
  let request_with_stream : Json = if system_content.is_empty() {
    {
      "model": model,
      "messages": non_system_messages.to_json(),
      "max_tokens": 4096,
      "stream": true,
    }
  } else {
    {
      "model": model,
      "messages": non_system_messages.to_json(),
      "max_tokens": 4096,
      "stream": true,
      "system": system_content,
    }
  }
  let json_body = request_with_stream.stringify()

  // Create HTTP client
  let client = @http.Client::connect(host, headers={
    "Authorization": "Bearer \{config.auth_token()}",
  }) catch {
    e =>
      raise HttpError(
        "Failed to connect to host '\{host}': \{e}\nFull URL: \{url}",
      )
  }
  defer client.close()

  // Send POST request
  let response = client.post(path, json_body, extra_headers={
    "Content-Type": "application/json",
  }) catch {
    e =>
      raise HttpError(
        "Failed to send POST request to '\{host}\{path}': \{e}\nRequest body: \{json_body}",
      )
  }
  if response.code != 200 {
    let error_body = client.read_all().text() catch {
        _ => "[Failed to read error body]"
      }
    raise HttpError(
      "HTTP request failed with status: \{response.code}\nResponse body: \{error_body}",
    )
  }

  // Read streaming response (SSE format)
  // Note: read_all() waits for complete response, but we output chunks as we parse them
  let mut full_content = ""
  let mut finish_reason = ""
  let body_text = client.read_all().text() catch {
      e => raise HttpError("Failed to read response: \{e}")
    }

  // Parse SSE format and output chunks
  let lines : Array[String] = []
  for line_view in body_text[:].split("\n") {
    lines.push(line_view.to_string())
  }
  for line in lines {
    if line.has_prefix("data: ") {
      let json_str_view = line[6:] catch { _ => continue }
      let json_str = json_str_view.to_string()
      let trimmed = json_str[:].trim(chars=" \t\r\n").to_string()
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
          let _ = @stdio.stdout.write(content) catch { _ => () }

        }
      }

      // Extract finish reason
      if choice_map.get("finish_reason") is Some(String(reason)) {
        finish_reason = reason
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
