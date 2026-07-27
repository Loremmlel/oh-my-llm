# History Ownership

History 是 Chat feature 的 read model。它允许依赖 Chat 的查询、分页和会话选择
application/domain API，以展示历史对话；它不是独立的 domain 或 data feature。

搜索只匹配对话标题与用户消息，标题生成和分页规则均由 Chat 保持所有权。
