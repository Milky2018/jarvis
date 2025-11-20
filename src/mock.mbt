///|
/// Testing utilities and mocks for Jarvis
///
/// This module provides comprehensive mocking infrastructure for testing:
/// - LLM API mocking
/// - File system mocking
/// - I/O (stdout/stderr) mocking

///|
/// Mock LLM response for testing
struct MockLLMResponse {
  text : String // Text content to return
  tool_calls : Array[(String, String, Json)] // (id, name, input)
  input_tokens : Int
  output_tokens : Int
}

///|
/// Mock LLM client that returns pre-configured responses
struct MockLLMClient {
  responses : Array[MockLLMResponse] // Queue of responses to return
  mut current_index : Int // Current position in response queue
  mut request_count : Int // Number of requests made
  mut last_messages : Array[@types.Message] // Last messages sent to the LLM
}

///|
/// Create a new mock LLM client with given responses
fn MockLLMClient::new(responses : Array[MockLLMResponse]) -> MockLLMClient {
  { responses, current_index: 0, request_count: 0, last_messages: [] }
}

///|
/// Get the next mock response
fn MockLLMClient::get_next_response(self : MockLLMClient) -> MockLLMResponse? {
  if self.current_index < self.responses.length() {
    let response = self.responses[self.current_index]
    self.current_index = self.current_index + 1
    self.request_count = self.request_count + 1
    Some(response)
  } else {
    None
  }
}

///|
/// Record the messages sent in a request
fn MockLLMClient::record_messages(
  self : MockLLMClient,
  messages : Array[@types.Message],
) -> Unit {
  self.last_messages = messages
}

///|
/// Mock file system for testing
struct MockFileSystem {
  files : Map[String, String] // path -> content
}

///|
/// Create a new mock file system
fn MockFileSystem::new() -> MockFileSystem {
  { files: Map::new() }
}

///|
/// Add a file to the mock file system
fn MockFileSystem::add_file(
  self : MockFileSystem,
  path : String,
  content : String,
) -> Unit {
  self.files.set(path, content)
}

///|
/// Read a file from the mock file system
fn MockFileSystem::read_file(self : MockFileSystem, path : String) -> String? {
  self.files.get(path)
}

///|
/// Write a file to the mock file system
fn MockFileSystem::write_file(
  self : MockFileSystem,
  path : String,
  content : String,
) -> Unit {
  self.files.set(path, content)
}

///|
/// Check if a file exists in the mock file system
fn MockFileSystem::file_exists(self : MockFileSystem, path : String) -> Bool {
  self.files.contains(path)
}

///|
/// Delete a file from the mock file system
fn MockFileSystem::delete_file(self : MockFileSystem, path : String) -> Unit {
  ignore(self.files.remove(path))
}

///|
/// List all files in the mock file system
fn MockFileSystem::list_files(self : MockFileSystem) -> Array[String] {
  let files : Array[String] = []
  self.files.each(fn(path, _) { files.push(path) })
  files
}

///|
/// Mock output capture for testing stdout/stderr
struct MockOutputCapture {
  mut stdout_lines : Array[String]
  mut stderr_lines : Array[String]
}

///|
/// Create a new mock output capture
fn MockOutputCapture::new() -> MockOutputCapture {
  { stdout_lines: [], stderr_lines: [] }
}

///|
/// Record a line to stdout
fn MockOutputCapture::write_stdout(
  self : MockOutputCapture,
  line : String,
) -> Unit {
  self.stdout_lines.push(line)
}

///|
/// Record a line to stderr
fn MockOutputCapture::write_stderr(
  self : MockOutputCapture,
  line : String,
) -> Unit {
  self.stderr_lines.push(line)
}

///|
/// Get all stdout output as a single string
fn MockOutputCapture::get_stdout(self : MockOutputCapture) -> String {
  let builder = StringBuilder::new()
  for line in self.stdout_lines {
    builder.write_string(line)
    builder.write_string("\n")
  }
  builder.to_string()
}

///|
/// Get all stderr output as a single string
fn MockOutputCapture::get_stderr(self : MockOutputCapture) -> String {
  let builder = StringBuilder::new()
  for line in self.stderr_lines {
    builder.write_string(line)
    builder.write_string("\n")
  }
  builder.to_string()
}

///|
/// Clear all captured output
fn MockOutputCapture::clear(self : MockOutputCapture) -> Unit {
  self.stdout_lines = []
  self.stderr_lines = []
}

///|
/// Test helper: Create a simple text-only mock response
fn mock_text_response(text : String) -> MockLLMResponse {
  { text, tool_calls: [], input_tokens: 100, output_tokens: 50 }
}

///|
/// Test helper: Create a mock response with tool calls
fn mock_tool_response(
  text : String,
  tool_calls : Array[(String, String, Json)],
) -> MockLLMResponse {
  { text, tool_calls, input_tokens: 100, output_tokens: 50 }
}

///|
/// Test helper: Create a mock execute_command tool call
fn mock_execute_command(command : String) -> (String, String, Json) {
  let id = "toolu_test_001"
  let name = "execute_command"
  let input : Json = { "command": command }
  (id, name, input)
}

///|
/// Test helper: Create a mock read_file tool call
fn mock_read_file(path : String) -> (String, String, Json) {
  let id = "toolu_test_002"
  let name = "read_file"
  let input : Json = { "path": path }
  (id, name, input)
}

///|
/// Test helper: Create a mock write_file tool call
fn mock_write_file(path : String, content : String) -> (String, String, Json) {
  let id = "toolu_test_003"
  let name = "write_file"
  let input : Json = { "path": path, "content": content }
  (id, name, input)
}

///|
/// Test helper: Create a mock end_elaborate tool call
fn mock_end_elaborate(summary : String) -> (String, String, Json) {
  let id = "toolu_test_004"
  let name = "end_elaborate"
  let input : Json = { "summary": summary }
  (id, name, input)
}

///|
/// Integration test context that bundles all mocks together
struct TestContext {
  llm_client : MockLLMClient
  file_system : MockFileSystem
  output_capture : MockOutputCapture
  chat_history : @session.ChatHistory
}

///|
/// Create a new test context
fn TestContext::new(llm_responses : Array[MockLLMResponse]) -> TestContext {
  {
    llm_client: MockLLMClient::new(llm_responses),
    file_system: MockFileSystem::new(),
    output_capture: MockOutputCapture::new(),
    chat_history: @session.ChatHistory::new(),
  }
}

///|
/// Example test using the framework
test "mock_llm_client_basic" {
  let responses = [mock_text_response("Hello, I'm Jarvis!")]
  let client = MockLLMClient::new(responses)
  let response = client.get_next_response()
  inspect(response is None, content="false")
  match response {
    Some(r) => inspect(r.text, content="Hello, I'm Jarvis!")
    None => @test.fail("Expected a response")
  }
}

///|
test "mock_file_system_operations" {
  let fs = MockFileSystem::new()

  // Initially empty
  inspect(fs.file_exists("/test.txt"), content="false")

  // Add a file
  fs.add_file("/test.txt", "Hello, World!")
  inspect(fs.file_exists("/test.txt"), content="true")

  // Read the file
  match fs.read_file("/test.txt") {
    Some(content) => inspect(content, content="Hello, World!")
    None => @test.fail("Expected file content")
  }

  // Write to the file
  fs.write_file("/test.txt", "Updated content")
  match fs.read_file("/test.txt") {
    Some(content) => inspect(content, content="Updated content")
    None => @test.fail("Expected updated content")
  }

  // Delete the file
  fs.delete_file("/test.txt")
  inspect(fs.file_exists("/test.txt"), content="false")
}

///|
test "mock_file_system_list_files" {
  let fs = MockFileSystem::new()

  // Initially empty
  let files = fs.list_files()
  inspect(files.length(), content="0")

  // Add multiple files
  fs.add_file("/file1.txt", "Content 1")
  fs.add_file("/file2.txt", "Content 2")
  fs.add_file("/dir/file3.txt", "Content 3")

  // List all files
  let files = fs.list_files()
  inspect(files.length(), content="3")
  inspect(files.contains("/file1.txt"), content="true")
  inspect(files.contains("/file2.txt"), content="true")
  inspect(files.contains("/dir/file3.txt"), content="true")

  // Delete one file
  fs.delete_file("/file2.txt")
  let files = fs.list_files()
  inspect(files.length(), content="2")
  inspect(files.contains("/file1.txt"), content="true")
  inspect(files.contains("/file2.txt"), content="false")
  inspect(files.contains("/dir/file3.txt"), content="true")
}

///|
test "mock_output_capture" {
  let capture = MockOutputCapture::new()
  capture.write_stdout("Line 1")
  capture.write_stdout("Line 2")
  capture.write_stderr("Error 1")
  let stdout = capture.get_stdout()
  inspect(stdout.contains("Line 1"), content="true")
  inspect(stdout.contains("Line 2"), content="true")
  let stderr = capture.get_stderr()
  inspect(stderr.contains("Error 1"), content="true")

  // Clear and verify
  capture.clear()
  inspect(capture.get_stdout(), content="")
}

///|
/// Test: Mock LLM client with conversation flow
test "integration: mock llm conversation with tools" {
  let responses = [
    mock_text_response("First response"),
    mock_text_response("Second response"),
    mock_text_response("Third response"),
  ]
  let client = MockLLMClient::new(responses)

  // First request
  match client.get_next_response() {
    Some(r) => {
      inspect(r.text, content="First response")
      inspect(client.request_count, content="1")
    }
    None => @test.fail("Expected first response")
  }

  // Second request
  match client.get_next_response() {
    Some(r) => {
      inspect(r.text, content="Second response")
      inspect(client.request_count, content="2")
    }
    None => @test.fail("Expected second response")
  }

  // Third request
  match client.get_next_response() {
    Some(r) => inspect(r.text, content="Third response")
    None => @test.fail("Expected third response")
  }

  // No more responses
  match client.get_next_response() {
    Some(_) => @test.fail("Should have no more responses")
    None => inspect(client.request_count, content="3")
  }
}

///|
test "integration: test context with all mocks" {
  let responses = [mock_text_response("Hello")]
  let ctx = TestContext::new(responses)

  // Test LLM client
  match ctx.llm_client.get_next_response() {
    Some(r) => inspect(r.text, content="Hello")
    None => @test.fail("Expected response")
  }

  // Test file system
  ctx.file_system.write_file("/test.txt", "content")
  inspect(ctx.file_system.file_exists("/test.txt"), content="true")

  // Test output capture
  ctx.output_capture.write_stdout("test output")
  inspect(
    ctx.output_capture.get_stdout().contains("test output"),
    content="true",
  )

  // Test chat history
  let msg = @types.Message::new("user", "test message")
  ctx.chat_history.add(msg)
  inspect(ctx.chat_history.messages.length(), content="1")
  inspect(ctx.chat_history.messages[0].role, content="user")
  let text = ctx.chat_history.messages[0].get_text()
  inspect(text, content="test message")
}

///|
test "mock_llm_client_record_messages" {
  let responses = [
    mock_text_response("Response 1"),
    mock_text_response("Response 2"),
  ]
  let client = MockLLMClient::new(responses)

  // Create test messages
  let messages : Array[@types.Message] = [
    @types.Message::new("user", "Hello"),
    @types.Message::new("assistant", "Hi there!"),
  ]

  // Record the messages
  client.record_messages(messages)

  // Verify the messages were recorded
  inspect(client.last_messages.length(), content="2")
  inspect(client.last_messages[0].role, content="user")
  let text0 = client.last_messages[0].get_text()
  inspect(text0, content="Hello")
  inspect(client.last_messages[1].role, content="assistant")
  let text1 = client.last_messages[1].get_text()
  inspect(text1, content="Hi there!")
}

///|
test "mock_llm_client_track_requests" {
  let responses = [
    mock_text_response("Response 1"),
    mock_text_response("Response 2"),
    mock_text_response("Response 3"),
  ]
  let client = MockLLMClient::new(responses)

  // Initially no requests
  inspect(client.request_count, content="0")

  // Make first request
  client.get_next_response() |> ignore
  inspect(client.request_count, content="1")

  // Make second request
  client.get_next_response() |> ignore
  inspect(client.request_count, content="2")

  // Make third request
  client.get_next_response() |> ignore
  inspect(client.request_count, content="3")

  // No more responses
  match client.get_next_response() {
    Some(_) => @test.fail("Expected no more responses")
    None => ()
  }
  inspect(client.request_count, content="3") // Count shouldn't increase
}

///|
test "mock_llm_client_message_history" {
  let responses = [mock_text_response("OK")]
  let client = MockLLMClient::new(responses)

  // Record first conversation
  let messages1 : Array[@types.Message] = [@types.Message::new("user", "First message")]
  client.record_messages(messages1)
  inspect(client.last_messages.length(), content="1")
  let text1 = client.last_messages[0].get_text()
  inspect(text1, content="First message")

  // Record second conversation (should replace)
  let messages2 : Array[@types.Message] = [
    @types.Message::new("user", "Second message"),
    @types.Message::new("assistant", "Reply"),
  ]
  client.record_messages(messages2)
  inspect(client.last_messages.length(), content="2")
  let text2_0 = client.last_messages[0].get_text()
  inspect(text2_0, content="Second message")
  let text2_1 = client.last_messages[1].get_text()
  inspect(text2_1, content="Reply")
}

///|
test "mock_tool_helpers" {
  // Test mock_execute_command
  let (id1, name1, input1) = mock_execute_command("ls -la")
  inspect(id1, content="toolu_test_001")
  inspect(name1, content="execute_command")
  match input1 {
    Object(map) =>
      match map.get("command") {
        Some(String(cmd)) => inspect(cmd, content="ls -la")
        _ => @test.fail("Expected command string")
      }
    _ => @test.fail("Expected JSON object")
  }

  // Test mock_read_file
  let (id2, name2, input2) = mock_read_file("/test.txt")
  inspect(id2, content="toolu_test_002")
  inspect(name2, content="read_file")
  match input2 {
    Object(map) =>
      match map.get("path") {
        Some(String(p)) => inspect(p, content="/test.txt")
        _ => @test.fail("Expected path string")
      }
    _ => @test.fail("Expected JSON object")
  }

  // Test mock_write_file
  let (id3, name3, input3) = mock_write_file("/output.txt", "Hello")
  inspect(id3, content="toolu_test_003")
  inspect(name3, content="write_file")
  match input3 {
    Object(map) => {
      match map.get("path") {
        Some(String(p)) => inspect(p, content="/output.txt")
        _ => @test.fail("Expected path string")
      }
      match map.get("content") {
        Some(String(c)) => inspect(c, content="Hello")
        _ => @test.fail("Expected content string")
      }
    }
    _ => @test.fail("Expected JSON object")
  }

  // Test mock_end_elaborate
  let (id4, name4, input4) = mock_end_elaborate("Task completed successfully")
  inspect(id4, content="toolu_test_004")
  inspect(name4, content="end_elaborate")
  match input4 {
    Object(map) =>
      match map.get("summary") {
        Some(String(s)) => inspect(s, content="Task completed successfully")
        _ => @test.fail("Expected summary string")
      }
    _ => @test.fail("Expected JSON object")
  }
}

///|
test "mock_tool_response_with_tools" {
  // Create a response with tool calls
  let tool_calls = [mock_execute_command("pwd"), mock_read_file("/config.json")]
  let response = mock_tool_response("Let me check that", tool_calls)
  inspect(response.text, content="Let me check that")
  inspect(response.tool_calls.length(), content="2")
  inspect(response.input_tokens, content="100")
  inspect(response.output_tokens, content="50")

  // Verify first tool call
  let (id1, name1, _) = response.tool_calls[0]
  inspect(id1, content="toolu_test_001")
  inspect(name1, content="execute_command")

  // Verify second tool call
  let (id2, name2, _) = response.tool_calls[1]
  inspect(id2, content="toolu_test_002")
  inspect(name2, content="read_file")
}
