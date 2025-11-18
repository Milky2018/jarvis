# Jarvis TODO

（请使用 `moon run src -- -e <prompt>` 来测试功能）

- [x] `current_dir` 是一个完全错误的设计，根本没有作用
  - 已修复：删除了 current_working_dir 字段，简化了命令执行逻辑
  - 现在每个命令在新的 shell 子进程中执行，不再维护虚假的状态
- [x] 优化系统提示词，添加工具说明和性格指导
  - 已完成：详细列出 8 个工具的使用说明
  - 添加行为准则：disciplined, skeptical, correctness-driven
  - 提供最佳实践指导

