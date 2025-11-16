# Jarvis TODO

（请使用 `moon run src -- -e <prompt>` 来测试功能）

- [x] 现在的 Read 工具似乎是一次性读整个文件，这显然是不合适的
  - 已实现：Read工具正确支持offset和limit参数进行分页读取
- [x] 现在连一个简单的 `cd <path>` 都做不好，你可以试试 `cd $PROJ/toykv`
  - 已修复：添加了单引号转义、支持裸cd命令、改进了错误报告
- [x] 现在简单的 web search 也做不好，可以试试
  - 已修复：修复了URL编码bug，增强了HTML解析的鲁棒性
- [x] 多轮工具调用仍然有问题，执行到一半就把控制权交还给用户了。建议加上一个对结尾冒号的检测（包括中文冒号和英文冒号）
  - 已实现：检测响应末尾的冒号（:和：），自动提示继续执行工具调用
- [x] 实现一套完整的测试框架。这是一个大工程，可能包括 LLM Mock、log mock（输出等）、memory mock（conv_001.json这种文件）
  - 已实现：包含MockLLMClient、MockFileSystem、MockOutputCapture的完整测试框架，共13个测试全部通过
