# Godot AI 工具对本游戏的接入价值复核

结论入口：[Godot AI开发工具适配调研](godot-ai-tools.md)。

调研日期：2026-10-30。对应[哪些 Godot AI 工具值得用于本游戏，较高 star MCP 是否更合适？](https://github.com/mxp-xc/emblem-rekindled/issues/15)。本报告只读上游文档、源码、仓库元数据与测试配置；未安装、运行候选，未创建工程或修改客户端。较高 star MCP 的专项核对由另一名 subagent 完成，本报告不重复其比较。

## 建议调整

**当前继续以官方 CLI 为开发自动化基线，不把社区 skill 或 MCP 设为开工前置。** 后续若需要统一从 agent 调用启动、日志、场景/资源操作，较高 star 的基础 MCP 值得先验证；是否接入取决于它相对现有 CLI 和文件操作减少了多少工作。不能仅因小项目工具更多，便把它排在更大社区的基础 MCP 前面。

上一轮“优先试 haxqer skill、再试 satelliteoflove”的建议需要收窄：

- **haxqer**：保留为 API 查询、场景/资源检查和按脚本试用的候选；当前不建议整套 skill 默认启用，更不能直接复用其存档模板。发现具体产品契约差异，详见下文。
- **satelliteoflove**：对运行时观察和战斗动画调试有价值，但它明确不提供完整鼠标坐标输入，不适合作为本项目鼠标/触屏操作验收的首选；另有与我们的 CLI 导入/导出并行流程直接相关的开放问题。
- **hybridindie**：确实提供坐标鼠标事件、运行截图与编辑器操作；低 star 不等于功能虚构，但其服务/插件/运行探针、工具集发现和版本匹配成本，尚不值得在没有实际工程时优先引入。列为出现具体缺口后的备选，不能用“已有 uv”替代兼容验收。

这不是判定三者完全无用，也不是断言较高 star 方案更正确；是把选型优先级与本游戏的实际流程、用户对维护成本的偏好对齐。所有候选在本机 macOS、Godot 4.7.2 和当前 agent 客户端中的兼容性仍未验证。

## 与本游戏流程的对应

| 本游戏工作 | 官方 CLI / 文件操作能承担的部分 | MCP 或 skill 的增量价值与边界 |
| --- | --- | --- |
| typed GDScript 战斗规则、寻路、可控随机分支 | 导入、指定脚本解析检查、headless 调用规则与测试入口、读取退出码和错误输出。`--check-only` 仅解析检查，不能替代业务测试。 | haxqer 的 API 查询、诊断整理可减少手工工作；MCP 不会自动验证原作数值、命中/暴击或物品规则。生产读档可重新尝试随机结果与测试固定随机源仍由本游戏实现。 |
| 关卡数据、三章身份、物品模板与持有物品 | 编辑结构化内容并执行字段、引用和章上下文检查，不依赖实时编辑器。 | 通用场景树工具不能替我们决定跨章身份/转换语义；不应因此增加项目专属 MCP 接口或让游戏业务依赖 MCP。 |
| 首关地图、单位选格与状态面板 | 生成/修改场景资源、运行指定场景、检查加载错误。 | 实时场景树、属性读取和截图能够定位选中框/范围图层/面板遮挡，属于有价值增量。能发键盘 action 不能证明坐标点选、拖图或触摸已验证。 |
| 独立战斗演出、原像素帧与高清显示 | 脚本整理动画资源、指定场景启动、有渲染运行或录制；按来源锚点/偏移/动作编排核对。 | satelliteoflove 可读改 AnimationPlayer 轨道、预览/seek、冻结游戏时间并查看状态/画面，适合检查攻击/受击/返回地图的衔接。它不会自动还原原作 `.sp` 数据与战斗编排，也不能把静止正确的一帧当完整动作通过。 |
| Android 竖屏 UI、电脑 Web | CLI 分别导出；用实际设备/浏览器核对输入、长宽比、安全区、文字、音频和平台行为。 | 编辑器截图能帮助早期调整布局；桌面游戏的输入注入不等同 Android 原生触屏，也不等同导出的 Web。不能用同一个 MCP 的 success 响应替代两个目标平台验收。 |
| 行动间隙存档、后台恢复、读档重试 | 经真实游戏保存入口运行跨进程用例，并验证业务字段、失败时保留旧档、结果已保存与未来随机结果的区别。 | 运行状态查询可协助排查“已行动”标记或演出未完成，但只查看内存/截图无法证明文件持久化、Web 浏览器存储或 Android 杀进程恢复正确。 |
| 日常启动、导入、导出和排错 | 官方 CLI 已有入口；文件/日志由现有 agent shell 读取。 | 基础 MCP 可以把入口统一成结构化工具调用，是便利性收益；不需要因此重造构建框架或把 MCP 端口/探针放进正式包。 |

官方依据：[Godot 4.7 CLI](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)；[Web 导出及浏览器限制](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)。上表的业务验收范围来自已确认的首关与跨章规格，不声称 CLI 本身自带这些游戏测试。

## 关键源码发现

### haxqer：有实用检查工具，但默认模板不是我们的产品实现

核对 SHA：`037c03e9858ae748bf66c010aeb9942dbe9b93d6`。

- skill 明确要求写存档、HUD、状态机等时优先复制自带模板，并建议项目 scaffold、QFramework Lite 参考、逐场景 fuzz/smoke 与较广的固定检查步骤。这与本项目“先完成自身组织设计、随真实复杂度拆分、测试按业务价值选择”的约定需要逐项协调，不能把安装 skill 当成接收其默认工程组织。[SKILL.md 模板要求 L59](https://github.com/haxqer/godot-skill/blob/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot/SKILL.md#L59)、[架构参考 L54](https://github.com/haxqer/godot-skill/blob/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot/SKILL.md#L54)、[scaffold L65](https://github.com/haxqer/godot-skill/blob/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot/SKILL.md#L65)。
- 自带 `save_manager.gd` 在正式 slot 路径上直接 `FileAccess.WRITE`，没有先写临时档再替换；版本不等时只 `push_warning`，之后仍可发 `game_loaded` 并返回 `data`。因此**不满足我们已有的保存失败保留上一份有效进度、读取时验证版本/引用并明确报告失败的完整契约**。这针对该模板，不是断言所有工具不可靠。[直接写正式路径 L40](https://github.com/haxqer/godot-skill/blob/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot/templates/gdscript/save_manager.gd#L40)、[版本处理 L82](https://github.com/haxqer/godot-skill/blob/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot/templates/gdscript/save_manager.gd#L82)。
- 配套场景 runner 确实实现 mouse button/motion 的事件注入、状态断言和截图；不能把它描述为只有文档。源码中核对的 first-class step 没有 `InputEventScreenTouch/ScreenDrag`，所以不能宣称已覆盖 Android 多指或触摸手势。[scenario_runner.gd L17](https://github.com/haxqer/godot-skill/blob/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot/scripts/debug/scenario_runner.gd#L17)、[鼠标事件 L170](https://github.com/haxqer/godot-skill/blob/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot/scripts/debug/scenario_runner.gd#L170)。
- 截图需要渲染。Python wrapper 会识别 screenshot step 并默认选择有窗口运行；纯布局矩形检查可 headless，不能将它们等同于真实画面。[needs_rendering L74](https://github.com/haxqer/godot-skill/blob/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot/scripts/debug/run_scenario.py#L74)、[运行模式 L104](https://github.com/haxqer/godot-skill/blob/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot/scripts/debug/run_scenario.py#L104)。

因此可按需复核并使用 API 查询/诊断/场景检查工具；若要启用整套 skill，仍需先明确其适用范围和与项目约定的冲突处理。没有必要为了获得官方 CLI 已具备的能力先引入这一套 skill。

### satelliteoflove：本游戏最重要的指针操作存在明确缺口

核对 SHA：`c7328651d6d64cae541d79c398e3cc1ca1f4f9f4`。

- input 工具文档明确写了不支持 absolute cursor positioning；支持的是 action、joypad、键盘、relative mouse-look 和文字。对我们点选战场格子、拖动地图的操作，不能据此声称“输入测试已有方案”。[输入文档](https://github.com/satelliteoflove/godot-mcp/blob/c7328651d6d64cae541d79c398e3cc1ca1f4f9f4/docs/tools/input.md)。
- 上游专门的鼠标调研决定不加入完整 mouse/coordinate 工具：它在 Godot 4.6.3/Windows 的探针区分了读取 `event.position` 的路径和轮询物理鼠标位置的路径，后者不能靠内部事件注入覆盖；macOS/Wayland 未验证。即使我们采用事件输入，**当前公开工具仍没有坐标 click/drag 接口**；任意执行 GDScript 可以另造注入，但那不能当成已有、验证完的标准输入工具。[设计决策与范围](https://github.com/satelliteoflove/godot-mcp/blob/c7328651d6d64cae541d79c398e3cc1ca1f4f9f4/docs/design/mouse-input-spike.md)。
- 对独立战斗调试的价值是具体的：AnimationPlayer 查询、轨道/关键帧、编辑器播放/seek，以及运行时冻结/步进和状态采样。但动画编辑器预览与运行中的游戏分别由不同工具控制，不能混用。[动画工具](https://github.com/satelliteoflove/godot-mcp/blob/c7328651d6d64cae541d79c398e3cc1ca1f4f9f4/docs/tools/animation.md)、[时间步进工具](https://github.com/satelliteoflove/godot-mcp/blob/c7328651d6d64cae541d79c398e3cc1ca1f4f9f4/docs/tools/game-time.md)。
- 插件 `_enter_tree` 会写入并保存 `MCPGameBridge` autoload。桥接脚本会检查 `EngineDebugger.is_active()`，但这不等同于已经保证开发探针不会进入导出包；若将来采用，需要验证关闭/移除插件与正式导出配置。[注册 autoload L250](https://github.com/satelliteoflove/godot-mcp/blob/c7328651d6d64cae541d79c398e3cc1ca1f4f9f4/godot/addons/godot_mcp/plugin.gd#L250)、[运行桥接 L42](https://github.com/satelliteoflove/godot-mcp/blob/c7328651d6d64cae541d79c398e3cc1ca1f4f9f4/godot/addons/godot_mcp/game_bridge/mcp_game_bridge.gd#L42)。
- 开放的 [headless 导入/导出端口冲突问题](https://github.com/satelliteoflove/godot-mcp/issues/403) 报告环境是 Godot 4.7.2/Windows：正常编辑器占用端口后，CLI 导入/导出又启动 server 导致 `ERROR`；维护者认可应对 one-shot runs 跳过 server 的方向，当前报告仍 open。这不是我们本机复现，但它与本项目既定 CLI 入口直接相关，值得列入试用门槛。
- CI 配置跑 Node20 build、coverage 和 stdio protocol，未在该工作流安装 Godot；仓库中存在引擎探针不能单独证明最近 main 的引擎行为通过 CI。[当前 CI](https://github.com/satelliteoflove/godot-mcp/blob/c7328651d6d64cae541d79c398e3cc1ca1f4f9f4/.github/workflows/ci.yml)。

因此它更适合“出现动画/运行观察痛点后专项试用”，而不是当前默认首选。

### hybridindie：坐标输入更贴近战棋，但仍有集成成本

核对 SHA：`e507176625a062a4c7ddff24c5e53a3d92612a82`。

- `simulate_mouse(x,y,button,pressed,relative_x,relative_y)` 和 `play_input_sequence` 真实存在；运行探针将坐标放进 `InputEventMouseMotion`/`InputEventMouseButton.position` 后调用 `Input.parse_input_event`。可以构造移动、按下、移动、释放的事件序列；**源码存在这条路径，不等于已证明我们真实窗口中的拖图/缩放和所有轮询鼠标逻辑正确**。[输入工具](https://github.com/hybridindie/godot-mcp/blob/e507176625a062a4c7ddff24c5e53a3d92612a82/mcp_server/tools/input_sim.py)、[探针 L249](https://github.com/hybridindie/godot-mcp/blob/e507176625a062a4c7ddff24c5e53a3d92612a82/godot/addons/godot_mcp/mcp_runtime_probe.gd#L249)。
- checked input surface 为 key/mouse/action，没有原生 screen touch/drag 工具。上游有 Godot 4.7 下合成 key/mouse 能抵达 `_input` 并更新 action 的 smoke test，但它是 headless 路由测试，不是窗口的物理指针、多点触屏或 Android 验收。[注入 smoke](https://github.com/hybridindie/godot-mcp/blob/e507176625a062a4c7ddff24c5e53a3d92612a82/godot/tests/input_inject_smoke.gd)。
- 运行截图从 viewport texture 取 image，明确处理没有渲染帧的失败；不是只要 headless 成功就会有真实截图。[截图路径 L183](https://github.com/hybridindie/godot-mcp/blob/e507176625a062a4c7ddff24c5e53a3d92612a82/godot/addons/godot_mcp/mcp_runtime_probe.gd#L183)。其 e2e 工作流说明 editor 可以 headless，但 play-session 套件需要 Xvfb/display；引擎测试比单纯 Python contract tests 提供更多依据，仍不能替代 macOS/4.7.2 实测。[e2e 配置](https://github.com/hybridindie/godot-mcp/blob/e507176625a062a4c7ddff24c5e53a3d92612a82/.github/workflows/e2e.yml)。
- 上游列出 Codex CLI 不自动刷新工具列表，建议启动时预开需要的 toolsets；当前 desktop 不能由此自动推定已兼容。默认开太多工具也增加 agent 选择与上下文成本。[客户端说明](https://github.com/hybridindie/godot-mcp/blob/e507176625a062a4c7ddff24c5e53a3d92612a82/docs/site/getting-started-clients.md)。
- 依赖 Python3.11+、FastMCP/MCP 等服务依赖、editor addon 与 runtime probe。使用现有 uv 只能降低环境准备的一部分成本，不能省去服务/插件一致性、端口/进程管理与正式包排除验证。[pyproject.toml](https://github.com/hybridindie/godot-mcp/blob/e507176625a062a4c7ddff24c5e53a3d92612a82/pyproject.toml)、[输入运行拓扑](https://github.com/hybridindie/godot-mcp/blob/e507176625a062a4c7ddff24c5e53a3d92612a82/mcp_server/tools/input_sim.py)。

## 社区规模与维护证据

当日 GitHub REST 元数据快照；最后 push 时间转换为本地时区。`open_issues_count` 包括 PR，不拿它当缺陷数。push 可能来自依赖更新，也不直接代表功能质量。

| 候选 | stars / forks | 许可 | 最后 push | 判断 |
| --- | --- | --- | --- | --- |
| haxqer | 252 / 5 | MIT | 2026-09-23 15:44:36 | 有实际引擎检查工具，但外部使用规模较小；无 open issue 不能证明无缺陷。 |
| satelliteoflove | 182 / 22 | MIT | 2026-10-03 06:35:26 | 有明确且诚实的输入限制说明、维护者回复；也有尚未解决的本项目相关 CLI 冲突报告。 |
| hybridindie | 45 / 10 | MIT | 2026-10-27 01:22:30 | 提交和测试面活跃，但社区样本更小、接口/集成面更大；不适合仅凭功能数量直接优先接入。 |

数据入口：[haxqer 仓库 API](https://api.github.com/repos/haxqer/godot-skill)、[satelliteoflove 仓库 API](https://api.github.com/repos/satelliteoflove/godot-mcp)、[hybridindie 仓库 API](https://api.github.com/repos/hybridindie/godot-mcp)。

## 后续若决定试用，最小验收

这些是后续设计/试用建议，不是本轮安装或开发操作。

1. 用同一获准的试验场景比较官方 CLI 与一个 MCP：能否准确报告一个预先制造的脚本错误（文件/行/堆栈）、场景加载失败及退出状态；失败不能仅返回 success。
2. 对战棋必要的指针动作，至少验证一个非原点格子的点选、按下拖动再释放、镜头移动/缩放后坐标转换；读取业务选中格/镜头状态确认结果，不能仅断言“事件已发送”。原生触屏与多指手势仍单独验收。
3. 有渲染窗口中，验证720×1280及另一实际长宽比的非空截图和布局；headless 状态测试与视觉检查分别报告。
4. 验证独立战斗开始/受击/结束三个阶段、返回地图时机和演出中重复输入约束；暂停/步进不替代正式业务状态机。
5. 编辑器开启时再运行 headless 导入/规则检查/导出，检查端口冲突、进程清理、并行客户端限制和关闭 MCP 后仍可构建运行。
6. 检查 addon/runtime autoload/探针与正式包的关系；Android/Web 自身可运行、存档与输入验收仍然独立。

安装增量需届时单独列清并先对齐：haxqer 为技能与 Python/GDScript 脚本；satelliteoflove 为 Node20+ server、addon 与桥接；hybridindie 为 Python/uv 服务依赖、addon、runtime probe 和客户端 toolset 设置。此轮未安装任何候选。
