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

  // Read both HTTP and HTTPS proxy settings
  let http_proxy = match env_vars.get("HTTP_PROXY") {
    Some(v) => v
    None =>
      match env_vars.get("http_proxy") {
        Some(v) => v
        None => ""
      }
  }

  let https_proxy = match env_vars.get("HTTPS_PROXY") {
    Some(v) => v
    None =>
      match env_vars.get("https_proxy") {
        Some(v) => v
        None => ""
      }
  }

  // Determine proxy configuration based on environment variables
  let proxy = if !http_proxy.is_empty() && !https_proxy.is_empty() {
    // Both proxies configured - use custom
    match (parse_proxy_url(http_proxy), parse_proxy_url(https_proxy)) {
      (Some((http_host, http_port)), Some((https_host, https_port))) =>
        Some(
          @http.Proxy::custom(
            http_host,
            http_port~,
            https_host,
            https_port~,
          ),
        )
      (Some((host, port)), None) => Some(@http.Proxy::http(host, port~))
      (None, Some((host, port))) => Some(@http.Proxy::https(host, port~))
      _ => None
    }
  } else if !http_proxy.is_empty() {
    // Only HTTP proxy configured
    match parse_proxy_url(http_proxy) {
      Some((host, port)) => Some(@http.Proxy::http(host, port~))
      None => None
    }
  } else if !https_proxy.is_empty() {
    // Only HTTPS proxy configured
    match parse_proxy_url(https_proxy) {
      Some((host, port)) => Some(@http.Proxy::https(host, port~))
      None => None
    }
  } else {
    None
  }

  // Use @http.get with proxy support
  match proxy {
    Some(p) => @http.get(url, proxy=p)
    None => @http.get(url)
  }
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
