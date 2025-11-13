# Jarvis - 智能电脑助手

## 1. 项目概述

Jarvis 是一个智能的命令行助手，使用 MoonBit 开发，通过 LLM 理解自然语言并执行系统命令。

### 核心特性
- **自然语言交互**: 通过 LLM (Claude/GPT) 理解用户意图
- **工具调用**: 自动执行 shell 命令
- **对话管理**: 智能的历史记录和上下文管理
- **命令行编辑**: 完整的 readline 功能支持

## 2. 系统架构

```
┌─────────────────────────────────────┐
│         命令行界面 (readline)        │
│  (历史记录、行编辑、UTF-8支持)       │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│          核心控制 (chat_loop)        │
│  - 命令解析 (:help, :model 等)      │
│  - 用户输入处理                      │
│  - 对话历史管理                      │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│       LLM 推理 (OpenAI API)          │
│  - 意图理解                          │
│  - 工具调用决策                      │
│  - 多轮对话                          │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│       工具执行 (Shell命令)           │
│  - 命令执行                          │
│  - 结果捕获                          │
└─────────────────────────────────────┘
```

## 3. 核心模块

### 3.1 配置模块 (Config)
```moonbit
struct Config {
  base_url : String      // LLM API URL
  auth_token : String    // API Token
}
```
从环境变量加载：
- `JARVIS_BASE_URL`
- `JARVIS_AUTH_TOKEN`

### 3.2 消息系统 (Message / ChatHistory)
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
}
```

**历史管理策略**:
- 触发条件: 超过 80% max_context_tokens (3200/4000)
- 保留: 首条消息 + 最近 8 条消息
- 中间部分: 通过 LLM 总结成摘要
- Token 估算: ~4 字符 = 1 token

### 3.3 工具系统 (Tool)
```moonbit
struct Tool {
  type_ : String          // "function"
  function : FunctionDef
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

**工具调用流程**:
1. 用户输入 → LLM 分析
2. LLM 决定调用工具 → 返回 tool_calls
3. 执行工具 → 获取结果
4. 结果返回 LLM → 生成最终回复
5. 最多迭代 10 次防止死循环

### 3.4 命令行编辑 (readline.mbt)

**Readline 功能**:
- 命令历史: 上下箭头导航，自动去重
- 光标移动: 左右箭头
- 单词跳转: Option + 左右箭头
- 行首/尾: Command + 左右箭头 / Home/End
- 删除: Backspace / Delete / Ctrl+D
- 取消: Ctrl+C
- UTF-8 支持: 正确处理 CJK 字符宽度

**终端控制 (tty.mbt / tty.c)**:
- Raw mode 设置 (通过 termios)
- 窗口尺寸获取 (用于绘制分隔线)

## 4. 系统命令

| 命令 | 说明 |
|------|------|
| `:help`, `:h` | 显示帮助 |
| `:model [name]` | 查看/切换模型 |
| `:models` | 列出可用模型 |
| `:clear`, `:c` | 清空对话历史 |
| `:exit`, `:quit`, `:q` | 退出 |
| `exit`, `quit` | 退出 (兼容) |

**支持的模型**:
- `claude-sonnet-4-5-20250929` (默认)
- `gpt-3.5-turbo`
- `gpt-4`
- `gpt-4-turbo`
- `gpt-4o`

## 5. 错误处理

```moonbit
suberror JarvisError {
  EnvVarNotSet(String)      // 环境变量未设置
  HttpError(String)         // HTTP 请求失败
  JsonParseError(String)    // JSON 解析错误
  StringViewError(String)   // 字符串处理错误
}
```

所有错误都显示清晰的错误消息，不会导致程序崩溃。

## 6. 代码结构

### 主要函数
- `chat_loop()` - 主循环 (42 行)
- `handle_user_input()` - 处理用户输入 (23 行)
- `handle_tool_calls()` - 工具调用循环 (86 行)
- `handle_command()` - 处理系统命令 (83 行)
- `is_exit_command()` - 检查退出命令 (3 行)

### 重构原则
- 单一职责: 每个函数只做一件事
- 职责分离: 命令处理、工具调用、用户输入分开
- 错误集中: 错误处理集中在各自的函数内

## 7. 使用示例

### 基本对话
```bash
$ ./target/jarvis
Jarvis: Hello! I'm Jarvis, your AI assistant. How can I help you today?

> What's the current directory?
Jarvis: Executing tool: execute_command
Jarvis: The current directory is /Users/zhengyu/Documents/projects/jarvis
```

### 系统命令
```bash
> :model
Jarvis: Current model: claude-sonnet-4-5-20250929

> :model gpt-4
Jarvis: Model changed to: gpt-4

> :clear
Jarvis: Conversation history cleared
```

### 工具调用
```bash
> List all .mbt files
Jarvis: Executing tool: execute_command
Jarvis: Found 3 MoonBit files:
  - jarvis.mbt
  - readline.mbt
  - tty.mbt
```

## 8. 技术实现

### 依赖包
```json
{
  "import": [
    "moonbitlang/async",
    "moonbitlang/async/stdio",
    "moonbitlang/async/http",
    "moonbitlang/async/io",
    "moonbitlang/async/process",
    "moonbitlang/x/sys"
  ],
  "native-stub": ["tty.c"]
}
```

### JSON 处理
- 自动序列化: `derive(ToJson, FromJson)`
- 字段重命名: `type_` → `"type"` 避免关键字冲突
- 手动 FromJson: `ChatResponseMessage` 处理 null 值
- JSON 字面量: 直接用 MoonBit 语法构造 JSON

### 异步处理
所有 I/O 操作都是异步的:
- `async fn chat_loop()`
- `async fn handle_tool_calls()`
- `async fn execute_shell_command()`
- `async fn readline_simple()`

## 9. 已知限制

1. **无持久化**: 对话历史在退出后丢失
2. **单线程**: 工具调用是串行的
3. **简单权限**: 没有细粒度权限控制
4. **API 依赖**: 需要兼容 OpenAI 的 API

## 10. 参考实现

### Maria 项目
- **项目**: https://github.com/moonbitlang/maria
- **版本**: f5d4629e74323aff79108ecfd8c3531f1562f3b9
- **参考内容**:
  - TTY 模块 (`tty.mbt`, `tty.c`) - 终端控制
  - Readline 模块 - 行编辑和历史记录

### 实现差异
- 简化错误处理 (直接 abort vs errno)
- 裁剪功能 (只保留基本行编辑)
- 扩展功能 (UTF-8、单词跳转、行跳转)

---

**项目版本**: v0.1.0
**文档版本**: 1.1.0
**最后更新**: 2025-11-13
