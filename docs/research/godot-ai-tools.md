# Godot AI开发工具适配调研

调研日期：2026-10-30。对应[本游戏AI工具适配评估](https://github.com/mxp-xc/emblem-rekindled/issues/15#issuecomment-6522385274)。评估对象为Godot4.7.2标准版、typed GDScript、Android竖屏/PC Web的2D像素战棋；依据只读上游文档、源码与CI记录，未安装或运行候选。

### 当前建议

1. **官方CLI继续作为基础入口，暂不把任何第三方skill/MCP设为开工前置。** 本项目agent已有文件编辑与Shell能力，规则、存档、内容校验和Android/Web构建可从项目明确的入口验证。
2. **如进入后续工具试用，先验证tugcantopaloglu/godot-mcp的固定新SHA。** 它约506stars，运行时源码具有点击、拖动、触屏事件、截图和动画操作，较贴合本游戏的地图/竖屏UI/独立战斗观察需求。代价是Node服务与项目runtime autoload，且没有Godot4.7.2/macOS实测证据；当前CI的引擎smoke默认会跳过。先比较它是否实际减少观察和排错工作，再决定是否接入。
3. **Coding-Solo/godot-mcp约6,438stars，但不是当前默认首选。** 不需要安装编辑器addon，适合统一启动/停止、日志和基础场景操作；当前14个工具没有截图、指针/触屏注入或实时场景树。对我们已有CLI的增量有限，且有与源码相符的UID路径/假成功反馈，不能只看初始化返回success。
4. **Godot-MCP-Native约863stars，功能值得关注，当前不按默认配置接入。** 原生GDScript、触屏/截图/动画能力有源码依据；但当前固定SHA的HTTP默认监听/鉴权缺口已核对到源码，另有Codex加载和TileMapLayer支持待验。需要先核对修复版本或受限接入方式。
5. **收窄上一轮skill与小规模MCP推荐。** haxqer的查询/检查脚本可按需参考，但其存档模板直接覆盖正式slot，不能直接满足我们已定的安全写档契约，不整套默认启用。satelliteoflove缺少坐标click/drag工具，留作动画/运行观察专项备选；hybridindie有坐标鼠标注入，但未提供原生触屏工具，且工具集刷新/服务与插件版本匹配仍需验证。它们不因功能数量或近期提交多而自动优先。

以上是有证据的试用顺序建议，**不是用户已选定依赖或批准安装**。这些候选均为社区维护，所有上游声明与CI证据都不代表本项目Godot4.7.2/macOS/当前客户端已通过。

主要来源：[Coding-Solo固定版本工具定义](https://github.com/Coding-Solo/godot-mcp/blob/1209744fad78f3998f98c7394fd0f6ef50da5281/src/index.ts#L666)、[tugcantopaloglu运行探针](https://github.com/tugcantopaloglu/godot-mcp/blob/88f0fbc69a08225d4fdec32f921209e127f52395/src/scripts/mcp_interaction_server.gd)、[Native当前HTTP实现](https://github.com/yurineko73/Godot-MCP-Native/blob/eef4807190e7765e69d59c9e707d0ba170f6770d/addons/godot_mcp/native_mcp/mcp_http_server_legacy.gd#L95)、[haxqer存档模板](https://github.com/haxqer/godot-skill/blob/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot/templates/gdscript/save_manager.gd#L40)、[satellite输入范围](https://github.com/satelliteoflove/godot-mcp/blob/c7328651d6d64cae541d79c398e3cc1ca1f4f9f4/docs/tools/input.md)。

### 与工程设计的关系

开发工具仅用于编辑/运行观察，不拥有业务状态或存档规则。工程组织设计无需为某个候选预造插件兼容层。以后若试用需要runtime autoload/探针，必须明确停用、并行CLI入口和正式导出的排除方式；桌面编辑器输入/截图不能替代Android真机和Web验收。

工具安装前仍先对齐来源SHA/版本、运行时依赖、Godot插件或探针、客户端配置改动和试用范围；优先复用已有工具，Homebrew不可提供的社区包需说明上游分发方式。本轮没有安装或运行候选，没有创建任何Godot工程。

详细证据与边界见[较高star MCP候选](godot-mcp-candidates.md)和[本游戏工作流与既有候选](godot-ai-workflows.md)。[工程组织设计](../design/project-organization.md)引用本调研，但不将任何候选设为开发前置。
