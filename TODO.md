# TODO: Conversation Continuity Feature (WIP)

## 功能目标

实现连续的对话历史同步系统，让对话可以跨会话持续，并在 summarize 后自动创建新文件。

## 设计方案

### 文件命名
```
~/.jarvis/
├── conv_001.json  # 第一个对话文件
├── conv_002.json  # summarize 后创建的新文件
├── conv_003.json  # 当前活跃的对话文件
```

### 工作流程
1. **启动时**: 自动加载最新的 `conv_XXX.json` 文件
2. **每次交互后**: 保存到当前文件
3. **Summarize 触发**: 创建新的 `conv_XXX+1.json` 文件，后续保存到新文件

## 已完成部分 ✅

### 1. 数据结构 (chat.mbt)
- [x] 添加 `current_file_number: Int` 字段到 `ChatHistory`
- [x] 在 `ChatHistory::new()` 中初始化为 0
- [x] 在 `ChatHistory::load()` 中初始化为 0

### 2. 文件管理函数 (storage.mbt)
- [x] `get_latest_conversation_number()` - 获取最新文件编号
- [x] `get_conversation_file_path(number)` - 根据编号生成文件路径
- [x] `create_new_conversation_file(messages)` - 创建新文件
- [x] `load_latest_conversation()` - 加载最新对话，返回 `(ChatHistory, Int)?`

### 3. 保存和创建函数 (chat.mbt)
- [x] `ChatHistory::save_to_numbered_file()` - 保存到编号文件
- [x] `ChatHistory::create_new_file_after_summary()` - summarize 后创建新文件

## 待完成部分 ⏳

### 1. 修改 chat_loop() - main.mbt

**位置**: `src/main.mbt` 的 `chat_loop()` 函数

**需要做的**:
```moonbit
async fn chat_loop(config : Config) -> Unit {
  // 尝试加载最新对话
  let mut chat_history = match load_latest_conversation() {
    Some((history, file_num)) => {
      history.current_file_number = file_num
      print_jarvis_prefix()
      println("Loaded conversation from conv_\{format_number(file_num)}.json")
      history
    }
    None => {
      // 创建新对话
      let initial_msg = Message::new("system", "You are Jarvis, ...")
      let history = ChatHistory::new()
      history.add(initial_msg)

      // 创建第一个文件
      let file_num = create_new_conversation_file([initial_msg])
      history.current_file_number = file_num

      print_jarvis_prefix()
      println("Hello! I'm Jarvis, your AI assistant...")
      history
    }
  }

  // ... 剩余代码保持不变
}
```

### 2. 修改 handle_user_input() - main.mbt

**位置**: `src/main.mbt` 的 `handle_user_input()` 函数

**需要在函数末尾添加**:
```moonbit
async fn handle_user_input(...) -> Unit {
  // ... 现有代码 ...

  // Manage history before sending request
  try {
    let summarized = chat_history.manage_history(config)
    if summarized {
      print_jarvis_prefix()
      println("(Summarized old conversation history to manage context length)")

      // *** 新增: 创建新文件 ***
      chat_history.create_new_file_after_summary()
      print_jarvis_prefix()
      println("(Created new conversation file: conv_\{format_number(chat_history.current_file_number)}.json)")
    }
  } catch { ... }

  // Execute tools and handle responses
  let tools = get_available_tools()
  handle_tool_calls(config, chat_history, tools)

  // *** 新增: 保存对话 ***
  chat_history.save_to_numbered_file()
}
```

### 3. 添加辅助函数 - storage.mbt

**需要添加**:
```moonbit
/// Format number as 3-digit string (for display)
fn format_number(n : Int) -> String {
  if n < 10 {
    "00\{n}"
  } else if n < 100 {
    "0\{n}"
  } else {
    n.to_string()
  }
}
```

### 4. 测试清单

- [ ] 首次启动创建 `conv_001.json`
- [ ] 对话自动保存到 `conv_001.json`
- [ ] 重新启动自动加载 `conv_001.json` 并继续对话
- [ ] 触发 summarize 后创建 `conv_002.json`
- [ ] 后续对话保存到 `conv_002.json`
- [ ] 再次重启加载 `conv_002.json`

## 实现注意事项

### 1. current_file_number 的设置
由于 `ChatHistory` 的字段有 `mut`，需要在创建或加载后立即设置：
```moonbit
let chat_history = ChatHistory::new()
chat_history.current_file_number = 1  // ✓ 可以修改
```

### 2. 编号格式化
使用 `get_conversation_file_path()` 已经处理了 3 位数字格式化：
- `conv_001.json`
- `conv_002.json`
- ...
- `conv_999.json`

### 3. 错误处理
如果文件操作失败，不应该崩溃，而是打印警告并继续：
```moonbit
if exit_code != 0 {
  print_jarvis_prefix()
  println("Warning: Failed to save conversation")
}
```

## 未来改进

- [ ] 添加 `:history` 命令查看所有对话文件
- [ ] 添加 `:load <number>` 命令加载特定对话
- [ ] 自动清理过旧的对话文件（保留最近 N 个）
- [ ] 压缩旧对话文件以节省空间

---

**状态**: Work In Progress (WIP)
**创建时间**: 2025-11-13
**预计完成时间**: 需要 15-20 分钟额外开发时间
