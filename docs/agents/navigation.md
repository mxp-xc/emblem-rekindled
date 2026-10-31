# 源码导航

先在人工源码中定位，再按 manifest 进入对应生成资源。

| 目的 | 入口 |
| --- | --- |
| 输入分派、跨界面流程 | `game/app/main.gd` |
| 战场状态与规则 | `game/gameplay/battle_state.gd`、同目录规则文件 |
| 地图、镜头、范围、HUD | `game/features/tactical_map/` |
| 人物行动、属性、物品界面 | `game/features/tactical_map/unit_information.gd`、`unit_menu.gd`、`item_actions.gd` |
| 标题、设置、存读档入口 | `game/features/menus/` |
| 开场、世界与对白 | `game/features/dialogue/story_player.gd` |
| 独立战斗与反馈 | `game/features/battle/` |
| 持久化 | `game/persistence/` |
| 内容入口 | `game/content/chapter_1/chapter.json` |
| 生成器与平台验证 | `tools/`，命令见 `package.json` |

路径以实际目录为准；找不到时先列出目标目录，避免猜测文件名。
素材路径从 `chapter.json` 的对应 manifest 追踪；生成 JSON/图片不是默认搜索范围。

```sh
rtk rg --files game/app game/gameplay game/features game/persistence -g '*.gd'
rtk rg -n 'symbol' game/app game/features -g '*.gd'
rtk uv run python tools/source_context.py build/web/index.js needle --radius 160 --limit 5
```

搜索大型生成文件或 minified JS 时使用最后一个命令按字符偏移输出有限片段，
而不是输出整行。需要完整分析产物时保存到临时文件，向会话只返回结论与定位。
