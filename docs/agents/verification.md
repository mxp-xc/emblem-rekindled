# 验证与界面复核

## 迭代

只运行本任务相关的定向测试与文件检查，subagent 同样遵循；用户未明确要求时不运行全量测试或整库检查。
游戏行为测试如 `uv run er check game --test test_map_input.gd`；工具测试按文件选择，
如 `uv run python -m unittest discover -s tests/tools -p test_cli.py`。
后续只有新增修改或失败才补跑相关检查。批量解析共享一个引擎，行为测试仍逐个隔离。
完整行为测试默认按逻辑核心数加二、最多十二个独立工程和用户目录并行，定向测试默认串行；可用 `--jobs 1` 强制串行，
或对多个定向测试显式设置 `--jobs`。并行检查拒绝工程内的符号链接，避免写到副本之外。
检查器显示阶段进度；运行故障清理测试先等待引擎就绪，再计运行超时。

游戏检查器和工具测试中的真实引擎调用默认使用一次性的 `user://` 身份，
不读取、备份或覆盖正常用户记录。检查临时修改当前工程的 `config/name`，
关闭可能配置的自定义用户目录，并在 `finally` 中逐字节恢复 `project.godot`；
同一工程的检查器通过文件锁拒绝并发。锁不能阻止直接启动的编辑器、游戏或导出工具，
运行前先协调这些入口停用当前工程配置；检查期间不要修改 `project.godot`。
工具故障 fixture 使用系统临时工程，不占用主工程配置。

定向游戏测试需要计时时添加 `--timings <path>`。只有用户明确要求完整检查时，才使用
`uv run er check full --output temp/<batch>/check`，批次目录必须尚不存在。
耗时直接围绕既有阶段及引擎调用测量，不额外执行测试；
失败也保留已完成阶段和当前未完成项。
原件、隔离配置与持有者信息先保存到 `game/.godot/check-recovery/`，再修改工程配置。
`finally` 适用于正常失败和 Python 中断；强制终止宿主进程（如 `SIGKILL`）后，
残留恢复材料会阻止后续检查，使用 `uv run er check restore-config` 恢复。

恢复入口取得同一把锁，确认记录的持有者已退出，且当前配置仍等于保留的隔离配置或原件，
才恢复并逐字节核对。检查期间若有人另改配置，自动恢复会拒绝覆盖并保留全部材料；
此时需先人工合并后来的修改与 `original.godot`，不能直接丢弃后来的修改。

Godot从JSON读取的数字数组，按元素显式`int`后核对值和源顺序；不要直接与int字面量数组整体比较，
否则float/int Variant差异可能造成错误失败。浏览器地图需要双击时，使用一次原生
双击操作（一次调用携带 `clickCount: 2`），调用后再读取状态；地图双击窗口为350ms，
不要在两次单击之间插入可访问性或业务状态轮询后，仍将其当作可靠双击。

commit/push 不自动运行测试；`uv run er workspace hooks` 只配置仓库 hook 路径。
已有自定义 hooks 或配置时保留并人工整合。

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

1. 用 `uv run er build web` 或 `uv run er build android` 导出带 buildId 的实际资源包。
2. Web 用 `uv run er serve` 保持用户原地址，再用 `uv run er verify web` 核对服务器实际 PCK。
   浏览器真实加载后读取 canvas 的 `data-emblem-build-id`，应等于 `build/web/build-info.json`；
   HTTP 验证只能证明服务器返回的 PCK，不能代替浏览器实际加载验证。
3. Android 每批安装当前 APK，再用 `uv run er verify android` 核对已安装包身份；
   内部只读响应的 `build` 字段还可核对当前进程。图标存在不能证明安装版本。
4. 记录命令、结果、证据路径与未测项；本轮平台范围以当前实施票及其关联的验收页为准。

Android 破坏性测试先 force-stop，再以完整快照保护全部 JSON。
`uv run er qa first-battle` 已接入保护；真实节奏另用1倍验证。
备份失败不继续，恢复失败不输出成功。保留的 backup.json 可用
`uv run er qa restore-records <backup.json>` 重试；恢复前停止应用，逐字节核对后写恢复凭证。
读取内部状态使用 `uv run er qa state read --ready`，不为规划下一步保存游戏。

章内差异场景复用 `uv run er qa android` 批次入口和 `uv run er qa web-bridge` 证据服务。
关卡提供 fixture 与差异 case，历史 `temp/` 场景和证据不会自动迁移。
Web 的 `preserveStorage` 只有在 persistBackup 将备份落盘、读回并确认 verified 后才能继续测试写入；
真实输入、buildId 核对和完整恢复仍按本节执行。

### Web 浏览器操作契约

`createChapterWebHarness` 接收固定 `buildId`、证据服务的 `artifactOrigin` 和 `browser` 操作对象。
执行环境将已有浏览器客户端映射到以下异步接口；输入接口使用真实浏览器输入，
页面求值仅用于只读探针、存储读取和证据服务通信：

| 接口 | 完成条件 |
| --- | --- |
| `evaluate(expression)` | 在当前页面等待表达式（含 Promise）完成，返回可序列化的值；页面异常向外抛出 |
| `key(value)` | 发送按键；接受 `Escape`、`Return`、`Left`、`Right` |
| `click([x, y], options?)` | 在 CSS 坐标点击；`clickCount: 2` 使用一次原生双击调用完成 |
| `drag(start, end)` | 在 CSS 坐标间完成鼠标拖动 |
| `settle()` | 输入提交后等待客户端完成处理，再允许读取结果 |
| `reload()` | 重新加载当前页面 |
| `ready({timeout})` | 等待游戏启动加载完成，超时（毫秒）或启动失败时抛出；之后才能发起游戏状态探针 |
| `screenshot()` | 返回当前页面的 PNG base64 字符串 |

每个固定运行包新建 harness。适配器负责将客户端返回值和异常转换为上述契约；
fixture 只验证公共调用顺序，具体客户端仍需验证真实输入、加载就绪和截图行为。
