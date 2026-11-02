## Agent skills

### 本地记忆

若项目根目录存在 `AGENTS.local.md`，读取 @AGENTS.local.md；不存在时继续。
通用实施规则记在本文件或其条件文档中；当前电脑的工具路径、设备与可用能力记在
`AGENTS.local.md`，该文件不进入版本控制。

### 开发与交付

- 定位源码或生成资源前，阅读 `docs/agents/navigation.md`。
- 使用 er、初始化 checkout、运行检查、导入资源或交付前，阅读 [er 使用手册](tools/emblem_dev/README.md)。
- 修改界面、交互或进行平台验收前，阅读 `docs/agents/verification.md`。
- 只运行本任务相关的定向测试与检查；用户未明确要求时，不运行全量测试或整库检查。
  此规则同样适用于 subagent；commit/push 不自动运行测试。
- 对用户记录进行测试写入前，使用已验证的完整备份；备份枚举/读取失败时停止。
  恢复先验证全部原文件，再清理新增文件；失败保留可恢复备份。
- 交付导出并核对实际运行包的 buildId；Web 覆盖用户原地址，
  Android 核对已安装包。检查通过与用户集中验收分开记录。

### Issue tracker

任务和规格使用 GitHub Issues；编写 PRD、规格或读写 issue 前，阅读 `docs/agents/issue-tracker.md`。

### Wayfinder 进展与续接

长期入口是 [三章连续主线重制：逐关推进的决策地图](https://github.com/mxp-xc/emblem-rekindled/issues/1)。
该 issue 只维护整体进展与索引，README 提供入口。第1、2、3章分别使用章级子 issue，
承载本章地图清单、完成计数与 TODO；具体关卡的规格、决定和实施结果放在该章下的子 issue。

继续 wayfinder、收到“阶段开发完成”或查询整体进展时：

1. 先读取整体地图与当前章进度票，再读取相关子 issue 的状态、依赖和负责人，按需读取评论。
2. 核对相关代码、工作区改动、PR 和验证证据，从已有记录恢复上下文；
   仅对记录与代码无法回答的缺口询问用户，区分实现完成与验证通过。
3. 阶段实施开始前，关联包含目标和验收的实施 issue；完成后在该票记录
   文件/PR、验证结果和剩余问题，更新章进度票的地图行、计数和下一入口，再同步整体地图的章级摘要。
4. 每轮结束或阶段交接时更新地图。后续阶段先保留粗粒度目标，
   问题或实施范围明确后再建子 issue 并关联依赖。
5. 当前决策清空后继续关联阶段实施和新问题；整体目标完成后才关闭地图。

地图允许跟踪阶段实施，实施票与 wayfinder 决策票区分；按当前阶段和用户授权推进。

### Triage labels

使用五个默认 triage 标签；分类或修改标签前，阅读 `docs/agents/triage-labels.md`。

### Domain docs

采用 single-context 布局；探索代码、使用领域术语或提出架构变更前，阅读 `docs/agents/domain.md`。
