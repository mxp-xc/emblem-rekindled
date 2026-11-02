# 纹章传说：重燃

使用 Godot 重制原版战棋游戏，将初章、第二章和终章逐步整合为连续主线。
保留像素风格，面向手机 App，首期以 Android 验收；电脑 Web 用于开发调试。
竖屏是默认及推荐方向，横屏作为可选能力提供。

游戏使用单屏战场，手机滑动、电脑鼠标拖动移动视野；功能按钮贴边放置，
状态与操作按点选显示，低频设置收在游戏内菜单中。

## 整体进展与 TODO

[查看三章连续主线重制：逐关推进的决策地图](https://github.com/mxp-xc/emblem-rekindled/issues/1#overall-todo)。

总体 issue 维护章级进展、全局决定和索引；各章地图清单、完成计数、TODO 与下一入口由章级子 issue 承载：

- [第1章：初章地图与关卡进度](https://github.com/mxp-xc/emblem-rekindled/issues/32)
- [第2章：第二章地图与关卡进度](https://github.com/mxp-xc/emblem-rekindled/issues/33)
- [第3章：终章地图与关卡进度](https://github.com/mxp-xc/emblem-rekindled/issues/34)

具体关卡的规格、裁决和实施证据保存在对应章下的子 issue。

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
福尔斯路线第二战与世界往返见[索菲亚山脉第二战验收](docs/acceptance/second-battle.md)。
后续初章关卡的开发自测证据见[逐关验收](docs/acceptance/chapter-content.md)。

```sh
bun install --frozen-lockfile
uv sync --locked
bun run format
bun run check
godot --path game --editor
```
