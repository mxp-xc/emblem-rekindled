# 纹章传说：重燃

使用 Godot 重制原版战棋游戏，将初章、第二章和终章逐步整合为连续主线。
保留像素风格，面向手机 App，首期以 Android 验收；电脑 Web 用于开发调试。

游戏使用单屏战场，手机滑动、电脑鼠标拖动移动视野；功能按钮贴边放置，
状态与操作按点选显示，低频设置收在游戏内菜单中。

## 整体进展与 TODO

[查看三章连续主线重制：逐关推进的决策地图](https://github.com/mxp-xc/emblem-rekindled/issues/1#overall-todo)。

整体清单直接放在该 issue 正文，包含已完成决策、当前待办、首关开发与验收、
后续章节和自定义玩法；当前阶段与下一入口也在同一 issue 中。
具体规格、裁决和实施证据保存在对应子 issue。

## 设计与调研

- [工程与文件系统组织设计](docs/design/project-organization.md)
- [Godot 最小工程实施计划](docs/design/first-godot-milestone.md)
- [Godot AI 开发工具适配调研](docs/research/godot-ai-tools.md)

## 项目约定

- [Agent 工作与续接约定](AGENTS.md)
- [领域术语](GLOSSARY.md)

## 开发与验证

入口位于 `game/project.godot`，命令和资源准备见[开发说明](docs/development.md)。
首关的验收条件、逐项证据和平台范围见[首关验收](docs/acceptance/first-battle.md)。

```sh
bun install --frozen-lockfile
uv sync --locked
bun run format
bun run check
godot --path game --editor
```
