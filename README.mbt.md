# Jarvis - 智能电脑助手

Jarvis 是一个基于 MoonBit 开发的智能 AI 助手,能够通过自然语言与 LLM 进行对话交互。

## 功能特性

- ✅ 自然语言对话交互
- ✅ 支持 OpenAI 兼容的 API
- ✅ 会话历史记录
- ✅ 命令行历史记录(上下箭头导航)
- ✅ 行内编辑(左右箭头移动光标)
- ✅ 错误处理和重试机制
- ✅ 环境变量配置

## 快速开始

### 前置要求

- MoonBit 编译器和工具链
- 一个 OpenAI 兼容的 LLM API 服务

### 安装依赖

```bash
moon add moonbitlang/async
moon add moonbitlang/x
```

### 配置环境变量

设置以下环境变量:

```bash
export JARVIS_BASE_URL="https://api.openai.com/v1/chat/completions"
export JARVIS_AUTH_TOKEN="your-api-token-here"
```

或者对于本地 LLM:

```bash
export JARVIS_BASE_URL="http://localhost:11434/v1/chat/completions"
export JARVIS_AUTH_TOKEN="ollama"
```

### 构建和运行

```bash
# 构建项目
moon build

# 运行
moon run .

# 或者直接运行编译后的可执行文件
./target/native/release/build/jarvis.exe
```

## 使用示例

```
$ moon run .
Jarvis: Hello! I'm Jarvis, your AI assistant. How can I help you today?
(Type 'exit' or 'quit' to end the conversation)

> 你好,请介绍一下你自己
Jarvis: 你好!我是 Jarvis,一个 AI 助手。我可以帮助你回答问题、提供信息和进行对话...

> exit
Jarvis: Goodbye!
```

## 项目结构

```
jarvis/
├── jarvis.mbt              # 主程序代码(包含所有核心功能)
├── readline.mbt            # 终端行编辑和历史记录功能
├── jarvis_test.mbt         # 测试文件
├── moon.mod.json           # 模块配置
├── moon.pkg.json           # 包配置(is-main: true)
├── DESIGN.md               # 设计文档
└── README.md               # 本文件
```

## 核心模块

### Config
配置管理,从环境变量读取 API 地址和认证令牌。

### Message
聊天消息的数据结构,支持 JSON 序列化。

### ChatHistory
管理对话历史记录。

### ChatRequest/ChatResponse
LLM API 的请求和响应结构,使用 `derive(ToJson, FromJson)` 自动处理 JSON。

### CommandHistory
管理命令行历史记录,支持上下箭头导航和自动去重。

### LineEditor
提供终端行编辑功能,支持光标移动、字符插入/删除等操作。

## 开发

### 运行测试

```bash
moon test
```

### 代码格式化

```bash
moon fmt
```

### 检查代码

```bash
moon check
```

## 技术栈

- **语言**: MoonBit
- **异步运行时**: moonbitlang/async
- **HTTP 客户端**: moonbitlang/async/http
- **环境变量**: moonbitlang/x/sys
- **JSON 处理**: 内置 derive(ToJson, FromJson)

## 错误处理

Jarvis 定义了以下错误类型:

- `EnvVarNotSet`: 环境变量未设置
- `HttpError`: HTTP 请求失败
- `InvalidResponse`: API 响应格式无效
- `JsonParseError`: JSON 解析错误
- `StringViewError`: 字符串视图错误

所有错误都会被捕获并以友好的方式显示给用户。

## 未来计划

查看 [DESIGN.md](DESIGN.md) 了解完整的设计规划和路线图。

主要计划:
- [ ] 语音输入/输出
- [ ] 系统操作集成
- [ ] 插件系统
- [ ] 工作流自动化
- [ ] 多模态支持

## 许可证

Apache-2.0 License

## 贡献

欢迎提交 Issue 和 Pull Request!
