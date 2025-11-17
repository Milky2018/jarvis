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
- [x] 测试 utils 文件命名为 mock.mbt，然后将所有的测试块移动到相应的函数实现附近
  - 已完成：将test_utils.mbt重命名为mock.mbt，测试已放在相应函数附近
- [x] 更加全面的测试，尽量提升覆盖率
  - 已完成：为diff.mbt添加了7个测试，为proxy.mbt添加了6个测试，总计25个测试全部通过
- [x] 实现 Search 工具，用于在本地文件中查找
  - 已完成：通过grep和glob工具实现，grep支持文本模式搜索，glob支持文件名模式匹配
- [x] record_messages 函数没有被用到，显然这个函数是用来测试某一类功能的，请实现这些测试
  - 已完成：添加了3个测试来验证record_messages功能，测试消息记录、请求追踪和消息历史，总计28个测试全部通过
- [x] list_files 和其他mock辅助函数也需要测试覆盖
  - 已完成：添加了3个测试（mock_file_system_list_files、mock_tool_helpers、mock_tool_response_with_tools），总计31个测试全部通过
- [x] chat_history 需要测试工具调用后的状态变化
  - 已完成：添加了5个真正的集成测试，使用真实工具执行来验证chat_history行为：
    * execute_command_updates_chat_history - 测试命令执行
    * execute_cd_updates_working_dir - 测试工作目录更新
    * execute_pwd_shows_current_dir - 测试pwd命令
    * grep_tool_with_test_file - 测试grep工具的真实搜索
    * glob_tool_finds_txt_files - 测试glob工具的文件查找
  - 总计36个测试全部通过，都是真正的集成测试，只有LLM部分使用mock
