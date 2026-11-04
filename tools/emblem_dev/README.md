# er 使用手册

`er` 是本项目 checkout 内的开发 CLI。本文集中维护安装、命令参数、输出与操作约束；
日常使用不需要阅读 Python 实现。以下命令从项目根目录运行，相对路径按当前工作目录解析。
`/path/to/...`、`<batch>`、`<buildId>`、`<serial>` 和示例 case 名均是占位符，执行前替换为已核实的值。
命令不会自动发现或运行 `temp/` 历史脚本。

## 安装与 checkout 初始化

需要已有 Python、uv、bun、Git；检查和导出另需 Godot 4.7.2（quick/tools 也有真实引擎故障 fixture），Android 操作另需已有 SDK、Java 和设备。
机器路径与可用能力先查看根目录可选的 `AGENTS.local.md`。初始化不会安装 Godot、SDK 或浏览器，也不创建 Git 分支或 worktree。

普通 checkout 首次安装及查看入口：

```sh
uv run er setup
uv run er workspace status
uv run er --help
```

每份 checkout / worktree 使用自己的真实 `.venv` 目录，默认也独立安装 `node_modules`。
setup 执行 `uv sync --locked` 与 `bun install --frozen-lockfile`；已有真实目录可继续同步。
`.venv` 链接或非目录会被拒绝，工具不会自动删改。
`uv run` 在 CLI 启动前可能同步 Python 环境，CLI 无法拦截这一步；
目标已有 `.venv` 链接时，从正常来源 checkout 初始化目标，不先进入目标运行 `uv run`：

```sh
uv run er workspace init /path/to/existing-checkout
```

此命令使用来源 checkout 已安装的工具，检查目标配置后为目标同步锁定依赖，不执行目标 Python 文件。
需要人工先处理的非法链接会直接报错，不能靠该命令自动修复。

| 命令（均加 `uv run` 前缀）                | 参数与结果                                                                              |
| ----------------------------------------- | --------------------------------------------------------------------------------------- |
| `er setup`                                | 可选 `--hooks`，默认关闭；安装当前 checkout 依赖                                        |
| `er workspace` / `er workspace status`    | 无参数；只读输出 checkout、工具来源、Python、依赖目录/链接、可执行文件和 CodeGraph 状态 |
| `er workspace init TARGET`                | 必填已有 checkout 路径；可选 `--hooks`，默认关闭                                        |
| `er workspace hooks`                      | 无参数；显式配置仓库 hook 路径；commit/push 不自动运行检查                              |
| `er workspace reuse-js --source SOURCE`   | 必填来源 checkout；显式创建兼容 `node_modules` 链接，输出 `LINK`                        |
| `er workspace copy-local --source SOURCE` | 必填不同的来源 checkout；只复制白名单 `AGENTS.local.md`，输出 `COPY`                    |

reuse-js 要求来源是已安装的真实 `node_modules` 目录，`package.json`、`bun.lock`、`.prettierrc.json`
逐字节一致，目标路径被 Git 忽略且尚不存在。不复用 Python 环境。
setup 遇到已复用的 JS 链接只验证兼容性，不沿链接安装。
copy-local 要求来源为真实文件、目标尚不存在且被 Git 忽略；不扫描其他配置或 secret。
这些入口不创建 CodeGraph 索引。

hooks 默认不配置；仓库 pre-commit/pre-push 是直接退出的空 hook，不自动运行测试或检查。
已有自定义 hooks 或 `core.hooksPath` 时保留并报错，按报出位置人工整合。
启用会改仓库 local Git 配置，影响同仓库 linked worktrees，不写全局 Git 配置。

## 命令导航与参数约定

分组入口为 `workspace`、`check`、`build`、`verify`、`import`、`qa`；
顶层另有 `setup`、`serve`、`source-context`、`extract-texture`。先看分组，再看叶子帮助：

```sh
uv run er qa --help
uv run er qa android --help
```

`uv run er extract-texture 'res://content/chapter_1/generated/shared/…/frame.png' temp/frame.png`
按逻辑路径从初章图集导出单张原图，输出已存在时拒绝覆盖；人工换图的目录和登记方式见
[开发说明](../../docs/development.md#章内共享图片与改图)。

所有层级支持 `--help`；顶层还提供 `--show-completion` 与 `--install-completion`。
后者会安装当前 shell 的补全。本文表格未标必填的选项均可省略；无默认值的可选选项默认为未提供。
布尔选项由 Typer 提供正反开关，如 `--ready` / `--no-ready`；表格列正向开关和默认行为。
参数属于各自叶子命令，放在叶子之后。只有明确标注可重复的选项可以收集多个值。

## 检查与故障恢复

默认只运行本任务相关的定向测试与文件检查，subagent 同样遵循。
用户未明确要求时，不运行全量测试或整库检查；commit/push 不触发测试。

运行 Godot 检查前，停用同工程的编辑器、游戏和导出；检查期间不要修改 `game/project.godot`。
检查用临时 `user://` 身份，不读取或改写正常用户记录；工程配置在结束时逐字节恢复。
文件锁只保护同工程检查器，不能阻止其他直接启动的引擎。
完整隔离和恢复契约见[验证规则](../../docs/agents/verification.md#迭代)。

| 命令                      | 参数、覆盖与输出                                                          |
| ------------------------- | ------------------------------------------------------------------------- |
| `er check quick`          | 无参数；lint 与工具测试各一次                                             |
| `er check full`           | 可选 `--output PATH`；依次 lint、工具测试、游戏检查各一次，首次失败停止   |
| `er check lint`           | 无参数；GDScript、Python、Java/JS/JSON 等维护文件规则与格式检查，不改文件 |
| `er check tools`          | 无参数；工具行为测试                                                      |
| `er check helpers`        | 无参数；Godot 测试 helper 使用边界                                        |
| `er check parse`          | 可选 `--timings PATH`；导入资源、批量解析脚本                             |
| `er check game`           | 可重复 `--test FILE`；可选 `--tests-only`（默认关闭）、`--timings PATH`、`--jobs 1..12` |
| `er check restore-config` | 无参数；恢复中断检查留下的工程配置                                        |

游戏行为测试显式选文件，工具测试按本次改动选择测试文件，例如：

```sh
uv run er check game --test test_map_input.gd
uv run python -m unittest discover -s tests/tools -p test_cli.py
```

静态检查也只指定本任务涉及的文件。上表保留完整命令目录；quick、full、lint、tools、parse、
未指定文件的 game 及 tests-only 会扩大到整库或完整测试集合，只有用户明确要求时才运行。
用户明确要求完整计时检查时，才使用 `uv run er check full --output temp/<batch>/check`。

game 默认执行资源导入、解析、行为测试和主场景 smoke；`--test` 只执行指定行为测试文件。
`--tests-only` 跳过导入和解析，执行全部行为测试及主场景 smoke；不能与 `--test` 同用。
parse 的批量解析共享一个引擎，行为测试逐个隔离；Godot 报错即使返回0也判失败，每次引擎调用有60秒超时。
完整行为测试默认按 CPU 逻辑核心数加二、最多十二个独立工程副本并行，单个引擎仍逐文件运行；首次失败会停止调度并清理已启动的引擎。
定向 `--test` 默认串行，显式指定 `--jobs 2` 等可并行；`--jobs 1` 强制串行。
并行要求游戏工程内没有符号链接，以免副本写入原路径；有链接时使用串行检查。
副本准备也计入总耗时，短测试集合通常串行更快。

`--output` 要求全新的批次目录，保存 `integrated-check.log`、`timings.json`；
执行到 game 阶段才生成 `godot-timings.json`，lint/tools 早失败时没有该文件。
日志转入文件，终端显示阶段。计时围绕本次实际调用，不为计时重复执行检查，失败也保留已完成和未完成项。
单独 game / parse 的 `--timings` 写引擎调用计时 JSON（父目录自动创建）。
lint 的独立格式检查并行执行并按固定顺序输出结果；tools 将原有 unittest 发现范围按文件分配到
最多四个独立 Python 进程。任一项失败仍会报告错误并阻止后续阶段，不减少测试集合。

普通失败和可处理的中断会清理拥有的引擎进程组并恢复配置。
强制终止留下 `game/.godot/check-recovery/` 时，后续检查会拒绝运行：

```sh
uv run er check restore-config
```

恢复先取同一把锁，确认持有者已退出，且当前配置仍为保留的隔离配置或原件。
如果配置已被其他人修改，保留恢复材料，人工合并后来的修改与 `original.godot`，再处理恢复；不要覆盖后来改动。

格式化和静态检查只向现有格式化器传入本任务涉及的文件；整库 format/lint 仅在用户明确要求时运行。

m13及公共章末改动可按需要选择`test_m13_locations.gd`、`test_chapter_statistics.gd`、
`test_chapter_completion_ui.gd`和`test_visit_feedback_ui.gd`等定向文件；实际测试清单和结果由实施票记录。
跨关 Session 基础入口测试在 `test_chapter_session.gd`；两条章末路线与各自的四槽冷读分别在
`test_chapter_session_route0.gd` 和 `test_chapter_session_route7.gd`，需要完整覆盖时三项都运行。
指挥官早期关卡和后期队伍分别由 `test_commander_rules.gd` 和
`test_commander_late_roster.gd` 覆盖。
m14 的两条路线分别使用 `test_m14_session.gd` 和 `test_m14_session_route2.gd`；
m15 使用 `test_m15_session.gd` 和 `test_m15_session_route3.gd`；m16 的两条路线使用
`test_m16_content.gd` 和 `test_m16_content_route5.gd`。
m2 内容和事件、m3 内容和事件、m4 内容、m5 和 m6 内容及事件的多路线矩阵按文件名中的 `routes` 分组；m2 战斗边界在
`test_m2_events_combat_boundaries.gd`。m3 主界面流程的分支分别使用 `test_m3_flow.gd`、
`test_m3_flow_route2.gd` 和 `test_m3_flow_route3.gd`。完整定向回归需包含对应分组文件。
m5 主界面流程分别使用 `test_m5_flow.gd`、`test_m5_flow_route2.gd` 和 `test_m5_flow_route4.gd`。
m7 内容和事件按 `test_m7_content*`、`test_m7_events*` 的路线分组运行；
原版随机边界在基础内容测试，首领战斗边界在 `test_m7_events_route3.gd`。
m8 内容、事件和界面流程分别按 `test_m8_content*`、`test_m8_events*`、`test_m8_flow*` 分组；
内容随机边界在基础内容测试，首领战斗边界在 `test_m8_events_route3.gd`。
m9 内容、事件和界面流程分别按 `test_m9_content*`、`test_m9_events*`、`test_m9_flow*` 分组；
装备随机边界在基础内容测试。
完成世界恢复与四槽记录应走真实Session/Store及JSON冷读；UI fixture通过不等于正式内容整合或平台验收。
用户记录的备份与恢复、引擎配置独占规则继续按[验证规则](../../docs/agents/verification.md)执行。

## 构建、预览与实际版本验证

需已有 Godot 4.7.2 与对应导出模板。模板归档从[官方 4.7.2 发布页](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)
取得；命令检查固定版本与 SHA-256 身份，不自动下载。
Android 另需在 Godot 编辑器 Export → Android 配置已有 Java SDK、Android SDK。

| 命令                     | 参数与输出                                                                                                                                        |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `er build templates TPZ` | 必填已有 `Godot_v4.7.2-stable_export_templates.tpz`；只提取 Android、单线程 Web 与 ICU 到 `build/templates/4.7.2.stable/`                         |
| `er build web`           | 无参数；发布 `build/web/index.html`、`build/web/<buildId>/` 与 `build-info.json`                                                                  |
| `er build android`       | 无参数；发布 `build/android/emblem-rekindled.apk` 与 `build-info.json`                                                                            |
| `er serve`               | 可选 `--port INTEGER`，默认8765；只监听 `127.0.0.1`，前提是已有 Web 导出                                                                          |
| `er verify web`          | 可选 `--origin URL`，默认 `http://127.0.0.1:8765`；核对入口、响应头和实际 PCK                                                                     |
| `er verify android`      | 可选 `--serial SERIAL`、`--apk PATH`；默认从本 checkout 的 `build/android/emblem-rekindled.apk` 取期望身份；指定 apk 时从该包取身份，核对已安装包 |

```sh
uv run er build templates /path/to/Godot_v4.7.2-stable_export_templates.tpz
uv run er build web
uv run er serve
```

serve 是前台服务；在另一终端运行验证。已有同地址服务先核实所属 checkout，可复用正确服务。

```sh
uv run er verify web
uv run er build android
uv run er verify android --serial <serial>
```

Android verify 不负责安装；先用已有 ADB 安装当前 APK（QA 批次会自行安装），再核对已安装包。
导出临时注入 buildId，包内验证通过才发布，结束恢复源身份文件。
构建身份含 buildId、时间、revision 与 dirty；以实际包身份为准，不能只看源码或安装图标。
Android 先准备完整 APK 和 metadata，再替换稳定包；普通发布失败保留旧包。
APK 是发布提交点；进程被强制终止后旁置 `build-info.json` 可能尚不同步，核包始终从 APK 读取身份。
Web 保持用户原地址，重新导出后普通刷新；入口 base 指向独立构建资源 URL，旧构建目录保留给仍运行的页面。
serve 使用 `Cache-Control: no-store`，不发送清理浏览器数据的响应头；普通 `http.server` 不符合该验证契约。
verify web 通过只证明 HTTP 返回的包；浏览器加载后还须核对 canvas 的 `data-emblem-build-id`
等于 `build/web/build-info.json`，再做真实输入验收。检查通过和用户集中验收分别记录，详见[平台交付](../../docs/agents/verification.md#平台交付)。

## 内容导入

内容结构、原包身份、图片所有权与产品表现见[原版资源整理](../../docs/development.md#原版资源整理)。
正式导入输入为 `reference/original-jars/chapter-1.jar`、已核对的 `authored/battles/mN.json`、
已有 FreeJ2ME-Plus JAR 和 Java/Javac。工具验证原 JAR 与模拟器固定身份，不自动下载替换。

### 初章计划与发布

`er import chapter-1` 的选项：

| 选项                        | 含义与默认值                                                             |
| --------------------------- | ------------------------------------------------------------------------ |
| `--plan`                    | 默认关闭；只输出 JSON 需求、缺项及 missingProfiles，不调用原 JAR、不发布 |
| `--chapter PATH`            | 默认本 checkout 的 `game/content/chapter_1`；可指向完整章副本演练        |
| `--battle ID`               | 非 plan 必填；发布范围 m0～m19                                           |
| `--emulator PATH`           | 非 plan 必填；已有 FreeJ2ME-Plus JAR                                     |
| `--route INTEGER`           | 可选，0～7；优先准备路线，其他缺项上下文仍按需补充                       |
| `--jdk PATH`                | 可选 Java/Javac 所在 bin 目录；默认 PATH                                 |
| `--native-input DIRECTORY`  | 可重复；复用已准备的原生输出，逐个核对来源、路线、部署和片段依赖         |
| `--native-output DIRECTORY` | 只导出独立原生采样，不发布游戏内容；与 native-input 互斥                 |
| `--encounter-step N`        | 遭遇战采样时已完成的主线节点数，范围为 6 到所选路线的节点数             |
| `--adaptive`                | 默认关闭；仅用于 native-output，按受控等级采样原版自动选阶表现           |
| `--evidence-output DIRECTORY` | 发布模式中保存自动原生样本；目录须为新目录且不得与章目录重叠           |
| `--refresh-motion`          | 默认关闭；重新采样当前原生上下文，与 native-input 互斥，不覆盖冲突旧片段 |
| `--report PATH`             | 发布模式将完整结果写 JSON，父目录自动创建；终端输出精简 JSON 摘要        |

`m17`、`m18`、`m19` 可通过发布模式更新；使用 `--native-output` 单独采样时须显式选择路线。
`--encounter-step` 指定受控队伍已经完成的节点数；省略时使用该路线倒数第二个节点的结算队伍。
采样使用受控结算，不代表自然遭遇或关卡已发布。
`m19` 支持结合 `--adaptive` 采样高等级敌人；`m17`、`m18` 的该组合仍未开放。
使用 `--plan --battle m17`、`--plan --battle m18` 或 `--plan --battle m19` 可查看按队伍去重的全部路线及进度组合；
`equivalentContexts` 列出每个队伍对应的路线和进度。

```sh
uv run er import chapter-1 --plan
uv run er import chapter-1 --emulator /path/to/freej2me_plus.jar --battle m6 --report temp/<batch>/import.json
```

发布模式默认复用已有动作契约，只采样缺项；先在隔离完整章副本合并并检查所有登记关卡的动作闭包，
通过后发布生成内容与章入口，不覆盖人工配置。相同输入重入保留未变化 JSON 字节、PNG 导入参数及 UID。
准备输入缺依赖时重新准备该上下文，不能将增量输出当完整输入。
共享敌方 recipe 在别关新增原版装备后，旧舞台补采也包含该 recipe 已登记的武器，
以补齐全章动作组合；原关卡部署和装备选择不变。

召唤之杖的六种职业、双方阵营与原生身份池由章库显式登记。发布时自动准备缺失的召唤表现，
并将其纳入所有已登记关卡的动作闭包；报告中的 `summonClassId` 标明该采样上下文选择的职业。
召唤采样仍使用原版构造与渲染，只固定准备条件，不代表自然游玩。原生输入可能引用先前上下文
已提供的片段；复用输入仍须满足完整依赖，缺项时由发布流程重新采样。

### 独立原生采样与部署

```sh
uv run er import chapter-1 --emulator /path/to/freej2me_plus.jar --battle m6 --route 0 --native-output temp/<batch>/native
uv run er import chapter-1 --emulator /path/to/freej2me_plus.jar --battle m6 --route 0 --native-output temp/<batch>/adaptive --adaptive
uv run er import chapter-1 --emulator /path/to/freej2me_plus.jar --battle m6 --native-input temp/<batch>/native --report temp/<batch>/import.json
```

native-output 返回 `nativeOutput` JSON；不发布、不写 report，未指定 route 时使用目标关卡首个招募上下文路线。
`--adaptive` 在原版加载目标关前将两个等级缓存设为内部等级9，采样自动选阶；这是受控素材准备，
不代表自然游玩。它只与 `--native-output` 使用，生成的样本可作为后续发布的 `--native-input`。
`--evidence-output` 在发布模式保存自动准备或重新准备的原生样本，检查必需文件、复制后逐文件核对；
路径必须不存在，且不得位于章目录内或包含章目录。已提供的 native-input 由调用者保管，不重复复制；
复制或核对失败时停止并保留已写出的证据，以便排查。
plan 分支优先返回，其余采样/发布选项不执行，也不检查互斥；不要用 plan 成功代替实际导入参数或资源验证。

`er import deployment SOURCE OUTPUT --battle INTEGER` 从定义文件导出部署；两个位置参数和 battle 均必填。
OUTPUT 写单位列表 JSON（创建父目录），stdout 输出完整部署 JSON。

## Android QA、状态与恢复

先确认 debug APK、已有已启动设备和 ADB；多设备显式指定 serial。
写入用户记录前必须完成并验证全量备份，枚举或读取失败立即停止。
恢复先验证全部原文件，恢复全部原 JSON 后才清理新增文件，逐字节核对；失败保留可恢复备份。
具体保护和证据标准见[平台交付](../../docs/agents/verification.md#平台交付)。

### 通用批次

`er qa android` 必填 `--apk PATH`、`--build BUILD_ID`、`--fixtures DIRECTORY`、
`--cases FILE`、可重复的 `--case NAME`、`--output DIRECTORY`、`--serial SERIAL`。
可选 `--adb COMMAND`（默认 adb）、`--stop-emulator`（默认关闭）。

fixtures 是同时包含 `fixtures.json` 与 `manifest.json` 的目录。
cases 是显式可信 Python 模块，会在进程内执行；模块导出 `CASES` 名称到接收 flow 的函数映射，
可选导出继承公共 `Flow` 的同名类。只运行指定的已知 case，不自动发现。
output 必须是全新目录。以下是参数模板，先准备且核实这些输入：

```sh
uv run er qa android --apk /path/to/captured.apk --build <buildId> --fixtures /path/to/fixtures --cases /path/to/trusted_cases.py --case case_a --case case_b --output temp/<batch>/android --serial <serial>
```

批次核对 APK 与显式 buildId，等待设备启动，force-stop 后全量备份记录及旋转配置，
捕获本批 APK、安装并读回已安装包核对身份，再执行 case。
结束（含失败）恢复记录与旋转设置；证据包括 captured/installed APK、检查点 JSON/PNG、输入、阶段耗时、
`records/` 和 `result.json`，失败尽可能保留状态和日志。case 决定截图与视频覆盖；通过批次不代表视觉已人工复核。
默认保留模拟器，需要结束后关闭时使用 stop-emulator。

### 首关自然回归

`er qa first-battle` 可选 `--speed INTEGER`（默认32）、`--serial SERIAL`、`--apk PATH`
（默认 `build/android/emblem-rekindled.apk`）、`--keep-emulator`（默认关闭）。

```sh
uv run er qa first-battle --speed 32 --serial <serial> --keep-emulator
```

已有安装时，入口先 force-stop 并完整备份，再安装、核对本批捕获的 APK；
首次安装时先安装核包、创建记录目录，再备份空记录集。从新游戏经真实 ADB 输入自然完成首关；
只读状态用于规划，每回合保存一次，不是通用关卡规划器。
输出自动创建于 `temp/playtest/<batch>/`，含回合记录、journal、完成进度、结果与恢复凭证，
失败尽可能保存截图、状态及进程日志。备份失败停止，结束恢复全部原记录。
普通随机战局仍可能失败；默认结束关闭模拟器，连续批次使用 keep-emulator。

### 只读状态与临时速率

| 命令                           | 参数与结果                                                                                                                     |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `er qa state read`             | 可选 `--serial SERIAL`、`--adb COMMAND`（adb）、`--ready`（默认关闭）、`--timeout SECONDS`（30）；stdout 输出 JSON，不保存游戏 |
| `er qa state speed VALUE`      | 必填速率，只允许1、2、4、8、16、32；可选 serial、adb 同上；通过真实游戏设置界面选择，返回 JSON                                 |
| `er qa restore-records BACKUP` | 必填完整 backup.json；可选 `--serial SERIAL`；校验备份后 force-stop 并恢复，核对后写 restored.json                             |

```sh
uv run er qa state read --ready --serial <serial>
uv run er qa state speed 32 --serial <serial>
uv run er qa restore-records temp/<batch>/android/records/backup.json --serial <serial>
```

状态接口用于 debug 应用；完成标题序文后读取，ready 等待玩家行动间隙，演出快照不能当稳定存档。
临时测试一般用32倍；每次重新启动应用或刷新页面都会回到1倍，必须重新经真实设置界面选择32倍。
切关和返回标题保留会话速率，速率不写设置或存档，累计时间按真实前台时间计算。
speed 命令选完仍留设置页，按所在页面逐层返回。正常节奏和动画完整性另用1倍验收。

## Web 证据桥与真实浏览器

`er qa web-bridge --output DIRECTORY` 必填证据目录，可选 `--origin URL`
（默认 `http://127.0.0.1:8765`）、`--port INTEGER`（默认8766）。
只接受带显式端口的 `http://127.0.0.1:PORT` 游戏 origin，只监听本机。

```sh
uv run er qa web-bridge --output temp/<batch>/web --origin http://127.0.0.1:8765 --port 8766
```

这是前台证据服务，不负责游戏启动、浏览器输入或自动备份。用独立新批次目录，
已有 backup.json 拒绝覆盖；其他同名 JSON 证据可覆盖。服务提供 storage codec/API 模块及 JSON GET/POST，
POST 校验 Origin、文件名和大小，落盘读回核对后返回 verified。
配套 harness、浏览器接口映射与真实输入要求见[Web 浏览器操作契约](../../docs/agents/verification.md#web-浏览器操作契约)。
`preserveStorage` 需在备份和恢复前停止游戏写入；persistBackup 必须落盘并读回完整快照，验证成功后才允许测试写入。
快照只接受能无损编码的普通对象、数组、JSON 标量、Date、ArrayBuffer 和支持的 typed-array/DataView；
遇到其他类型、循环、非有限数值或普通对象的 `__qaType` 字段时，在测试写入前停止。
退出恢复原 origin 全部记录，不以清空 IndexedDB 代替恢复；浏览器客户端仍按环境提供的能力操作。

## 大型生成源码的有限检索

`er source-context FILE NEEDLE` 两个位置参数必填；needle 非空且最多200字符。
可选 `--radius INTEGER` 默认160、范围0～500；`--limit INTEGER` 默认5、范围1～20。
按字符偏移输出有限片段（换行转义），没有匹配不输出；不打印 minified 文件的完整长行。

```sh
uv run er source-context "build/web/<buildId>/index.js" needle --radius 160 --limit 5
```

先从 `build/web/build-info.json` 读取 buildId 替换路径。需要完整分析产物时写临时文件，会话只返回结论和定位。

## 退出码与中断

成功通常为0；Typer 参数错误为2。运行故障通常为1，底层命令失败和 check 会保留相应非零码，
SIGINT / SIGTERM 分别为130 / 143。`--help` 不执行命令业务，但外层 `uv run` 仍可能同步 Python 环境。
终端中断会先展开命令的 finally 清理；SIGKILL 无法清理，应检查保留的配置恢复材料或备份后再继续。
恢复失败、版本不一致或备份失败不能记录为通过；保留批次及错误输出用于复核。
