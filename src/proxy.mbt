///|
/// HTTP Proxy Client
/// Provides simple HTTP proxy support

///|
/// Parse proxy URL to get host and port
/// Format: http://host:port or https://host:port
fn parse_proxy_url(proxy_url : String) -> (String, Int)? {
  if proxy_url.is_empty() {
    return None
  }

  // Remove protocol prefix
  let url = if proxy_url.has_prefix("http://") {
    proxy_url[7:].to_string() catch {
      _ => proxy_url
    }
  } else if proxy_url.has_prefix("https://") {
    proxy_url[8:].to_string() catch {
      _ => proxy_url
    }
  } else {
    proxy_url
  }

  // Split host and port
  if url.contains(":") {
    let parts_view = url.split(":")
    let parts : Array[String] = []
    for part in parts_view {
      parts.push(part.to_string())
    }
    if parts.length() >= 2 {
      let host = parts[0]
      let port = @strconv.parse_int(parts[1]) catch { _ => 8080 }
      return Some((host, port))
    }
  }

  // No port specified, use default
  Some((url, 8080))
}

///|
/// Get HTTP request with proxy support
/// Uses proxy if configured via environment variables, otherwise uses direct connection
pub async fn get_with_proxy(url : String) -> (@http.Response, &@io.Data) {
  // Read proxy settings from environment
  let env_vars = @sys.get_env_vars()

  // Determine which proxy to use based on URL protocol
  let proxy_url = if url.has_prefix("https://") {
    match env_vars.get("HTTPS_PROXY") {
      Some(v) => v
      None =>
        match env_vars.get("https_proxy") {
          Some(v) => v
          None => ""
        }
    }
  } else {
    match env_vars.get("HTTP_PROXY") {
      Some(v) => v
      None =>
        match env_vars.get("http_proxy") {
          Some(v) => v
          None => ""
        }
    }
  }

  // For now, always use direct connection since MoonBit's @http doesn't support proxy
  // TODO: Implement proxy support using @socket.Tcp when needed
  if !proxy_url.is_empty() {
    // Log that proxy is configured but not used
    println_async(
      "Note: Proxy configured (\{proxy_url}) but not yet supported by HTTP library",
    )
  }

  // Use direct connection
  @http.get(url)
}

///|
test "parse_proxy_url: empty string" {
  inspect(parse_proxy_url(""), content="None")
}

///|
test "parse_proxy_url: http with port" {
  let result = parse_proxy_url("http://proxy.example.com:8080")
  inspect(result, content="Some((\"proxy.example.com\", 8080))")
}

///|
test "parse_proxy_url: https with port" {
  let result = parse_proxy_url("https://proxy.example.com:3128")
  inspect(result, content="Some((\"proxy.example.com\", 3128))")
}

///|
test "parse_proxy_url: no protocol" {
  let result = parse_proxy_url("proxy.example.com:8080")
  inspect(result, content="Some((\"proxy.example.com\", 8080))")
}

///|
test "parse_proxy_url: no port defaults to 8080" {
  let result = parse_proxy_url("http://proxy.example.com")
  inspect(result, content="Some((\"proxy.example.com\", 8080))")
}

///|
test "parse_proxy_url: host only" {
  let result = parse_proxy_url("proxy.example.com")
  inspect(result, content="Some((\"proxy.example.com\", 8080))")
}
