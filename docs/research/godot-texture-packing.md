# Godot 图集与生成素材的仓库组织

调研日期：2026-11-01。对应 [research issue #30](https://github.com/mxp-xc/emblem-rekindled/issues/30)，属于 [主线地图 #1](https://github.com/mxp-xc/emblem-rekindled/issues/1)。

后续实施：用户随后要求尽早完成章内共享图片，实施由[共享资源任务](https://github.com/mxp-xc/emblem-rekindled/issues/31)跟踪。
以下统计与“本轮不迁移”建议保留为调研时点记录；当前所有权、导入与改图约定以
[开发说明](../development.md#章内共享图片与改图)为准。后续已采用物理图集和逻辑图片路径，迁移实测见[原版与重制版对照](original-remake-footprint.md)。

## 判断

本轮建议保持现有散 PNG 和 `.import`，不立即迁移。Godot 原生支持“多图合一，按矩形区域读取”，也有自动把多个源 PNG 装箱的 importer；但自动图集仍需要源 PNG 和各自的导入配置，不能直接解决 Git 中条目太多的问题。要明显减少仓库文件数，需要改变随仓库保存的素材快照形式，这会增加单图编辑、资源引用和生成工具的维护工作。

用户关注的 Git 条目和以后改图确实有改善空间，尤其是后续逐关扩展。本轮发现 m1 的 1305 张 appearance PNG 中，有 775 张与 m0 某张 appearance PNG 的完整 bytes 相同。建议在继续大范围扩关前，优先评估章内共享素材、避免按关重复保存图片；这可以保持现有纹理读取和动画偏移，改动面通常小于全面引入 atlas region。不能只因当前 PNG 合计 2.35 MiB 就忽略增长问题。

图集作为下一层选择：若消除跨关重复之后文件数仍影响审阅，再小范围评估“按角色外观分组的无损图集 + 可读 region 清单”，保留人工替换素材的独立文件。不建议先做全章大图、源 ZIP 构建前展开或额外 PCK 挂载系统。当前没有加载、显存或渲染瓶颈证据，不以性能提升作为此次迁移理由。

这是研究建议，没有修改图片、importer、manifest、Godot 导入设置、导出流程或正式运行包。

## 当前项目的实际成本

以下为本地 tracked 文件和当前源码的只读核对，不包含 `.godot` 缓存和已有 APK/PCK 的大小。

| 内容 | 数量 / 大小 | 对判断的影响 |
| --- | --- | --- |
| 全部 PNG，均在 `game/content/chapter_1/generated/` | 2906 个，2,463,558 bytes，约 2.35 MiB | 主要问题是条目数，不是当前源图片字节数 |
| 全部 `.import` | 2914 个，2,949,335 bytes，约 2.81 MiB | 比 PNG 字节数略大，但保存导入配置与 UID，并非可随意删除的缓存 |
| generated 内 `.import` | 2912 个 | 2906 张图片及 6 条 Ogg；另两份对应字体与 settings.svg |
| m0、m1 的 `battle/` PNG | 分别 918、1538 个，共 2456 个，占 PNG 的 84.5% | 若以后治理，应先看独立战斗素材，而不是平均改动所有素材 |
| 两关 `appearances` | 112 + 218 个外观，共 704 + 1296 帧 | 按外观合图可覆盖主要条目；同外观不等于同一角色，有装备和阵营差异 |
| PNG 宽高组合 | 212 种；其中 64×64 为 256 张 | 多数素材不适合统一等格切片，战斗帧尺寸尤其不一致 |

统计使用 `git ls-files`、文件长度与 PNG IHDR 宽高，没有重新计算内容摘要。两关独立战斗 PNG 共 1,941,174 bytes；不能用压缩后 PNG 大小推断运行时显存。

仓库依据：

- [工程组织基线](../design/project-organization.md) 第 3 节明确：`generated/` 是已转换、随仓库管理的可运行快照；普通运行与导出不应重新读取原 JAR。`authored/` 是人工内容和替换素材，生成器不得覆盖它。章内容按章隔离。
- 调研时的导入器只在更新来源时调用本地 JAR、Java renderer 与音频转换；随后复制新结果，并按 provenance 清理旧结果及其 `.import`。当时的 `finish_second_battle()` 将 m1 manifest 指向章内资源和共享音乐。以下是该时点的历史样本，不对应当前 CLI 模块：m1 输出目录独立，人物外观和 UI 等仍逐关生成；m1 还将可携带武器范围扩至 1～52，覆盖队伍换装，所以不能把 m1 比 m0 多的素材全部判断为浪费。
- [`tools/resources/content/Chapter1MapAssets.java`](../../tools/resources/content/Chapter1MapAssets.java) 的 `exportCycle()` 生成 64×64 地图帧，并在 `map_animations.json` 保存顺序、时长和源帧信息。两关各 32 个地图人物、96 条活动/已行动帧引用。
- [`tools/resources/content/Chapter1BattleAssets.java`](../../tools/resources/content/Chapter1BattleAssets.java) 的 `rasterize()` 先画到临时画布，再裁掉透明边框，保存 `offsetX/Y`、宽高与空帧标记。当前动画偏移已有业务含义，不能把图集里的 x/y 替换进去。
- [`tools/resources/content/Chapter1BattleClips.java`](../../tools/resources/content/Chapter1BattleClips.java) 的 `raster()` 同样裁剪、复用已有 texture ID，并把舞台位置保存为 x/y。图集迁移还要处理这套 ID 到纹理的映射，不能只改 appearance 帧。
- [`game/features/tactical_map/tactical_map.gd`](../../game/features/tactical_map/tactical_map.gd) 的 `setup()` 按 manifest 加载 `Texture2D`，`_draw()` 根据序列选帧；并不依赖 `AnimatedSprite2D`。
- [`game/features/battle/battle_canvas.gd`](../../game/features/battle/battle_canvas.gd) 的 `_texture()` 延迟加载并缓存；`_draw_foreground()` 加上帧偏移，`_draw_clipped()` 按视口再裁剪。UI、剧情也有各自的纹理入口。
- [`game/app/battle_clip_library.gd`](../../game/app/battle_clip_library.gd) 的 `_frames_valid()`、[`chapter_content.gd`](../../game/app/chapter_content.gd) 的动画校验目前要求 frame 的 `texture` 是存在的资源路径。直接改成路径加 region 需要同步更新校验和读取边界。
- [`.gitignore`](../../.gitignore) 已忽略 `game/.godot/`；[`game/export_presets.cfg`](../../game/export_presets.cfg) 使用 `all_resources` 并明确包含 JSON，排除测试及 provenance；[`tools/emblem_dev/commands/build.py`](../../tools/emblem_dev/commands/build.py) 承担当前正式导出。玩家运行已有 APK/Web PCK，与 Git 中的散图数量是不同层面。

### 跨关重复与扩关增长

直接读取 PNG 的完整 bytes 并比较，没有计算 hash。这里统计磁盘文件，appearance 文件含 projectile，因此与上表只统计 `frames` 的 704/1296 不同。

| 样本 | m0 / m1 PNG 数 | 两关相同相对路径 | 其中完整 bytes 相同 |
| --- | --- | --- | --- |
| `battle/appearances/` | 713 / 1305 | 245 | 160；另 85 张同路径内容不同 |
| 整个 `battle/` | 918 / 1538 | 434 | 349，m1 对应文件合计 278,516 bytes |
| `map_units/` | 96 / 96 | 78 | 21 |
| `ui/` | 76 / 78 | 76 | 76 |
| `story/` | 17 / 20 | 17 | 17 |

进一步不限定相对路径，按文件长度筛候选、再比较完整 bytes，m1 有 775 张 appearance PNG 可匹配 m0 某张 appearance PNG，共 675,226 bytes。这些是可以共享同一不可变图片的候选，不是说 775 个角色/外观定义应合并。相同图片也可能出现在不同角色、装备、方向、动作位置；应保留这些定义及各自偏移，只让纹理引用复用。反过来，85 张同相对路径而内容不同，证明不能按部署 ID 或路径直接认定跨关图片相同。

当前两关本地 PNG 数分别为 1141、1765。`Chapter1Story.exportWorld()` 的结果有 17 个世界节点，但节点本身没有一一声明已验证的战术图身份；目前只接入 m0/m1，因此不能把 17 直接当作已核实的战术关卡总数。若后续机械沿用“每关完整导出一份共享视觉素材”，新增 N 个与 m1 规模相近的关卡会再产生约 `1765 × N` 个 PNG，以及近等数量的 `.import`；这只是增长情景，实际取决于新增角色、武器覆盖和关卡差异。作为量级示例，假设最终需要 17 份同量级关卡目录，会达到约 1.9 万～3 万张 PNG，而不是继续停留在当前两关的 2906 张。

因此，在全初章扩展前收拢章内共享图片有明确的文件数收益。它并不要求跨章共用资源，也不要求图集：优先在当前章中维护已确认相同的视觉资源，关卡 manifest 仍保存自己的单位、动作、剧情与映射。当前路径是相对 manifest 解析的；若抽出资源，需要明确章内公共路径或相对引用，并同步生成器的所有权和清理规则，防止重导入某一关时删除其他关正在引用的图片。

## Godot 原生能力核对

### AtlasTexture：任意矩形区域，适合现有 Texture2D 入口

`AtlasTexture` 本身是 `Texture2D`：`atlas` 引用大图，`region` 定义取图矩形，多个资源可以共享同一底图；`margin` 可以表达额外留白，`filter_clip` 用于限制周边像素渗出。它只提供区域引用，不会自己把磁盘上的多个 PNG 拼成一张图。[官方 AtlasTexture 文档](https://docs.godotengine.org/en/4.7/classes/class_atlastexture.html)

对本项目的推论：如果将来迁移，可在加载边界把 manifest 的图集路径和 region 转成 `AtlasTexture`，继续交给多数现有 `Texture2D` 绘制入口。原有舞台偏移仍保留，atlas 坐标另设字段。每帧新建一个独立 `.tres` 虽然直观，却会重新增加大量文件；也可以在一个资源中保存多个 subresource，或保留 JSON 并在加载时创建区域对象。具体实现应按真实改动范围选择。

对现有 `_draw_clipped()` 的区域内二次裁剪、UI 局部进度条、透明边界和缩放仍需做实际图像回归；仅凭类型兼容不能宣称视觉完全一致。

### Sprite2D、SpriteFrames：有现成切帧和预览，但不要求换播放器

`Sprite2D.hframes/vframes` 将 sprite sheet 分为规则行列，通过 `frame` 或 `frame_coords` 选帧；任意矩形则可使用 `region_enabled/region_rect`。这适合等尺寸网格，并不会替不同大小的裁剪战斗帧管理原有锚点。[官方 Sprite2D 文档](https://docs.godotengine.org/en/4.7/classes/class_sprite2d.html)

`SpriteFrames` 保存动画、`Texture2D` 帧、速度与相对时长，供 `AnimatedSprite2D/3D` 播放。编辑器支持从散图或 sprite sheet 加帧并预览。[官方 SpriteFrames 文档](https://docs.godotengine.org/en/4.7/classes/class_spriteframes.html)、[官方 2D 动画教程](https://docs.godotengine.org/en/4.7/tutorials/2d/2d_sprite_animation.html)

本项目已经有动作、特效、HP 与时序编排，合图不要求把它们改成 `SpriteFrames`。如果以后单纯需要地图待机编辑器预览，可以另评估该资源；不把整套演出播放器替换列为文件治理的前置工作。

### ResourceImporterTextureAtlas：确有多源自动装箱，但不减少源文件

官方类页给出 `atlas_file`、Region/Mesh 模式、透明边界裁剪等设置；文字描述容易被理解为只裁一张现成 spritesheet。实际核对 4.7 官方实现：`get_option_group_file()` 返回 `atlas_file`，`import_group_file()` 遍历同组的多个源文件、逐张加载，调用 `EditorAtlasPacker::chart_pack()`，写出 atlas PNG，并为每个源生成 `AtlasTexture` 或 `MeshTexture` 导入结果。因此，多个 PNG 指向同一个 atlas 输出路径时，原生 importer 确实能自动打包，无须先自写装箱算法。[官方类页](https://docs.godotengine.org/en/4.7/classes/class_resourceimportertextureatlas.html)、[官方 4.7 importer 源码](https://github.com/godotengine/godot/blob/4.7/editor/import/resource_importer_texture_atlas.cpp)

源码中的 Region 模式可保持原图尺寸：`crop_to_region=false` 时，生成资源通过 margin 还原原图留白。图集输出路径也需要被 Godot 正常导入；源 PNG 的路径通过导入映射加载对应资源，源图和每图设置依然是重导入输入。它有机会降低运行纹理切换，却会保留现有几千份源文件，另加图集，不能用来直接压缩当前 Git 文件列表。不能删除源图后还期待它继续为这些源图重建区域资源。[同一官方实现](https://github.com/godotengine/godot/blob/4.7/editor/import/resource_importer_texture_atlas.cpp)

本轮仅核对文档与源码，没有在本机 Godot 4.7.2 新建隔离工程验证 importer UI、重导入和导出行为。

### `.import` 与 `.godot/`：配置应保留，缓存可以重建

每个源素材旁的 `<asset>.import` 保存导入配置，官方要求提交版本控制；Godot 转换后的资源位于 `.godot/imported/`，可删除并自动重新导入，官方不建议提交 `.godot/`。代码加载导入素材应走 `ResourceLoader`，不能把“编辑器可用 FileAccess 读取源 PNG”当作导出包契约。[官方导入流程](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/import_process.html)

本项目抽查的 PNG `.import` 含 `uid`、importer、目标 `.ctex` 路径和压缩等参数。因此只把 `*.import` 加入 `.gitignore` 会丢掉当前已保存的 UID 和设置；项目默认导入参数可以统一新增图片的默认值，却不能等价代替每个已有资源的身份和例外配置。自动图集沿用源资源路径，仍保留其 sidecar；只保存新图集时，则管理新图集的 `.import` 与完整 region 清单，不伪造旧 UID。

### PCK/ZIP：资源包与源素材快照 ZIP 是两回事

Godot 可以按导出预设生成 PCK 或 ZIP 资源包，且 `ProjectSettings.load_resource_pack()` 可将额外资源包挂入 `res://`；同路径文件默认可被新包替换，需要控制挂载时机和路径冲突。这是运行资源分发能力。[官方资源包指南](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_pcks.html)、[官方 load_resource_pack API](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-method-load-resource-pack)

导出指南将 PCK 定义为默认、通常推荐的未压缩格式，ZIP 是压缩、普通工具易读写的格式；读写和体积取舍不能外推成当前 PNG 集合必然能压缩多少。[官方 PCK/ZIP 对比](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html#pck-versus-zip-pack-file-formats)

把源 PNG 和 `.import` 装进普通 ZIP，构建前展开，属于本项目自建的素材准备步骤。它不会自动生成 Godot 所需的导入结果；不能将这种源 ZIP 直接当作已导出的 Godot 纹理资源包替换当前 `load()` 契约。若要运行时读原始图片，则是另一种运行加载设计，超出本轮文件治理需求。现有正式导出已经封装资源，无须再加一层 PCK 来解决 Git 列表问题。

## 方案比较

下面的维护成本是基于当前代码的工程判断，未做运行性能对比。所有方案都可以在充分保存转换后素材的前提下做到无原 JAR 普通构建；区别在于需要额外保留什么、预处理什么。

| 方案 | 仓库文件数与审阅 | 单图替换、预览与导入身份 | 当前路径/动画、独立构建与扩关成本 | 本项目判断 |
| --- | --- | --- | --- | --- |
| 保留散 PNG + `.import` | 数千条，但改哪张图就对应哪条路径；JSON 可读 | 单图直接打开和替换，Godot 直接预览；保留已存 UID/设置 | 现有路径、偏移、播放器均不变；克隆后 Godot 导入即可，无 JAR；扩关沿用现有工具 | 当前成本最低，建议本轮保留 |
| 章内共享相同图片，继续散 PNG | 减少跨关重复 PNG/sidecar，保留单图 diff；并不压缩每个独立帧为一个文件 | 单图仍直接编辑/预览；共用修改会影响所有引用方，需区分人工替换身份；保留公共资源 UID/设置 | 图片路径和生成器所有权要调整，帧序列/偏移结构可不变；提交共享快照后无需原 JAR；新关复用已有视觉资源、仅新增差异 | 扩关前优先评估，比全面 atlas 迁移更贴近已发现问题 |
| 保留散图，Godot 原生自动图集 | 源 PNG/sidecar 仍在，另加 atlas；文件数不会下降 | 保持源图独立编辑，自动重装箱；需维护分组配置、atlas 导入设置和 UID | 可沿用源资源加载路径；需验证 margin、区域裁剪和导出；每章/用途分组，新图加入对应组 | 只在性能证据支持时试，不作为文件治理方案 |
| 散图为编辑源，自建工具生成图集，两者都提交 | 增加图集与 region 清单，总文件数可能更多 | 编辑便利，但源图与产物可能不同步，审阅要核对两份 | 更新生成器和加载边界；独立构建可用已提交图集；扩关要维护两份产物 | 当前收益不足 |
| 只提交无损图集 + region 清单 | 显著减少 PNG/sidecar；清单可读，但修改一帧也会改变整张图的二进制 diff | 可直接编辑 spritesheet，也可工具拆帧后重打包；须保留稳定 ID、完整区域/偏移、新图集 UID/设置；纯 JSON 不自带逐帧编辑器预览 | 更新生成器、校验和纹理入口；提交可用图集后无 JAR 普通构建；按外观/用途/章分组可限制扩关重排 | 若以后治理文件数，这是优先试验方向 |
| 源 PNG + `.import` 按章/用途保存 ZIP，展开目录忽略 | tracked 条目大降，但 ZIP 内 PNG 没有常规逐图 diff；解压后工作区文件数仍多 | 编辑需展开、重新打包，容易出现未回包修改；sidecar 必须一同保存；首次预览前先展开并导入 | 保留现有相对路径可少改运行代码，但编辑器、检查和导出都要接入准备步骤；独立构建需要仓库内完整 ZIP；扩关维护快照边界和清理旧文件 | 不作当前首选，不能把文件隐藏当作维护工作消失 |
| 只提交已导出 PCK/ZIP 并运行时挂载 | tracked 数少，内部改动不便审阅；属于编译/导出产物 | 单图修改要找可编辑源并重新导出；编辑器需额外挂载/准备；涉及已导入资源和 UID 映射 | 新增挂载时机、失败、覆盖规则、平台产物管理；仅已有包可运行不等于有可持续重建的源；每章独立分发时才有明确额外价值 | 当前已有 APK/PCK，不再添加这一层 |

ZIP 和 PCK 都无法提供 atlas 的同一底纹理区域采样；图集也不会自动减少 Git 中文件数。应先明确要改善的是提交审阅、单图创作、加载时间还是渲染，再选择对应层面的办法。

## 最小可行建议与后续试验边界

本轮维持现状，不把研究直接变成未经验证的批量素材迁移。下一次关卡素材实施时，优先检查是否继续生成大量与已有图片相同的 UI、世界/剧情图和战斗外观，再决定是否在该阶段同时整理章内共享引用。可先选择少量已确认重复图片，保持纹理类型、帧尺寸、动画顺序与舞台偏移不变，核对两个关卡加载及重导入后的所有权；这样能验证共享素材成本，无须同时引入 region 坐标。

共享素材并非零成本：目前 m0 根目录与 m1 的 provenance 分别拥有输出，盲目将 m1 指向 m0 私有输出，会使 m0 的清理行为影响 m1。应把真正共用素材交给明确的章内生成所有者，再调整两关引用。不要按路径相同就去重，也不需要为了去重引入运行时摘要计算或任意目录扫描。只要后续普通构建仍读已提交快照，就保持无原 JAR 的独立构建能力。

如果这一步已经使后续扩关的文件增长可控，可以继续保留散图。若用户仍希望显著收拢每个外观内部的多帧文件，再做下面的小图集试验。

不把本段当作已批准实施规格。最小候选是选择一个已有独立战斗外观，把该外观所有帧无损放在一张图中，生成稳定帧 ID 到 region 的可读清单；保持原有 `offsetX/Y`、时间和动作序列不变。先保持无旋转、无额外裁透明规则，避免在现有裁剪上叠加坐标变化。地图、UI、剧情、音乐和其他外观继续现状。

如果试验满足收益，再按章、用途和外观逐步采用：

1. 图集是 `generated/` 下可直接导入的快照；原 JAR 只用于明确的内容更新。不得把每次构建重新跑原 renderer 作为前提。
2. 同一帧只保留一个权威编辑来源。原版转换快照可以只留图集；人工改图仍放 `authored/`，通过明确引用生效，防止下次重新提取覆盖。需要独立编辑原版帧时提供可逆拆帧/回包入口，不要求人手算像素偏移。
3. 不生成几千份独立 `.tres` 来代替几千份 PNG。根据现有加载边界选择单个资源内的区域引用或 JSON + `AtlasTexture`，保持校验可读、缺失 region 明确报错。
4. 按分组固定排序和边界，避免新增一名角色导致全章重排。仅将当前 2000 张 appearance 帧按 330 个外观合图，理论上可少约 1670 张 PNG 及相应 sidecar；这是分组数量估算，不是已生成结果，分页上限和其他图片均未计入。
5. 比较实际改动文件数、单帧修改步骤和 diff 可理解性；再验证导入、动画顺序、原有偏移、空帧、边缘像素、UI 二次裁剪，以及无 JAR 的干净环境构建。若为了减少几个 MiB 文件引入长期维护负担，应停止迁移。

图集可能帮助减少纹理切换和 draw call，但实际结果受屏幕同时绘制的内容、裁剪、材质、装箱留白、整组加载范围和目标 GPU 影响。官方性能指南要求根据实际瓶颈判断；当前没有本项目的前后测量，不能承诺更快、更省显存或 APK 更小。[官方 GPU 优化说明](https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html)

## 核对范围与未验证事项

- 已读取项目组织基线、实际 Java/Python importer、章入口、生成 manifest 样本、GDScript 加载/校验/绘制入口、Git 忽略与导出配置；未读取或修改原 JAR。
- 外部资料先通过 Context7 定位 `/godotengine/godot-docs/__branch__4.7`，再核对官方 4.7 文档与引擎源码。多源自动图集结论以 `import_group_file()` 实现为依据，不仅依赖类页简述。
- 没有运行自动图集实验、图像对比、Android/Web 导出、性能测试或 ZIP 压缩测量；本机 4.7.2 的具体 importer UI 与目标平台效果尚未实测。
- 未引入第三方图集插件、未安装软件、未改已有源文件或素材。本报告只提出有边界的选择，不将仓库文件减少等同于运行性能提升。
