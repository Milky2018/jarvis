# Jarvis TODO

要将代码分离成 subpackage，建议按以下顺序：

1. 创建 shared types package (无依赖):
  - ContentBlockItem, Message, ToolCall, FunctionCall, Tool, UsageStats
  - ResponseUsage, ChatResponse, ContentBlock
  - ModelInfo, 常量, 颜色定义, Config
  - JarvisError, JarvisSignal (所有 suberror)
2. proxy package (依赖: shared types)
3. diff package (依赖: shared types 的颜色常量)
4. api package (依赖: shared types, proxy)
5. storage package (依赖: shared types)
6. chat package (依赖: shared types, api, storage)
7. tools package (依赖: shared types, api, proxy, diff, storage, chat)
8. commands package (依赖: shared types, chat, tools, storage)
9. main (依赖: 所有 package)

