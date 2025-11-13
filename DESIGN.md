# Jarvis - 智能电脑助手

## 1. 项目概述

Jarvis 是一个智能的命令行助手，使用 MoonBit 开发，通过 Claude API 理解自然语言并执行系统命令。

### 核心特性
- **自然语言交互**: 通过 Claude API 理解用户意图
- **工具调用**: 自动执行 shell 命令
- **对话管理**: 智能的历史记录、上下文管理和记忆系统
- **命令行编辑**: 完整的 readline 功能支持
- **流式响应**: 实时显示 LLM 输出
- **执行模式**: 支持 `-e` 参数执行单个命令后退出
- **使用统计**: 跟踪 token 使用和成本

## 2. 系统架构

Jarvis 采用模块化分层架构：

### 2.1 项目结构
```
src/
├── config.mbt       # 配置和错误类型定义
├── types.mbt        # 核心数据类型 (Message, Tool, ToolCall)
├── api_types.mbt    # API 请求/响应类型
├── api.mbt          # HTTP API 调用 (流式/非流式)
├── storage.mbt      # 文件存储和记忆系统
├── chat.mbt         # 对话历史管理
├── tools.mbt        # 工具执行逻辑
├── commands.mbt     # 系统命令处理
├── readline.mbt     # 命令行编辑
├── tty.mbt          # 终端控制 (MoonBit 接口)
├── tty.c            # 终端控制 (C 实现)
└── main.mbt         # 主程序入口和循环
```

### 2.2 架构层次

1. **命令行界面层** - 负责用户交互
   - readline 实现：命令历史、行编辑、UTF-8 字符支持
   - TTY 控制：raw mode、终端尺寸检测
   - 彩色输出和分隔线

2. **核心控制层** - 主循环和命令分发
   - `chat_loop()` 主循环读取用户输入
   - 命令解析：识别系统命令（`:help`, `:model`, `:cost` 等）
   - 输入分发：区分系统命令和普通对话
   - 对话历史管理：自动总结和裁剪

3. **LLM 推理层** - 理解和决策
   - 通过 Claude API 调用 LLM
   - 支持流式和非流式响应
   - 理解用户自然语言意图
   - 决策是否需要工具调用
   - 生成最终回复

4. **工具执行层** - 执行具体操作
   - 执行 shell 命令（通过 `sh -c`）
   - 捕获命令输出和错误
   - 返回结果给 LLM 继续推理

5. **存储层** - 持久化和记忆
   - 对话历史保存/加载
   - 记忆系统：跨会话知识保留
   - 智能记忆搜索和注入

## 3. 核心模块

### 3.1 配置模块 (config.mbt)
```moonbit
struct Config {
  base_url : String      // Claude API URL
  auth_token : String    // API Token
}
```
从环境变量加载：
- `JARVIS_BASE_URL` - API 端点 (默认 Claude API)
- `JARVIS_AUTH_TOKEN` - API 认证令牌

颜色定义：
- `JARVIS_COLOR` - Jarvis 输出颜色 (cyan + bold)
- `TOOL_COLOR` - 工具调用颜色 (green)
- `SEPARATOR_COLOR` - 分隔线颜色 (dim)

### 3.2 消息系统 (types.mbt, chat.mbt)
```moonbit
struct Message {
  role : String
  content : String?
  tool_calls : Array[ToolCall]?
  tool_call_id : String?
  name : String?
}

struct ChatHistory {
  messages : Array[Message]
  max_context_tokens : Int
  mut current_model : String
  usage_stats : UsageStats
}
```

**历史管理策略**:
- 触发条件: 超过 80% max_context_tokens (3200/4000)
- 保留: 首条消息 + 最近 8 条消息
- 中间部分: 通过 LLM 总结成摘要
- Token 估算: ~4 字符 = 1 token

**对话持久化**:
- 自动保存到 `~/.jarvis/conversations/<timestamp>.json`
- 支持加载历史对话继续

### 3.3 工具系统 (tools.mbt)
```moonbit
struct Tool {
  name : String
  description : String
  input_schema : Json
}

struct ToolCall {
  id : String
  type_ : String
  function : FunctionCall
}
```

**已实现工具**:
- `execute_command`: 执行 shell 命令
  - 参数: `{ "command": "shell command" }`
  - 返回: 命令输出或错误信息
  - 使用 Claude API 的 tool_use 格式

**工具调用流程**:
1. 用户输入 → LLM 分析
2. LLM 决定调用工具 → 返回 tool_use content blocks
3. 执行工具 → 获取结果
4. 结果返回 LLM → 生成最终回复
5. 最多迭代 10 次防止死循环

### 3.4 记忆系统 (storage.mbt)
**功能**:
- 自动保存重要信息到 `~/.jarvis/memories/`
- 智能搜索相关记忆
- 关键词提取和匹配
- 上下文注入

**记忆格式**:
```json
{
  "timestamp": "2025-11-13T10:30:00",
  "content": "用户偏好使用 vim 编辑器",
  "context": "工具选择和配置"
}
```

### 3.5 命令行编辑 (readline.mbt)

**Readline 功能**:
- 命令历史: 上下箭头导航，自动去重
- 光标移动: 左右箭头
- 单词跳转: Option + 左右箭头
- 行首/尾: Command + 左右箭头 / Home/End
- 删除: Backspace / Delete / Ctrl+D
- 单词删除: Option + Delete
- 整行删除: Command + Delete
- 取消: Ctrl+C
- UTF-8 支持: 正确处理 CJK 字符宽度

**终端控制 (tty.mbt / tty.c)**:
- Raw mode 设置 (通过 termios)
- 窗口尺寸获取 (用于绘制分隔线)

## 4. API 通信 (api.mbt, api_types.mbt)

### 4.1 请求类型
```moonbit
struct ChatRequest {
  model : String
  messages : Array[Message]
  max_tokens : Int
  stream : Bool
  tools : Array[Tool]?
  system : String?
}
```

### 4.2 响应类型
```moonbit
struct ChatResponse {
  id : String
  type_ : String
  role : String
  content : Array[ContentBlock]
  model : String
  stop_reason : String?
  usage : ResponseUsage?
}

struct ContentBlock {
  type_ : String      // "text" | "tool_use"
  text : String?
  id : String?
  name : String?
  input : Json?
}
```

### 4.3 API 函数
- `send_chat_request_with_tools()` - 非流式请求，支持工具调用
- `send_streaming_chat_request()` - 流式请求，实时输出
- `parse_url()` - URL 解析辅助函数

## 5. 系统命令 (commands.mbt)

| 命令 | 说明 |
|------|------|
| `:help`, `:h` | 显示帮助 |
| `:model [name]` | 查看/切换模型 |
| `:models` | 列出可用模型 |
| `:cost` | 显示使用统计和成本 |
| `:summarize`, `:sum` | 手动生成对话总结并保存为 Markdown |
| `:clear`, `:c` | 清空对话历史 |
| `:exit`, `:quit`, `:q` | 退出 |
| `exit`, `quit` | 退出 (兼容) |

**Summarize 功能**:
- `:summarize` - 手动总结，生成详细 Markdown 文档
  - 保存为 `~/.jarvis/<timestamp>_<title>.json` 和 `.md`
  - 包含: 对话主题、关键要点、重要决定、需要记住的信息
- 自动总结 - 当 token 超过 80% 上下文限制时触发
  - 保留第 1 条消息 + 最近 8 条消息
  - 中间消息压缩为简短摘要
  - 自动创建新的 `conv_XXX.json` 文件

**支持的模型**:
- `claude-sonnet-4-5-20250929` (默认)
- `claude-haiku-4-5-20251001`
- `claude-opus-4-1-20250805`

**成本计算**:
- Sonnet 4.5: $3/M input, $15/M output
- Haiku 4.5: $1/M input, $5/M output
- Opus 4: $15/M input, $75/M output

## 6. 命令行参数

使用 `TheWaWaR/clap` 库进行参数解析：

```bash
jarvis [OPTIONS] [PROMPT]...

Options:
  -e, --execute  Execute a single prompt and exit
  -h, --help     Print help

Arguments:
  [PROMPT]...    Prompt to execute (requires -e flag)
```

**使用示例**:
```bash
# 交互模式
jarvis

# 执行单个命令
jarvis -e "What's the current directory?"

# 多词 prompt
jarvis -e "List all .mbt files in src directory"
```

## 7. 错误处理

```moonbit
suberror JarvisError {
  EnvVarNotSet(String)      // 环境变量未设置
  HttpError(String)         // HTTP 请求失败
  JsonParseError(String)    // JSON 解析错误
  StringViewError(String)   // 字符串处理错误
}
```

所有错误都显示清晰的错误消息，不会导致程序崩溃。

## 8. 使用示例

### 基本对话
```bash
$ jarvis
Jarvis: Hello! I'm Jarvis, your AI assistant. How can I help you today?

> What's the current directory?
Jarvis: I'll execute a command to check the current directory.
Jarvis: Executing tool: execute_command
  Command: pwd
  Output: /Users/zhengyu/Documents/projects/jarvis

Jarvis: The current directory is /Users/zhengyu/Documents/projects/jarvis
```

### 系统命令
```bash
> :model
Jarvis: Current model: claude-sonnet-4-5-20250929

> :cost
=== Usage Statistics ===
Total requests: 5
Total tokens: 1234 (987 input + 247 output)
Estimated cost: $0.0074

> :clear
Jarvis: Conversation history cleared
```

### 执行模式
```bash
$ jarvis -e "List all .mbt files"
Jarvis: Processing: List all .mbt files
Jarvis: Executing tool: execute_command
  Command: find . -name "*.mbt"

Jarvis: Found 11 MoonBit files:
  - src/api_types.mbt
  - src/api.mbt
  - src/chat.mbt
  ...
```

## 9. 技术实现

### 9.1 依赖包
```json
{
  "deps": {
    "moonbitlang/async": "0.12.0",
    "moonbitlang/x": "0.4.36",
    "TheWaWaR/clap": "0.2.6"
  },
  "import": [
    "moonbitlang/async",
    "moonbitlang/async/stdio",
    "moonbitlang/async/http",
    "moonbitlang/async/io",
    "moonbitlang/async/process",
    "moonbitlang/x/sys",
    "TheWaWaR/clap"
  ],
  "native-stub": ["tty.c"]
}
```

### 9.2 JSON 处理
- 自动序列化: `derive(ToJson, FromJson)`
- 字段重命名: `type_` → `"type"` 避免关键字冲突
- Option 类型: 自动处理 JSON `null` 值
- Json 类型: `input: Json?` 保存原始 JSON 对象

### 9.3 异步处理
所有 I/O 操作都是异步的:
- `async fn main()`
- `async fn chat_loop()`
- `async fn handle_tool_calls()`
- `async fn execute_shell_command()`
- `async fn send_chat_request_with_tools()`
- `async fn send_streaming_chat_request()`

## 10. 代码质量

### 10.1 代码统计
- 总文件数: 12 个源文件 (11 .mbt + 1 .c)
- 警告数: 5 个 (全部为未读取的 API 响应字段)
- 错误数: 0

### 10.2 重构历史
1. **模块化拆分**: 从单个 1838 行文件拆分为 11 个模块
2. **消除重复**: 提取 `parse_url()` 辅助函数
3. **简化 JSON**: 使用 `derive(FromJson)` 替代手动实现
4. **命令行解析**: 使用 clap 库替代手动解析
5. **代码格式化**: 使用 `moon fmt` 统一格式

### 10.3 重构原则
- 单一职责: 每个模块只负责一个领域
- 职责分离: API、存储、UI、逻辑分离
- DRY: 消除重复代码
- 自动化: 优先使用 derive 宏

## 11. 已知限制

1. ~~**无持久化**: 对话历史在退出后丢失~~ ✅ 已实现
2. **单线程**: 工具调用是串行的
3. **简单权限**: 没有细粒度权限控制
4. **Claude API**: 仅支持 Claude API 格式

## 12. 安装和运行

### 12.1 环境配置
```bash
export JARVIS_BASE_URL="https://api.anthropic.com"
export JARVIS_AUTH_TOKEN="your-api-key"
```

### 12.2 构建
```bash
moon build
```

### 12.3 安装
```bash
./install.sh
```

### 12.4 运行
```bash
# 交互模式
jarvis

# 执行模式
jarvis -e "your prompt"
```

## 13. 参考实现

### Maria 项目
- **项目**: https://github.com/moonbitlang/maria
- **版本**: f5d4629e74323aff79108ecfd8c3531f1562f3b9
- **参考内容**:
  - TTY 模块 (`tty.mbt`, `tty.c`) - 终端控制
  - Readline 模块 - 行编辑和历史记录

### 实现差异
- 简化错误处理 (直接 abort vs errno)
- 裁剪功能 (只保留基本行编辑)
- 扩展功能 (UTF-8、单词跳转、行跳转、整行删除)
- 适配 Claude API 格式

---

**项目版本**: v0.1.0
**文档版本**: 2.0.0
**最后更新**: 2025-11-13
