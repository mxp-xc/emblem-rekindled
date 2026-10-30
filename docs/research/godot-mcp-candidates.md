# 较高 star Godot MCP 对本游戏的接入价值

结论入口：[Godot AI开发工具适配调研](godot-ai-tools.md)。

调研日期：2026-10-30。对应 [本游戏 AI 工具适配评估](https://github.com/mxp-xc/emblem-rekindled/issues/15)。本轮为只读上游资料、源码与 GitHub API 核对，没有安装、运行候选或创建工程。

## 判断

较高 star MCP 值得重新比较，但本轮证据不支持直接把 stars 最高的 Coding-Solo 选作首关开发的默认依赖。它主要把已有 CLI 和基础场景操作包装成 MCP；我们更缺的点选、拖动、触屏、运行中状态和截图反馈，它当前主分支没有提供。

本次新增的 **tugcantopaloglu/godot-mcp** 更值得列入后续试用短名单：社区规模高于前轮两个运行时候选，确有触屏、截图、动画和场景操作源码，兼容已选标准版 GDScript。代价是 Node 服务与项目 runtime autoload，且实引擎 CI 证据不足；应以固定新 SHA 做隔离验收，不能直接当已验证的生产工具。它不因这次推荐成为工程设计的前置依赖。

**Godot-MCP-Native** 在功能和额外运行时成本上也有价值，但当前 HTTP 默认监听与鉴权问题、Codex 接入反馈和测试版本差异，需要先解决/核验；本轮不把它作为直接照默认配置安装的首选。

对我们的实际增益建议分开判断：规则结算、存读档和构建仍由正式项目的 CLI 检查与行为测试负责；MCP 的优先价值是帮助 agent 在 Godot 编辑器/桌面运行中观察竖屏 UI、点选与拖动、战斗演出和错误。它们不证明 Android 真机或 Web 平台已经通过验收。

## 样本与证据边界

按 GitHub `godot mcp in:name` 按 stars 排序的当日快照，重点选前三个适合现有标准版环境的开源方向。stars 是社区规模快照，非可靠性结论。维护日期按 API 返回日期记录，不将 UTC 的时分秒写作本地时间。

| 仓库 | 规模/维护 | 实际接入方式 | 对我们最有价值与欠缺之处 |
| --- | --- | --- | --- |
| [Coding-Solo/godot-mcp](https://github.com/Coding-Solo/godot-mcp) | 6,438 stars、512 forks、MIT；主分支 `1209744f`，最后提交日期 2026-04-16 | Node.js 18+ stdio MCP；启动 Godot CLI，复杂操作执行随包 GDScript；不要求复制编辑器 addon | 无侵入包装启动/停止、日志、创建/修改场景和贴图；当前只有14个工具，无截图、输入模拟或实时场景树。已有 shell+Godot CLI 时增量价值较小。 |
| [yurineko73/Godot-MCP-Native](https://github.com/yurineko73/Godot-MCP-Native) | 863 stars、MIT；主分支 `eef48071`，最后提交日期 2026-08-03；release v1.0.8 日期 2026-07-26 | 原生 GDScript 编辑器插件提供 HTTP/stdio；无需 Node/Python server；可选额外 Rust 编译的 gdmcp CLI 和随包 Codex skill | 实时场景/日志/截图、ScreenTouch/Drag、动画/音频等工具对首关有用；但默认 HTTP 的具体缺口、Codex 工具发现反馈，以及使用旧 TileMap 路径等需核验。 |
| [tugcantopaloglu/godot-mcp](https://github.com/tugcantopaloglu/godot-mcp) | 506 stars、MIT；主分支 `88f0fbc6`，最后提交日期 2026-10-09；release v3.1.0 日期 2026-07-13 | Coding-Solo 扩展版；Node stdio MCP + headless 场景/资源脚本；运行时功能需注册 `McpInteractionServer` autoload，TCP `127.0.0.1:9090` | 有 `game_click`、`game_drag`、`game_touch`、`game_screenshot`、节点读写/调用、动画等实现；适合桌面内可观察的点选/演出检查。额外接口较大，需限定实际使用能力；运行探针不能随正式游戏发布。 |

来源：各仓库 README、源文件、[GitHub 仓库搜索 API](https://api.github.com/search/repositories?q=godot+mcp+in%3Aname&sort=stars&order=desc&per_page=12)、仓库 metadata/commits/releases API。本轮也看到收费仓库及 C#/.NET 方案；它们不能提供比当前样本更低的标准版 GDScript 接入成本，因此没有继续扩大调查。

## Coding-Solo：社区最大，但增益和验证有明确边界

- [固定 SHA 的工具定义与处理器](https://github.com/Coding-Solo/godot-mcp/blob/1209744fad78f3998f98c7394fd0f6ef50da5281/src/index.ts#L666) 实际列出14个工具。场景修改经 `executeOperation()` 用 `--headless --path ... --script godot_operations.gd` 执行；`run_project` 通过子进程收集 stdout/stderr。并没有实时编辑器 bridge/TCP runtime 或截图/输入工具。不能把某些 fork 对祖先的描述当作当前原仓库已经具备的能力。
- [源码树](https://github.com/Coding-Solo/godot-mcp/tree/1209744fad78f3998f98c7394fd0f6ef50da5281) 中未见测试目录或 `.github/workflows` 测试工作流；[package.json](https://github.com/Coding-Solo/godot-mcp/blob/1209744fad78f3998f98c7394fd0f6ef50da5281/package.json) 没有 test 脚本。Actions API 仅返回动态 Copilot review。未找到 Godot4.7/4.7.2 实引擎测试证据，不能以 MCP 客户端能加载来证明 Godot 场景操作正确。
- 当前最后一次提交是 [修复任意脚本实例化问题](https://github.com/Coding-Solo/godot-mcp/commit/1209744fad78f3998f98c7394fd0f6ef50da5281)，不是没有维护修复过；之后较久没有主分支提交是维护风险信号，不能单独断言项目已弃用。
- [UID 假成功报告](https://github.com/Coding-Solo/godot-mcp/issues/102) 描述绝对路径被拼成错误 `res:///...` 且返回成功；当前 TypeScript 仍将宿主路径传给重存操作，GDScript 仍直接添加 `res://`，源码与该报告相符。该报告来自 WSL/Windows；本轮没有在 macOS 重现。它提示我们试用时必须比较实际资源变化，不能只看 success。
- [启动错误丢失反馈](https://github.com/Coding-Solo/godot-mcp/issues/106)、[输入请求](https://github.com/Coding-Solo/godot-mcp/issues/68)、[视觉回放请求](https://github.com/Coding-Solo/godot-mcp/issues/88) 仍开放；这些是用户反馈，不自动证明所有环境都失败。`run_project` 源码会在 spawn 后立即报已启动，并在退出时清空 activeProcess；因此“启动返回成功”也不能代替后续错误检查。
- [Godot4.7支持提问](https://github.com/Coding-Solo/godot-mcp/issues/111) 尚无回复；这不是不兼容证明，只说明当前没有由它得到支持承诺。
- GitHub tags 列表为空，latest release API 返回404。README 有 npm 分发方式，但本轮没有核验 npm 包与当前修复 SHA 一致；未来若试用，必须单独对齐固定的实际来源版本。

## Native：功能有用，当前接入问题已核对到固定源码

- [runtime probe](https://github.com/yurineko73/Godot-MCP-Native/blob/eef4807190e7765e69d59c9e707d0ba170f6770d/addons/godot_mcp/runtime/mcp_runtime_probe.gd) 确有截图、`Input.parse_input_event`、ScreenTouch/Drag、AnimationPlayer 查询/播放等实现；[触屏集成测试](https://github.com/yurineko73/Godot-MCP-Native/blob/eef4807190e7765e69d59c9e707d0ba170f6770d/test/integration/test_runtime_touch_input_flow.py) 检查游戏脚本收到的输入事件，并非只断言工具返回成功。这一层比仅提供文档有价值，但测试文件存在不等于本轮或 CI 已通过。
- [实际 CI](https://github.com/yurineko73/Godot-MCP-Native/blob/eef4807190e7765e69d59c9e707d0ba170f6770d/.github/workflows/gdmcp-cli.yml) 主要跑 Rust CLI 检查/测试、Python 语法和包装契约；Godot 部分固定4.6.1，只解析 CLI installer 脚本，没有执行完整截图/触屏集成流。主分支 [2026-08-03 run](https://github.com/yurineko73/Godot-MCP-Native/actions/runs/30792045413) success；之后两个 run 为其他 SHA 的 failure，不能将它们当主分支当前失败。没有找到本项目4.7.2/macOS的实测证据。
- [上游具体报告](https://github.com/yurineko73/Godot-MCP-Native/issues/78) 对应的正是当前 `eef48071`。本轮核对 [HTTP 实现](https://github.com/yurineko73/Godot-MCP-Native/blob/eef4807190e7765e69d59c9e707d0ba170f6770d/addons/godot_mcp/native_mcp/mcp_http_server_legacy.gd#L95)：`listen(_port)` 没有显式指定 loopback；[默认设置](https://github.com/yurineko73/Godot-MCP-Native/blob/eef4807190e7765e69d59c9e707d0ba170f6770d/addons/godot_mcp/native_mcp/settings_manager.gd) 为 `auth_enabled=false`、`cors_origin="*"`；[HTTP 外层](https://github.com/yurineko73/Godot-MCP-Native/blob/eef4807190e7765e69d59c9e707d0ba170f6770d/addons/godot_mcp/native_mcp/mcp_http_server.gd#L29) 的 allow_remote/loopback 检查只在 CLI route。它影响的是开发机上的 MCP 接入，不是游戏玩法。报告者称改绑定后在4.7.2可用，属于报告者现场结果，不是我们验证过。
- README 有 Codex HTTP 配置，但 [工具未暴露反馈](https://github.com/yurineko73/Godot-MCP-Native/issues/24) 仍开放。需要以后核对当前 Codex 客户端实际加载；不能仅凭提供配置片段就承诺接入成功。
- runtime probe 的 TileMap 工具仍以 `TileMap` 类型解析，未见对应 `TileMapLayer` 路径；不应直接当作已覆盖新 Godot 地图结构。我们仍可使用它观察节点和输入，地图业务数据的正确性依然由项目接口检查。

## tugcantopaloglu：值得加入下一轮试用，但要区分新主分支和旧 release

- [当前 runtime 源码](https://github.com/tugcantopaloglu/godot-mcp/blob/88f0fbc69a08225d4fdec32f921209e127f52395/src/scripts/mcp_interaction_server.gd) 确有截图、鼠标点击/拖动、触屏 press/release/drag、AnimationPlayer、节点属性/方法等处理。Godot4.7兼容是维护者 README/release 声明，本轮没有实际运行。
- [接入说明](https://github.com/tugcantopaloglu/godot-mcp#runtime-tools-setup) 要求项目注册 runtime autoload。不是只安装 MCP server 就能观察任意正在运行的游戏；该 autoload 在启动时监听 TCP。本项目需要在开发组织设计中明确保存位置和导出排除方式，避免正式 Android/Web 包携带它或出现悬空 autoload 引用。
- [当前 CI](https://github.com/tugcantopaloglu/godot-mcp/blob/88f0fbc69a08225d4fdec32f921209e127f52395/.github/workflows/ci.yml) 在 Node22/24跑 build、Vitest和 audit；[2026-10-09 run](https://github.com/tugcantopaloglu/godot-mcp/actions/runs/37973488140) 为 success。CI没有安装 Godot，[engine-smoke](https://github.com/tugcantopaloglu/godot-mcp/blob/88f0fbc69a08225d4fdec32f921209e127f52395/tests/engine-smoke.test.ts) 在未设置 `GODOT_SMOKE_PATH` 时跳过；所以这个绿灯不能证明运行时触屏/截图通过。
- [开放 schema 反馈](https://github.com/tugcantopaloglu/godot-mcp/issues/31) 来自旧v3.1.0与具体客户端。核对当前 [工具定义](https://github.com/tugcantopaloglu/godot-mcp/blob/88f0fbc69a08225d4fdec32f921209e127f52395/src/index.ts#L1244)，已对该报告中的 args 等数组添加 items；当前还有日志游标/保留限制。不能因为issue仍开着就说当前main未修复，但 [release v3.1.0](https://github.com/tugcantopaloglu/godot-mcp/releases/tag/v3.1.0) 早于这些提交，不能以它替代当前代码。
- 标准版 GDScript 使用无需.NET。上游运行要求 Node18+，当前开发/CI要求Node22.12+；默认分发方式是源码构建。没有找到 Bun 执行兼容验证或具体 Codex Desktop 端到端证据，未来应在现有运行时条件下对齐版本及启动命令，不自行换成 bunx/npm最新包。

## 针对本游戏的试用建议

1. 现阶段继续以官方 CLI 和项目清楚的目录/命令入口做工程设计，不预装 MCP 或 skill。小规模非官方 skill 暂作可选参考，不需要先接受其架构模板和完整流程；所有本轮 MCP 也都是第三方维护。
2. 如果需要现在从较高 star 方向选一个做**后续隔离验证候选**，优先将 tugcantopaloglu 固定新 SHA 纳入短名单；它比 Coding-Solo 的 CLI 包装更接近我们的触屏/截图需求。它与前轮 satelliteoflove 二选一试即可，不必同时维护两个 bridge。根代理可结合另一个 agent 的适配评估决定先测谁。
3. 验证应对准首关：竖屏UI截图非空、角色/地格点选、地图拖动、ScreenTouch/Drag事件、独立战斗演出返回、已知语法/加载错误的实际报告、运行探针关闭后的恢复，以及不含工具的导出配置。不要只检查有多少工具或初始化success。
4. 用受控业务入口核对战局/存档内容，不依赖MCP执行任意脚本来代替正式规则接口。编辑器注入输入仍须补Android真机触屏、安全区、存储/后台恢复与Web音频/持久化验收。
5. 安装前再列清来源SHA、Node/MCP依赖、Godot探针或插件位置与版本、客户端配置修改。Native若继续评估，要先核对已修复版本或明确受限接入配置；无需为了它们改变本游戏正式运行依赖。
