///|
/// HTTP Proxy Client
/// Provides simple HTTP proxy support

///|
/// Global proxy configuration (initialized once at startup)
let proxy_config : Ref[@http.Proxy?] = { val: None }

///|
/// Initialize proxy configuration from environment variables
pub fn init_proxy_config() -> Unit {
  let env_vars = @sys.get_env_vars()
  let http_proxy = (match env_vars.get("HTTP_PROXY") {
    Some(v) => Some(v)
    None => env_vars.get("http_proxy")
  }).bind(parse_proxy_url)
  let https_proxy = (match env_vars.get("HTTPS_PROXY") {
    Some(v) => Some(v)
    None => env_vars.get("https_proxy")
  }).bind(parse_proxy_url)

  // Build proxy configuration
  proxy_config.val = match (http_proxy, https_proxy) {
    (Some((h1, p1)), Some((h2, p2))) =>
      Some(@http.Proxy::custom(h1, http_port=p1, h2, https_port=p2))
    (Some((h, p)), None) => Some(@http.Proxy::http(h, port=p))
    (None, Some((h, p))) => Some(@http.Proxy::https(h, port=p))
    (None, None) => None
  }
}

///|
/// Get the global proxy configuration
pub fn get_proxy_config() -> @http.Proxy? {
  proxy_config.val
}

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
async fn get_with_proxy(url : String) -> (@http.Response, &@io.Data) {
  match get_proxy_config() {
    Some(p) => @http.get(url, proxy=p)
    None => @http.get(url)
  }
}

///|
/// POST HTTP request with proxy support
/// Uses proxy if configured via environment variables, otherwise uses direct connection
pub async fn post_with_proxy(
  url : String,
  body : String,
  headers~ : Map[String, String] = {},
) -> (@http.Response, &@io.Data) {
  match get_proxy_config() {
    Some(p) => @http.post(url, body, headers~, proxy=p)
    None => @http.post(url, body, headers~)
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
