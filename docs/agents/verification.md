# 验证与界面复核

## 迭代

日常运行 `bun run check:quick`、`bun run check:parse` 和相关的定向行为测试；
`check_godot.py --test` 可以重复指定文件。每个阶段完成后运行一次 `bun run check`，
后续只有新增修改或失败才补跑相关检查。批量解析共享一个引擎，行为测试仍逐个隔离。
检查器显示阶段进度；运行故障清理测试先等待引擎就绪，再计运行超时。

`bun run setup:hooks` 为当前 checkout 安装 pre-commit 快速检查及 pre-push 完整检查；
已有自定义 hooks 或配置时保留并报出需要手动整合的位置，不写全局 Git 配置。

## 界面证据

每个新功能先运行原版的对应完整流程，记录入口、信息层级、确认与返回。
原版已有证据可复用，但要指明具体状态和来源。按 `docs/development.md` 的当前交互契约
实现；原版差异与主动改进说明理由，不能仅凭静态截图声称流程通过。

变更复核至少包含以下对应关系，证据保存到实施票关联的 `temp/` 批次：

| 状态 | 原版/既有依据 | 当前截图 | 真实输入及结果 |
| --- | --- | --- | --- |
| 入口与选中 | 指明来源状态 | 正常与窄屏 | 点击/悬停/滚轮选中是否一致 |
| 子页与确认 | 完整操作顺序 | 确认前后 | 确认只提交一次，取消不提交 |
| 返回 | 上一级应保留内容 | 逐层结果 | Esc、Android Back、菜单外点击 |
| 布局 | 地图/人物/说明层级 | 宽屏与手机 | 缩放后不越界、不遮挡目标格 |

边界、选中同步、状态恢复及重复输入用自动测试保护；统一风格、字号比例和可读性
由截图复核，不能以坐标断言替代审美判断。真实系统 Back 与音频连续性需要运行验证。
自动化从游戏设置临时调速；每次重启后重新设置。批量执行已知输入，在预期业务状态处检查结果；截图用于布局、关键结果和失败复核。
修改性能或自动化驱动时，以同一场景记录优化前后的总耗时，分别保留启动、输入/演出、保存、重启及恢复记录的耗时。

## 平台交付

1. `bun run build:web` / `bun run build:android` 导出带 buildId 的实际资源包。
2. Web 使用 `bun run serve` 的原地址，再运行 `bun run verify:web`。
   浏览器真实加载后读取 canvas 的 `data-emblem-build-id`，应等于 `build/web/build-info.json`；
   HTTP 验证只能证明服务器返回的 PCK，不能代替浏览器实际加载验证。
3. Android 每批安装当前 APK，运行 `bun run verify:android` 核对已安装包；
   内部只读响应的 `build` 字段还可核对当前进程。图标存在不能证明安装版本。
4. 记录命令、结果、证据路径与未测项；本轮平台范围见 `docs/acceptance/first-battle.md`。

Android 破坏性测试先 force-stop，再使用 `tools/qa_records.py` 的完整快照保护全部 JSON。
`tools/playtest_first_battle.py` 已接入保护，默认32倍并按回合保存；真实节奏另用1倍验证。
备份失败不继续，恢复失败不输出成功。保留的 `backup.json` 可恢复：

```sh
rtk uv run python tools/qa_records.py temp/playtest/<batch>/records/backup.json --serial <serial>
```

恢复命令先停止应用，逐字节核对恢复结果后写 `restored.json`；故障时保留备份供重试。
读取内部状态走 `tools/android_playtest.py read --ready`，不为规划下一步保存游戏。
