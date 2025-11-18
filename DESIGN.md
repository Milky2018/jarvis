# Jarvis - Design Documentation

## 1. Design Philosophy

**Core Principles:**
- **Natural Interaction**: Users communicate in plain language, not command syntax
- **Autonomous Capability**: Jarvis can take actions and make decisions independently
- **Transparency**: All tool executions are visible to the user
- **Context Awareness**: Maintains conversation history and learns from interactions
- **Graceful Degradation**: Handles errors without crashing

## 2. Architecture

### 2.1 Layered Design

```
User Interface (readline, terminal control)
         ↓
Control Layer (main loop, command dispatch)
         ↓
LLM Reasoning (API communication, tool selection)
         ↓
Execution (tool execution, shell commands)
         ↓
Storage (conversation persistence)
```

### 2.2 Key Modules

- **UI**: `readline.mbt`, `tty.mbt/c`, `config.mbt`
- **Control**: `main.mbt`, `interact.mbt`, `commands.mbt`
- **LLM**: `api.mbt`, `api_types.mbt`, `chat.mbt`
- **Execution**: `tools.mbt`, `types.mbt`
- **Storage**: `storage.mbt`

## 3. Core Design Concepts

### 3.1 Tool-Based Architecture

Jarvis uses **tool calling** as the primary action mechanism:

- Structured output from LLM (JSON schema)
- Type-safe execution
- Easy to extend
- Clear separation between reasoning and action

**Available Tools:**
- `execute_command`: Run shell commands
- `read_file`: Read file contents with pagination
- `write_file`: Create or overwrite files
- `grep`: Search for patterns in files
- `glob`: Find files matching patterns
- `end_elaborate`: Signal task completion
- `end_play_mode`: Exit autonomous mode (play mode only)

### 3.2 Context Management

**Problem:** Limited context window (200k tokens) vs. long conversations

**Solution:** Tiered retention with summarization

```
[First Message] [Summarized Middle] [Recent 8 Messages]
```

**Triggers:**
- Auto: 80% context usage (160k/200k tokens)
- Manual: `:summarize` command

**File Management:**
- Each conversation: `~/.jarvis/conv_XXX.json`
- Auto-increment on summarization
- Latest file loaded on startup

### 3.3 Play Mode Design

**Philosophy:** Give Jarvis freedom to explore autonomously

**Key Decisions:**
1. **Tool-Based Exit**: Jarvis calls `end_play_mode` to stop
   - More reliable than text pattern matching

2. **No Forced Prompts**: No "What next?" between iterations
   - Allows natural conclusion of activities

3. **Budget Management**: Pre-set spending limit for safety

4. **Playground Isolation**: `~/.jarvis/playground` for experiments

### 3.4 Auto-Continue Workflow

**Philosophy:** Let Jarvis work autonomously until completion

**Behavior:**
- Simple responses: Returns control immediately
- Tool-based tasks: Continues until `end_elaborate` is called
- Prevents infinite loops on conversational responses

### 3.5 Async Architecture

All I/O is asynchronous for responsiveness:
- Non-blocking network requests
- Queue-based readline communication
- Responsive to interrupts (Ctrl+C)

### 3.6 Error Handling

**Principle:** Errors inform, don't crash

```moonbit
suberror JarvisError {
  EnvVarNotSet(String)
  HttpError(String)
  JsonParseError(String)
  StringViewError(String)
  ExitRequested
}

suberror JarvisSignal {
  InterruptByUser
  ActionFinished
  PlayModeEnded
}
```

## 4. Technical Decisions

### 4.1 Why MoonBit?

- Modern syntax and strong typing
- First-class async support
- Automatic JSON serialization
- Native compilation for performance

### 4.2 Why Claude API?

- Native tool calling support
- 200k token context window
- Excellent reasoning quality
- Streaming support

### 4.3 Custom Readline

**Decision:** Implement rather than use library

**Rationale:**
- Full control over behavior
- UTF-8 and CJK character support
- Bracketed paste mode
- No external dependencies

## 5. User Experience

### 5.1 Visual Feedback

**Color Coding:**
- Cyan + Bold: Jarvis speaking
- Red: Errors
- Gray: Separators
- Green/Yellow/Red: Token warnings

### 5.2 Keyboard Shortcuts

Standard terminal conventions:
- Ctrl+C: Interrupt
- Ctrl+D: Exit
- Arrows: History/navigation
- Option/Command: Word/line operations

## 6. Extension Points

### Add New Tools

1. Create tool struct implementing `ToolImpl` trait
2. Add to `get_available_tools()`
3. Test with integration tests

### Add New Commands

1. Add case in `handle_command()`
2. Update `:help` text
3. Implement handler

## 7. Security

**Command Execution:**
- All commands visible before execution
- User in control (not automated)
- Play mode confined to playground

**API Keys:**
- Environment variables only
- Never logged or displayed

## 8. Known Limitations

1. Single-threaded tool execution
2. No command sandboxing
3. Claude API format only
4. No undo for commands

## 9. Testing Strategy

**Philosophy:** Test real behavior, not mocks

- Integration tests use actual tools and execution
- Mock only the LLM layer for predictability
- Tests colocated with implementation
- 39 tests covering core functionality

---

**Version**: v0.1.0 | **Updated**: 2025-11-18

*For implementation details, see source code. For usage, see README.md.*
