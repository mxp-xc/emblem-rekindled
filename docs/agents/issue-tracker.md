# Issue tracker: GitHub

本仓库的任务和规格使用 GitHub Issues，通过 `gh` CLI 操作。
在仓库目录内运行命令，由 Git remote 确定目标仓库。

## 常用操作

- 创建：`gh issue create --title "..." --body-file <path>`
- 读取：`gh issue view <number> --comments`
- 列表：`gh issue list --state open --json number,title,body,labels`
- 评论：`gh issue comment <number> --body-file <path>`
- 添加标签：`gh issue edit <number> --add-label "..."`
- 移除标签：`gh issue edit <number> --remove-label "..."`
- 关闭：`gh issue close <number>`

多行正文先写入临时文件，再通过 `--body-file` 传入。
按任务需要读取标签、评论，并使用状态和标签过滤列表。

skill 要求“发布到 issue tracker”时，创建 GitHub issue；
要求“获取相关 ticket”时，读取对应 issue 及评论。

## Issue 的仓库上下文

创建或更新任何类型的 Issue 时，可按需增加 `## Repository Context`，
集中引用与任务相关的仓库依据。引用前核对内容，按任务需要选择：

- 相关 Issue、PR、`GLOSSARY.md`、规格和 ADR，以及所依据的结论；
- 现有实现的文件路径、symbol、接口、数据和状态边界；
- 缺陷相关的 fixture、case、trace、来源身份、复现步骤和失败信号；
- 主要实现位置、相关测试和验收入口，以及明确不涉及的范围。

引用应指向具体依据，并说明它与当前任务的关系；区分已验证事实、
用户裁决和待验证假设。文件路径使用仓库相对路径，Issue、PR 和
外部资料使用编号或链接。

正文描述任务目标、行为和验收要求；仓库引用集中在 `Repository Context`，
非契约 helper、伪代码和库调用留给实现。

## Pull requests as a triage surface

**PRs as a request surface: no.**

GitHub 的 issue 和 PR 共用编号空间。裸编号类型不明确时，
先尝试 `gh pr view <number>`，再尝试读取 issue。

## Wayfinding

- Map：使用一个带 `wayfinder:map` 标签的 issue，
  正文包含 Notes、Decisions-so-far 和 Fog。
- Child ticket：优先通过 GitHub sub-issue 关联到 map。
  不支持时，在 map 正文使用任务列表，child 正文顶部写 `Part of #<map>`。
- Ticket 类型标签：`wayfinder:research`、`wayfinder:prototype`、
  `wayfinder:grilling`、`wayfinder:task`。
- 阻塞关系：优先使用 GitHub 原生 issue dependencies。
  API 使用 issue 的数字数据库 id；不支持时，在 child 正文顶部写
  `Blocked by: #<number>, #<number>`。所有 blocker 关闭后才能推进。
- Frontier：按 map 顺序选择首个未关闭、无未关闭 blocker、
  且未分配负责人的 child。
- Claim：通过 `gh issue edit <number> --add-assignee @me` 认领。
- Resolve：评论记录结果，关闭 child，并在 map 的 Decisions-so-far
  中追加结论摘要和链接。
