# Jarvis - Intelligent Computer Assistant

Jarvis is an intelligent AI assistant built with MoonBit, enabling natural language conversation and system command execution through LLM integration.

## Features

- ✅ Natural language conversation interface
- ✅ OpenAI-compatible API support
- ✅ Tool calling for shell command execution
- ✅ Conversation history persistence
- ✅ Smart context management with auto-summarization
- ✅ Command-line history navigation (arrow keys)
- ✅ Advanced line editing (cursor movement, word jumping, etc.)
- ✅ Streaming responses with real-time output
- ✅ Token usage tracking and cost estimation
- ✅ Execute mode (`-e` flag) for single commands
- ✅ Play mode for autonomous exploration
- ✅ Multi-model support (Claude Sonnet/Haiku/Opus)
- ✅ Auto-continue workflow until task completion
- ✅ Comprehensive test coverage with integration tests

## Quick Start

### Prerequisites

- MoonBit compiler and toolchain
- An OpenAI-compatible LLM API service (Claude API recommended)

### Configuration

Set the following environment variables:

```bash
export JARVIS_BASE_URL="https://api.anthropic.com/v1/messages"
export JARVIS_AUTH_TOKEN="your-api-key-here"
```

Or for local LLM services:

```bash
export JARVIS_BASE_URL="http://localhost:11434/v1/chat/completions"
export JARVIS_AUTH_TOKEN="ollama"
```

### Build and Run

```bash
# Build the project
moon build

# Run in interactive mode
moon run src

# Or run the compiled executable
./target/native/release/build/src/src.exe

# Execute a single command and exit
moon run src -- -e "What is the current directory?"
```

### Installation

```bash
./install.sh
# This installs the binary to ~/bin/jarvis
```

## Usage

### Interactive Mode

```bash
$ jarvis
Jarvis: Hello! I'm Jarvis, your AI assistant. How can I help you today?
(Type 'exit' or 'quit' to end the conversation)

[1030/200000 tokens (0%)]
────────────────────────────────────────────────────────────────────────────────
> List all .mbt files in the src directory
Jarvis: Executing: ls src/*.mbt
# Output displayed...

> exit
Jarvis: Goodbye!
```

### Execute Mode

Execute a single command and exit:

```bash
$ jarvis -e "What is the current directory?"
Jarvis: Processing: What is the current directory?
Jarvis: Executing: pwd
/path/to/current/directory
```

### Built-in Commands

| Command | Description |
|---------|-------------|
| `:help`, `:h` | Show help message |
| `:model [name]` | View or set current model |
| `:models` | List available models |
| `:cost` | Show API usage statistics and estimated cost |
| `:summarize`, `:sum` | Manually summarize and save conversation |
| `:play [budget]` | Start autonomous exploration mode (default budget: $10) |
| `:clear`, `:c` | Clear conversation history |
| `:exit`, `:quit`, `:q` | Exit Jarvis |
| `exit`, `quit` | Exit (alternative) |

### Keyboard Shortcuts

- **Arrow keys**: Navigate command history (up/down), move cursor (left/right)
- **Option + Left/Right**: Jump by word
- **Command/Ctrl + A**: Move to start of line
- **Command/Ctrl + E**: Move to end of line
- **Home/End**: Move to start/end of line
- **Backspace/Delete**: Delete characters
- **Option + Delete**: Delete word backward
- **Command + Delete**: Delete to start of line
- **Ctrl + C**: Cancel current line
- **Ctrl + D**: Exit (when line is empty)

## Key Features

### Context Management

Jarvis automatically manages conversation context:
- **Token tracking**: Real-time display of token usage before each input
- **Color-coded warnings**:
  - Green: < 30% of context
  - Yellow: 30-79% of context
  - Red: ≥ 80% (auto-summarization will trigger)
- **Auto-summarization**: When context exceeds 80%, older messages are summarized
- **Manual summarization**: Use `:summarize` to create a detailed Markdown summary

### Play Mode

Let Jarvis explore autonomously with a budget:

```bash
> :play 10
Jarvis: Entering play mode with budget: $10
Jarvis: Play mode initialized. Jarvis is now autonomous!
```

In play mode, Jarvis can:
- Freely explore and experiment within `~/.jarvis/playground`
- Execute any shell commands
- Create files, scripts, or projects
- Learn and try new things
- End the session by calling the `end_play_mode` tool

### Conversation Persistence

All conversations are automatically saved:
- Location: `~/.jarvis/conv_001.json`, `conv_002.json`, etc.
- Automatic loading of the latest conversation on startup
- Summaries saved as: `~/.jarvis/<timestamp>_<title>.md`

## Supported Models

- `claude-sonnet-4-5-20250929` (default) - $3/$15 per 1M tokens
- `claude-haiku-4-5-20251001` - $0.8/$4 per 1M tokens
- `claude-opus-4-1-20250805` - $15/$75 per 1M tokens

Switch models with `:model <name>` command.

## Development

### Run Tests

```bash
moon test
```

### Code Formatting

```bash
moon fmt
```

### Type Checking

```bash
moon check
```

## Design Philosophy

See [DESIGN.md](DESIGN.md) for the complete design philosophy and architecture details.

## License

Apache-2.0 License

## Contributing

Issues and Pull Requests are welcome!
