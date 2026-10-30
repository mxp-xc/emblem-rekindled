## Agent skills

### Issue tracker

任务和规格使用 GitHub Issues；编写 PRD、规格或读写 issue 前，阅读 `docs/agents/issue-tracker.md`。

### Wayfinder 进展与续接

长期入口是 [三章连续主线重制：逐关推进的决策地图](https://github.com/mxp-xc/emblem-rekindled/issues/1)。
整体进展和 TODO 直接维护在该 issue 正文，README 提供入口；详细决定和实施结果放在对应子 issue。

继续 wayfinder、收到“阶段开发完成”或查询整体进展时：

1. 先读取地图正文、子 issue 状态、依赖和负责人，再按需读取相关评论。
2. 核对相关代码、工作区改动、PR 和验证证据，从已有记录恢复上下文；
   仅对记录与代码无法回答的缺口询问用户，区分实现完成与验证通过。
3. 阶段实施开始前，关联包含目标和验收的实施 issue；完成后在该票记录
   文件/PR、验证结果和剩余问题，再更新地图的当前阶段、TODO 和下一入口。
4. 每轮结束或阶段交接时更新地图。后续阶段先保留粗粒度目标，
   问题或实施范围明确后再建子 issue 并关联依赖。
5. 当前决策清空后继续关联阶段实施和新问题；整体目标完成后才关闭地图。

地图允许跟踪阶段实施，实施票与 wayfinder 决策票区分；按当前阶段和用户授权推进。

### Triage labels

使用五个默认 triage 标签；分类或修改标签前，阅读 `docs/agents/triage-labels.md`。

### Domain docs

采用 single-context 布局；探索代码、使用领域术语或提出架构变更前，阅读 `docs/agents/domain.md`。
