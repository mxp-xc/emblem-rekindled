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
| 跨关公共 Android QA、fixture/case 接入 | `tools/chapter_android_qa.py --help`，保护契约见 `docs/agents/verification.md` |
| Web 真实输入与完整存储保护 | `tools/chapter_web_harness.js`、`chapter_storage_api.js`、`chapter_storage_codec.js`；证据服务 `tools/chapter_qa_bridge.py --help` |

路径以实际目录为准；找不到时先列出目标目录，避免猜测文件名。
素材路径从 `chapter.json` 的对应 manifest 追踪；生成 JSON/图片不是默认搜索范围。
扩关、改图或修改资源清理前，阅读 `docs/development.md` 的“章内共享图片与改图”；
公共图片归章级shared所有，关卡只拥有私有输出，共享逻辑从 `tools/chapter_assets.py` 进入。
扩展关卡配置、队伍部署或章级表现库时，阅读 `docs/design/chapter-content.md`；
其中区分选定设计与已落地行为，实施状态以关联issue为准。

新增跨关平台 case 或维护公共驱动时，从上述 `tools/` 入口复用能力；
关卡差异由显式选择的 case 模块及 `fixtures.json` / `manifest.json` 提供。
Android case 模块导出 `CASES`（名称到接收 flow 的函数），可选导出继承公共 `Flow` 的同名类；
CLI 只加载测试人员指定的可信模块。批次使用新的输出目录，证据、视频与截图继续存 `temp/`。
Web 存储 API 的 `preserveStorage` 要求 `stop` 回调在备份前和恢复前停止游戏写入，
同时保留当前 origin 的存储 API 可用；`persistBackup` 必须将完整快照写入新的
`backup.json` 并从证据服务读回其内容，验证一致后才进入 `run`，退出时恢复并核对原记录。
这三个 Web 模块可以按相对路径导入。harness 的浏览器操作契约见
`docs/agents/verification.md`；具体客户端的接口映射由执行环境提供。
公共入口不依赖 `temp/code/` 的历史脚本，旧批次作为证据保留。

```sh
rg --files game/app game/gameplay game/features game/persistence -g '*.gd'
rg -n 'symbol' game/app game/features -g '*.gd'
uv run python tools/source_context.py "build/web/<buildId>/index.js" needle --radius 160 --limit 5
```

搜索大型生成文件或 minified JS 时使用最后一个命令按字符偏移输出有限片段，
而不是输出整行。需要完整分析产物时保存到临时文件，向会话只返回结论与定位。
Web资源位于`build/web/<buildId>/`；运行最后一条命令前，用`build/web/build-info.json`中的buildId替换路径占位符。
