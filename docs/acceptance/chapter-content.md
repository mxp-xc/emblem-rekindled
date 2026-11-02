# 配置扩关与初章m2～m7验收

本轮范围为[配置驱动扩关](https://github.com/mxp-xc/emblem-rekindled/issues/36)、
[迷雾森林边缘m2](https://github.com/mxp-xc/emblem-rekindled/issues/35)，再逐关推进到m7（含）。
章级地图清单与完成计数由[初章进度](https://github.com/mxp-xc/emblem-rekindled/issues/32)维护。
本页记录验收门槛、m0/m1候选与m2/m3集成包的实际回归；m4～m7的平台验收仍须逐关执行。
开发自测与用户集中验收分别记录。默认推荐竖屏，横屏作为可选能力保留回归。

## m0/m1候选回归（2026-11-02）

本批基于`daec1e4`之后的未提交框架改动捕获实际包，未将继续开发中的源码重新导入本批。
该候选没有登记m2，也不含后续新增的地图魔法；#36完整门槛与#35真实接入另行完成。

| 平台 | 实际身份 | 已通过的真实输入 |
| --- | --- | --- |
| Android | `20261102-013229-f4415634`，安装包和运行中探针一致。 | 默认竖屏、启动1倍、UI临时调速；m0新游戏完整进入；合法世界取消前往不改继续档再进入m1；旧m1地图/头像/状态、可选横屏；移动、长弓独立战斗、HP/耐久/行动结束；菜单保存后冷启动读取完整state相等；受控boss胜利、路线1/7000金、节点1/step2；旧m0地点商店、命名世界档从m0继续档读取且继续字节不变。 |
| Web | `20261102-013219-2d323d5d`，原地址实际PCK和canvas身份一致。 | 同类m0/m1流程；实际键盘/点击、Esc逐层返回、旧档头像与横竖屏、独立战斗、精确冷恢复；世界取消、受控胜利/路线/驻留、旧地点商店；命名档覆盖取消保持原档、保存与跨关读取保持继续档。 |

Android在启动旧快照后先停止应用，完整枚举/读取本批原JSON并验证备份，再安装候选。
各次测试均在finally停止应用、恢复并验证全部原文件后清理新增JSON。
最终原文件名单/字节和方向设置再次一致，模拟器已关闭。
Web在静态同源页停止游戏写入后备份全部35项IndexedDB记录；恢复全部原键、字节、Date/权限等元数据并验证后，
才清理测试新增项。正常启动后再次核对35项完全一致，临时音乐恢复关闭，视口覆盖已清除，原地址保留。

证据入口为`temp/qa-chapter-content/android-candidate-20261102-013229-f4415634/candidate-summary.json`和
`web-candidate-20261102-013219-2d323d5d/candidate-summary.json`；后者位于同一批次根目录。
恢复凭证分别为Android的`final-restored-verified.json`和Web的`records-restored-after-reload.json`。
完整输入、状态、截图及临时驱动保留在该批次目录和`temp/code/python/`。
采用旧合法记录与明确受控的boss/世界边界，没有自然重打前置整章。

Android原`07-m1-map-landscape.png`是系统旋转中间帧，不能作为最终横屏证明，已保留并标为无效布局证据。
同一已捕获APK另开新完整保护批次，只补横屏地图和一次菜单系统Back：
有效图为`landscape-recapture-1/01-m1-landscape-stable-map.png`、`02-m1-landscape-after-system-back.png`，
两图均已实际查看，地图与HUD水平完整。`rotation-observations.json`记录应用在0.469秒已横向ready，
但系统`RotationLayer`/`BackColorSurface`仍存在；0.801秒起退出，再确认后才截图。
定向补证总计11.522秒，原JSON/方向新备份恢复凭证为该子目录的`restored-verified.json`，模拟器再次关闭。
这是QA截图时机修正，没有据此认定产品缺陷；其余候选回归结果保持。

Android本批安装与核对1.088秒；定向样本移动/战斗1.320秒、保存0.665秒、冷启动/调速/恢复5.545秒，
旧地点商店7.511秒、命名档往返6.884秒，分别记录于各次运行结果。
Web单次批量输入的冷恢复5.642秒、世界取消/开场10.402秒、受控胜利/结算/旧商店11.645秒。
Web命名档样本52.025秒包含多次工具调用与agent决策间隔，不能用作纯游戏运行基准；
以上不同流程也不与旧12秒固定m1样本作严格同比。

本批没有发现确定的产品回归。临时驱动曾因固定命中断言、保存输入后抢停、世界镜头仍移动时确认而产生假失败，
改为确认实际业务状态后补证通过，未修改生产驱动。Web一次QA调试读取未导出的FS getter导致页面中止，
重新加载后才开展业务流程；该探测错误保留在日志，不归为产品错误，未见其他error日志。
Chrome标签在检查时显示音频已静音，本批未改浏览器静音设置；仅临时打开游戏音乐检查设置，
未声称实体设备或扬声器听感通过。用户集中验收尚未开展。

## m2集成包阶段验证（2026-11-02）

固定包为Web `20261102-041816-8c8d7a68`、Android `20261102-041824-edba0286`，
导出分别7.731/14.180秒；本批没有随之后的源码修改重导或换包。
本批完成下列非死亡流程，但平台验收未整体通过，#36/#35仍不能据此关闭。

| 范围 | 已取得证据 | 剩余项 |
| --- | --- | --- |
| 两端Main与早期m2 | m1指挥官菜单、同进程切回m0后无旧人物选择；合法route0/step2世界取消不改继续档、完整进入m2/指挥官7、第一批正式与临时援军；菜单保存后冷启动1倍、UI32倍读回完整state相等。 | 不重跑这些稳定流程；修复包核对身份并补受影响链。 |
| 两端普通独立战斗 | 受控非致死boss82，实际地狱之炎独立演出、HP/耐久/行动结果、503首次对白标记及冷恢复。 | 根另确认普通boss死亡对白与退场次序缺口；本批没有用已知错误死亡链证明完成。下一包补m1的496/497及m2的503/504、退场与结算。 |
| Android地图能力 | 合法晚期route7/step7的mage8，46/51回合限制；50/46/51预览取消不改战局、整次成本/熟练/行动一次、无普通boss对白标记、三次独立冷恢复。 | 8张46过程帧能看到地图位移，但未捕获黑帧，不能据文件名声称黑闪已验证；下一包补真正视觉帧。 |
| Web地图能力 | 回合限制；50真实点击Back返回主目标页且不改战局，真实点击Confirm独立生效（无Enter兜底），一次成本与冷恢复正确。 | 稳定预览几乎满屏蓝panel，底部hint与图标被裁；触控命中区域有效不等于可见布局通过。下一包补两端可见按钮/提示和纯触控操作，再补Web46/51过程。 |

早期world fixture由`test_m2_content.prepare`的实际Session m0/m1规则边界产生，并经Store编码。
晚期使用同一已验证合法prefix和真实模板生成m2战斗记录；46/50/51在此前m10商店可取得，
本批配装、位置、HP/属性和round均明确受控，没有声称自然购买、自然训练或自然打完七张前置图。
未登记的前一地图m3不被伪造为可读世界档。9个fixture均经Session/Store JSON解码和恢复零初始化RNG核对。
生成器在`temp/code/gdscript/m2_platform_fixtures.gd`，本批输入在`temp/qa-chapter-content/m2-fixtures-final-20261102-041824/`。

本批入口为`android-m2-final-20261102-041824-edba0286/summary.json`和
`web-m2-final-20261102-041816-8c8d7a68/summary.json`，均位于`temp/qa-chapter-content/`。
Android各次新完整备份均在finally恢复原JSON名单/字节与方向，最后模拟器关闭；Web原35项键/字节/元数据恢复，
正常启动后再次全等，1倍、原音乐关闭与默认视口已恢复。原地址保留，临时8766桥关闭。
原失败记录保留：菜单指挥官需检查`menuPage=commander`，开场专用`ui.commander`不能代替；
晚期存档默认镜头不在施法者，需真实拖图后点击，并在镜头变化后重算格子坐标。
这两项QA假设修正与已确认的预览裁剪缺口分别记录，不将驱动超时当作产品失败。

修复包按下表补充，此前已过流程不重复；实际结果见随后一节。
临时Android驱动`temp/code/python/m2_platform_android.py`提供`death1`、`death2`、`50`用例，
Web静态CUA声明准备在`temp/code/javascript/m2_repair_web.js`，复用完整保护与只读helper。
这批生成器已实际通过10项Session/Store JSON恢复与零初始化RNG核对，
包括m1旧胜利记录、m2火球射程内的17,10移动目的地。

| 窄范围 | 输入与检查点 | 画面与记录 |
| --- | --- | --- |
| m1普通boss | 合法受控boss81/HP1，人物6长弓；496首战→独立战斗→497死前对白→退场→奖励/胜利。 | 保留对白、地图、独立战斗与结算帧；不重打m0/m1前置。 |
| m2普通boss与世界 | 早期合法route0/step2的受控boss82/HP1，人物7由17,9移到17,10后使用40；503→独立战斗→504→退场→奖励/胜利。 | 至少此链1倍原始短视频及关键帧；world应route0/step3、资金仅加1000；命名档落盘后冷启动1倍、UI32读取，不重复奖励且继续档字节不变。 |
| 两端地图预览 | 稳定预览中hint与完整Confirm/Back原图标可见；分别真实touch/click返回和确认，不加Enter兜底。 | 先实际看图再判布局；取消无变更，确认成本一次。Android复用50，Web结合46/51剩余业务。 |
| Web地图46/51 | 合法晚期route7/step7受控配装/站位/round6，实际UI施放；成本、熟练与行动一次，冷恢复相等。 | 46先UI临时1倍录实际canvas连续帧，需实际找到黑闪和位移；51用UI32。捕获失败保留失败，不据文件名判通过。 |

普通战斗规则会先提交HP0/hidden等权威状态，再让地图显示副本等待死前对白与退场。
因此`PlaytestProbe.snapshot`中的死亡/隐藏不能作为“对白期间地图人物消失”的判断依据；
必须实际查看对白期间地图人物本体、爆点/烟雾和隐藏后的画面，不为此新增生产写入探针。
Android短视频使用现有ADB原生screenrecord，Web拟使用现有浏览器canvas连续帧录制，
均须实际验证非空且可播放后才作为证据；启动/保存仍按业务状态等待，录制不控制游戏结算。

## 死亡与地图预览修复包复核（2026-11-02）

本批固定Web `20261102-051003-1e36db58`、Android `20261102-051011-0ad48460`，
导出7.616/13.934秒；实际PCK/canvas/探针及安装APK/探针分别一致，没有随开发换包。
两端完成m1的496/497与m2的503/504普通死亡链：死前对白期间实际地图人物本体仍在，
随后退场隐藏，再奖励与胜利世界返回。m2实际world为route0、step3、8000金（原7000加1000）；
命名世界档落盘后冷启动先1倍、再UI32倍读取，资金不重复增加，继续档字节不变。

Android的1倍原生视频位于
`temp/qa-chapter-content/android-m2-repair-20261102-051011-0ad48460/attempt-2/m2-ordinary-death-sequence.mp4`。
已实际查看并保留同目录的原视频提取帧：`m2-native-video-3.15s.png`是504对白与仍显示的boss，
`m2-native-video-3.45s.png`是爆点/烟雾，`m2-native-video-3.60s.png`是烟雾，
`m2-native-video-3.75s.png`是已空出的格子，`m2-native-video-4.00s.png`才进入XP反馈。
m1在32倍下的只读采样没有捕捉到短独立场景，但原视频的`m1-native-video-0.58s.png`
实际显示长弓独立战斗，不能因探针跳帧判演出缺失。

两端预览hint现已完整可见，真实Back/Confirm分别取消和施放，不再用Enter兜底；
Android50与Web46/51的整次耐久、熟练和行动一次、冷恢复相等均通过。
Web46在UI临时1倍录到真实地图黑闪，HUD保留，中间恢复地图并有位移：
`web-m2-repair-20261102-051003-1e36db58/map46-blackflash-real-frames.webm`
保留实际连续帧，1.423～1.489及1.557～1.623秒是黑帧；同目录
`map46-native-video-black-frame.png`与`map46-native-video-between-flashes.png`已实际查看。
两端底部原Confirm/Back图样初看像被裁白片，随后按源图逐像素核对确认是完整原图。
Android的49/49与61/61个非透明像素中心、全部8行分别由两份独立脚本精确RGB匹配，
报告为`temp/qa-chapter-content/forecast-footer-pixel-audit.md`。
Web所有110个源非透明位置、全部8行也匹配固定四色映射：白/灰保持原RGB，
深蓝由源`(3,44,93)`统一呈为`(16,43,90)`，不能把这项写成Web原RGB完全相等；
记录在Web批次`footer-pixel-position-audit.json`。结合真实Back/Confirm，当前完整图样与操作已通过，
不据此前误判改造UI。图标本身的大小、底边位置与辨识感仍可由用户集中验收反馈。
旧0418包的panel高度错误、hint离屏已有真实证据，该旧包布局未通过的结论仍保留。

Android两次临时驱动失败分别是世界重建后不存在boss的观察假设、以及先读choices误把世界菜单当路线选择；
各次finally完整恢复。保留失败输入与截图，从第二次已真实结算的世界结果只补命名档与50，
没有重新打死亡链。Web旧CUA helper闭包仍比较上一包build变量，改为本批静态闭包后身份一致。
Web m2大视频的JSON传输超过桥接30MB限制，游戏业务已到世界，保留全部截图和结算，
该Web视频文件未取得；所需m2一倍原视频由Android提供。不能将传输失败当作产品失败或声称文件存在。

Web另外保留一次05:17:05.402的`Failed to save IDB file system: No such file or directory`。
实际继续档已落盘m2/route0/step3/8000，命名档冷读成功；原地址35项原记录仍完整恢复。
该错来自Godot的异步IDBFS同步，前14ms恰有被游戏消费后删除的只读请求，符合临时文件枚举/删除竞态，
但现存日志没有缺失path，不能倒推原单次错误的确切文件。
离线记录见Web批次`storage-audit-findings.json`。随后用完全独立的18765 origin调查：
初始数据库清单为空，实际UI进入m0、保存、冷启动1倍后UI32读回完整state相等；
10秒210次只读请求未自然复现。仅在temp的同包index.js副本里增加错误path诊断与确定性调度，
在localset已枚举请求后暂停remote回调，实际Probe自然消费/删除，再继续loadLocalEntry，
确实捕获`playtest_request.json`的errno44/ENOENT。
同路径/同内容在继续读取前恢复为存在的对照没有新错误。
这确认现有debug协议存在同类删除竞态，仍不证明旧05:17单次缺失path就是该请求。
完整结果在`temp/qa-chapter-content/web-sync-isolated-20261102-051003/summary.json`，
协调者安排运行时最小修复和隔离回归，不重复已过死亡链。

原数据只读审计`constructor-byte-audit.json`确认原35项中3个文件真实constructor均为Uint8Array、
byteOffset均0、byteLength为1666/1666/49且全部原始字节一致；其余32项是目录。
带负数的Int8Array仅出现在本次新测试记录，未涉及原备份。
临时codec已抽到`temp/code/javascript/chapter_storage_codec.js`，用ArrayBuffer.isView显式保留
constructor、实际字节、byteOffset/length，并支持旧备份tag；Date与目录mode等元数据不丢失。
只采集view实际字节，不复制整个Godot heap，恢复用offset+byteLength的最小零前缀buffer，
超过64MiB即停止。隔离脚本验证Uint8/Int8/ArrayBuffer/Uint16/DataView和元数据往返，
Chrome中实际新存档的Int8Array往返也逐字节相等；未对用户IDB试写，旧备份未覆写。

本批Android每次新完整备份均恢复原名单、字节与方向后关闭模拟器；Web全35项键、字节、Date/权限等元数据恢复，
正常启动再全等，原文件constructor/偏移/长度额外只读核对也通过。音乐关、1倍、1336×747默认视口已恢复。
8766桥关闭，8765原服务保留。两端入口分别为对应`android-m2-repair-*`与`web-m2-repair-*`目录下的`summary.json`；
本批产品短流程、死亡、地图能力与完整图标复核通过；Web debug协议竞态随后由下一节最终包补验解决，
不静默丢弃console事件。独立18765/18866服务及QA标签已关闭，只保留该origin自造数据供复现。

Androidm1死亡/结算12.949秒、m2一倍链含QA世界菜单终止26.675秒，另从实际结算世界补命名冷读13.374秒，
50预览/点击/施放/冷读18.076秒。Web46含1倍录制及冷读30.591秒、51为19.313秒、m1为13.019秒，
命名世界冷读8.744秒；m2调用26.618秒包含失败的视频传输，不作为纯游戏性能样本。
这些都是定向边界流程，不能与自然整关耗时作严格同比。

## 最终Probe协议补验（2026-11-02）

最终固定包为Web `20261102-060801-3c44967a`、Android `20261102-060809-04b6ba9c`，
导出7.872/13.661秒。本批只补Probe与其测试对应的协议范围，复用0510包已通过的死亡、结算、
完整图标与地图能力证据，没有重打这些业务流程。最终汇总为
`temp/qa-chapter-content/probe-final-summary.json`，本批平台范围通过。

独立18765 origin先用新codec完整备份已有34项自造QA数据，其中两个实际文件为Int8Array。
同样在localset已枚举请求后暂停remote回调，实际Probe已写出本次ID响应，
此时`playtest_request.json`仍存在，恢复同步后error为null、路径诊断为空。
之后新唯一ID覆盖同一请求文件并产生匹配的新响应；没有在原8765做竞态实验。
`web-probe-final-20261102-060801-3c44967a/retained-request-deterministic-proof.json`
保留消费前后及同步结果。

Web隔离页通过实际菜单保存，再冷启动确认1倍、UI临时32倍读取，完整战局和实际IDB继续档字节均相等。
新codec实际保护并恢复该origin初始Int8Array的constructor、offset、length、字节与目录/Date元数据，
先逐项验证全部原记录，再清理新请求等测试项，最终34项全等，见`isolate-restored.json`。
实际保存与冷恢复输入、字节和类型在同目录`actual-menu-save.json`、`real-save-cold-proof.json`。

临时实验显式暂停一次GodotFS.sync期间，两次自动同步碰到现有`Already syncing!`防重入提示；
它们分别对应两次受控暂停，均早于真实保存/冷读流程开始。该流程内没有新的error，
新包受控同步也没有ENOENT；分类记录为`console-classification.json`，不声称整份console为空。
旧05:17单次日志始终没有捕获path，仍保留为未知确切文件；已证明并修复的是另行复现的请求删除竞态，
不能把两者合并成一条已知path的历史事件。

原8765实际加载canvas与HTTP PCK均为最终Web ID，先新完整备份，再仅加载与只读核对，
本批未向其用户记录写测试数据、未执行恢复。35项键、字节和元数据仍全等，
三个原文件均真实Uint8Array，offset0、length1666/1666/49，原始字节一致。
凭证在`web-probe-user-origin-20261102-060801-3c44967a/records-restored-after-reload.json`
与`constructor-byte-audit.json`；这里的文件名沿用既有验证helper，含义是加载后验证，并非本批执行过restore。

Android先force-stop并新完整备份，再安装并核对最终APK/实际进程，
验证请求消费后保留、新ID覆盖请求及匹配响应、实际菜单保存后冷启动1倍/UI32完整state相等。
本批受控初始m2记录沿用已通过Session/Store的0510 fixture；没有用它重做进入关卡或通关声明。
finally恢复全部原JSON名单与字节、方向后关闭模拟器，凭证为
`android-probe-final-20261102-060809-04b6ba9c/result.json`及`records/restored.json`。

Android协议/保存/冷读样本12.033秒；Web同类实际输入与保存冷读9.747秒，包含UI和只读查询，
不与自然整关或含视频传输的旧批次作严格同比。最终8766/18765/18866已关闭，QA标签与AVD已关闭，
8765原服务保留，原用户视口1336×747、音乐与设置未改。当前m0/m1/m2所需实际平台链已收齐，
后续关卡与用户集中验收单独推进。

### m2阶段耗时与检查汇总

通过的Android分项为light17.161秒、世界进入/援军/冷恢复21.018秒、普通战斗/冷恢复15.664秒，
回合限制7.507秒、地图50/46/51各17.494/24.610/17.023秒（包括各自重新启动、UI调速与冷恢复）。
Web对应light16.129秒、世界链21.597秒、非致死普通战斗/冷恢复18.383秒、回合限制8.100秒。
错误镜头假设造成的50.372秒等待另列为失败驱动开销，不混入通过样本，也不与不同旧流程作严格同比。

根协调记录的集成检查为61项工具、170份脚本解析、112项行为及Main smoke，证据在
`temp/qa-chapter-content/integrated-check-result.json`：后段测试适配后分段完成，原失败日志保留，
不能表述为单次`bun run check`全绿。维护时跨内容重建后重取当前Control；图像来源按chapter→battle recipe→catalog profile追踪；
针对某人物的操作使用显式ID，只有排序测试按数组位置断言。

## m3南部平原实际验收（2026-11-02）

[实施票#37](https://github.com/mxp-xc/emblem-rekindled/issues/37)对应固定Web
`20261102-111242-9ed7065b`、Android `20261102-111252-652ddcc7`，
导出9.424/15.940秒；实际PCK/canvas/只读响应与安装APK/进程身份分别一致。
协调者的完整检查为61工具、181解析、121行为与Main smoke通过，两轴审查无未解决项，
见`temp/m3/integrated-check.log`及同目录审查报告；本批没有重跑已过检查或Probe诊断。
实际平台汇总为`temp/qa-chapter-content/m3-platform-summary.json`，所约定范围通过。

| 范围 | 实际输入与结果 |
| --- | --- |
| 两端真实入口 | 复用实际m2命名世界档route0/step3、队伍0/9/6/7，经当前Session/Store复核；取消前往保持继续字节，再真实前往m3，完整开场与指挥官3，39条部署、初始19可见。前序m2战斗数值为明确受控，未称自然培养。 |
| 第2轮 | 当前合法phase0/round2受控快照，保留三组14名敌军及原格、6个slot和选择器；仅隐藏无关初始AI、限制boss无关行动。真实结束回合完成三组原地显现、511、北入、512/513；实际位置与一次性标记保持，菜单保存/cold1→UI32完整state及字节相等，不重播。 |
| 新独立战斗 | 两端均真实攻击107/class32，看到红色魔物独立场景及反击，HP/耐久/行动结束正确，再菜单保存冷恢复；Web另补63/class24的实际独立场景。新演出关键帧临时用UI4倍，其余bulk UI32。 |
| 两端515/516 | 514首战后，515期间HP0的83本体仍在、镜头聚焦83；退场后516聚焦当前0的位置，原83格已空；随后奖励。权威snapshot已hidden不等同显示副本，不以其否定对白画面。 |
| Android固定结算 | 明确先清除其他可见敌人，再由普通战斗击杀最后83；不是bossHP1单独判胜。保持route0、step4、8000→9000金；命名世界档cold读取不重奖、不改继续档。 |
| Web初次分支 | 只从真实m0代表choice2的合法route2/step1世界进入m3；517后实际选择鲁卡/next2，得到route3/step2、6000→7000金。named cold保持结果且继续字节不变。未伪造m0/route3世界档；next4→route2另由headless覆盖。 |
| 布局与返回 | 默认推荐竖屏；Android等待系统RotationLayer/animator退出后，实际查看完整水平横屏地图/HUD及一次菜单系统Back，之后恢复竖屏与原方向。 |

Android的1倍原视频为
`android-m3-20261102-111252-652ddcc7/m3-controlled-round2-reveal-north-entry-1x.mp4`，
位于`temp/qa-chapter-content/`，长11.020秒；同目录`m3-reveal-video-3.40s.png`、
`4.50s.png`、`5.90s.png`、`8.00s.png`（后三者同`m3-reveal-video-`前缀）是保留的原视频提取帧，已实际查看。
511与512实际画面分别为`m3-round2-dialogue-01.png`、`02.png`；完整逐帧mask计数0→4→7→14、
同步无Tween及纯显示/RNG不变由运行时真实Main检查补足，不从Probe的已提交可见状态推断中间显示mask。
两端515/516关键图分别是Android的`m3-fixed-death-dialogue-02.png`、`03.png`和
Web的`m3-branch-death-dialogue-2.png`、`3.png`，均已实际看图确认body、空格与不同焦点。

Web第一批已经过合法step1入口及515/516，到真实517选项后，临时manifest却从fixed内容投影取得
“黑暗森林”作为按钮文案，导致QA点击停止；实际UI正确给出鲁卡/莎尼亚。
该失败、截图与完整恢复凭证保留。后续先新完整备份，只从实际失败快照构造受控尾段：
保留已发生boss事件、库存和XP，仅将非boss63复活为HP1、重置人物3行动并清outcome，
经Session/Store JSON及实际`attack_options=[63]`验证，真实清除最后敌人后再选择当前控件name对应的next2。
没有重演已通过开场或死亡，也没有把受控重构称为连续自然战。
尾段来源及往返证明在`m3-choice-tail-20261102/`，通过结果在Web批次的`attempt-2/tail-result.json`。
后续关卡应从当前分支投影和实际控件取得选择语义，不能复用fixed投影的label。

7项首批fixtures在`m3-fixtures-20261102-integrated/`，由当前统一入口及公开domain waits/end_phase生成，
没有使用非法phase2存档；恢复不重抽初始化随机。生成期的两个QA假设已修正：
编译后turnEvent.unitIds含14敌人及6个解析后的slot，不能把总长度当14；maxHp须遵守当前上限60。
没有因此修改生产保存校验。通用Web临时driver按每批buildId创建新闭包，并按CSS viewport换算Retina坐标，
不再复用闭合旧build的helper；Android沿用同一受保护runner与m3用例配置。

Android一次新完整备份后安装，finally逐字节恢复全部原JSON和方向，模拟器关闭。
Web两个子批各有独立新完整35项备份，finally先恢复并验证全部原键、实际view类型/offset/length、字节、Date/mode，
再删除新增项，正常启动后再次全等；音乐/原设置字节恢复、视口覆盖清除为1336×747。
原地址保留新Web ID，8766等临时服务关闭，8765保留。两端`summary.json`列出输入、证据与恢复凭证。
六上下文、失败优先、隐藏未来援军不阻止早胜和另一条初次分支由headless矩阵承担，未称自然重打整章。

Android分项为真实入口10.829秒、横屏/Back2.159秒、1倍事件及冷恢复27.789秒、
怪物独立战斗及冷恢复18.711秒、固定结算及命名冷读17.186秒。
Web入口12.854秒、事件及冷恢复16.177秒、怪物及冷恢复20.529秒、额外class24场景11.196秒，
受控选择尾段含命名cold21.499秒；失败尝试单列，不能混入通过样本。
这些是不同业务边界的绝对样本，不与自然整关或不同地图作严格速度同比；用户集中验收单独记录。

## m4实际验收通过

[黑暗森林#38](https://github.com/mxp-xc/emblem-rekindled/issues/38)本轮最小两端矩阵已通过。
实际包为Web `20261102-124746-8343333d`、Android `20261102-124756-078183e1`，
均核对实际canvas/进程内部buildId，Android另核对已安装APK，Web另核对原8765的PCK。
汇总及全部入口为`temp/qa-chapter-content/m4-platform-summary.json`，可用
`uv run python temp/code/python/m4_platform_summarize.py`离线复核业务状态与恢复凭证。

| 平台 | 实际输入与结果 | 可复核证据（相对temp/qa-chapter-content） |
| --- | --- | --- |
| 两端 | 实际m3 route0/step4世界档，取消不改继续档字节，再前往m4；开场/指挥官8、36部署。 | 各平台m4批次的`m4-actual-world-entry.png/json`。 |
| 两端 | 真实结束回合使105从class36/gen1/source109换为class28/gen4/source112，地图/石人信息页一致；旧opaque物品仍在warehouse，菜单保存后cold1→UI32恢复完整snapshot/物品/波次，不重播。 | Android `battle_wave3-current105-information.png`、`battle_reuse4-current105-information.png`和`battle_reuse4-once-cold-equal.json`；Web `m4-reuse-current-class28-information.png`和cold-equal。 |
| Android | 七个旧槽从隐活状态实际入场，新8原本可见；1倍首波逐人显现；8对新105石人真实独立战斗，HP60→41、45耐久18→17、行动2。 | `battle_round2-dialogue-01.png`、before/after完整状态；`battle_wave3-actual-1x.mp4`（6.524秒），已看1.8/2.6/4.2/5.0秒帧；`m4-recycled-class28-independent.png`。 |
| Android | 合法round10边界只发一次结束回合，进入11即时生存胜利，route0/step5、9000→10000金；命名世界档冷读不重复奖励。 | `battle_round10-after.png/json`、`m4-named-world-slot.json`、`m4-named-world-cold-no-repeat-reward.png/json`。 |
| Web | 敌80实际AI使用原风50，地图浅青风圈清晰，无独立战斗/普通首战死亡标记，整次扣耐久1并冷恢复；普通8原45攻击持50的80，实际class13防守，526→527旧格body仍在→退场→528雅木/旧格已空，清场仍未提前胜，冷读保留。 | `m4-boss50-tactical-effect-candidate.png`及cost/cold；`attempt-2/m4-boss50-class13-independent-defense.png`、`m4-boss-ordinary-dialogue-2.png`、`-3.png`和retired/cold。 |

前置复用实际UI保存/冷读的m3世界档；之后的quiet HP/显隐、站位、波次和旧物品转仓库均明确受控，
不称自然完整10轮通关或自然G掉落。1倍视频是模板原格的零距离逐人显现，没有邻格移动，
不把它当邻格移动证据；四邻阻塞、池满、当前模板继承、全波次、六上下文和失败优先由headless矩阵覆盖。
本轮复用既有横屏公共证据，没有重复旋转矩阵。缩放只从设置调整，滚轮只平移。

有效fixtures为`m4-fixtures-20261102-integrated-v2`，生成器直接复用运行时helper与实际phase命令，
Session/Store JSON往返、零初始化RNG、boss AI/普通死亡oracle实际exit0，22.455秒。
首次v1的quiet helper让所有我方可见，导致round2 arrivals为空；旧批次保留而不用作进场证明。
v2只在round2按content.slots恢复七槽隐活，再断言7个唯一arrivals、from/to、存活显现及once标记。
Web早期REPL工厂少了phase计时方法，发生在fixture写入前；仅补计时，没有重复已过链。
计时输出对象曾被空timings覆盖，实际内存计时另存`actual-case-timings.json`，原结果保留。

Android六分项为11.363/15.426/18.768/18.571/19.134/20.075秒，共103.337秒；
Web入口/换代/风/普通boss为12.204/16.253/21.042/22.413秒，共71.912秒。
这些包含各case的冷启、UI调速、输入、截图和对应存读，未单独计启动模拟器、安装、完整保护和离线看图。
正常每次启动1倍，bulk用UI32，克隆演出1倍、独立战斗/风取UI4；没有同场景旧m4基线，不宣称加速比。

Android原2个JSON及方向逐字节恢复，`records/restored.json`与result确认，模拟器已关闭。
Web两次fresh完整备份各35项，均先恢复验证全部原项的type/offset/length/字节/Date/mode再清新增；
第二批正常启动新canvas后再次只读核对35项不变，见`attempt-2/normal-startup-proof.json`。
两批console均为空。原音乐/设置保留，未改视口；8766已关闭，8765保留最新包，原游戏标签正常打开。
本轮平台剩余项为无；集中用户体验验收仍与检查通过分开记录。



## m5皇都近郊实际验收（2026-11-02）

[皇都近郊#39](https://github.com/mxp-xc/emblem-rekindled/issues/39)最小两端矩阵已通过，剩余项为无。
固定实际包：Web `20261102-135912-92b4dc0c`，Android `20261102-135922-62c3fa89`；
核对原8765 PCK/实际canvas/内部buildId及已安装APK。结果入口
`temp/qa-chapter-content/m5-platform-summary.json`，离线复核命令
`uv run python temp/code/python/m5_platform_summarize.py`。

| 平台 | 已通过的实际输入与业务结果 |
| --- | --- |
| 两端 | 合法世界取消不改继续档字节，再前往m5/开场/指挥官2/36单位；分别查看现代46/class8刀斧手和70/class24信徒的资料/地图/装备，两者sourceId均46且身份独立。原版fallback头像可相同，不要求图片不同。 |
| Android | m0合法代表route4/worldStep1进入；round1六槽从右侧入场、534..537；round3原64..69依次显现后538，1倍原视频16.589秒，已实际看2/4/6/8/10/12/14/15.5秒关键帧；菜单保存cold1→UI32，完整事件状态不重播。 |
| 两端分工 | Android对46/class8、Web对70/class24各一次真实独立战斗。两次实际均命中，目标HP60→59、原武器24耐久16→15、行动2；保存冷读后两身份/物品及完整state相同。驱动仍允许miss并按实际HP/耐久联动核验。 |
| Android | boss84死亡时46/70仍活，539/真实class25战斗/540 body-before/退场，真实点击Choice_5即next4，结算route5/worldStep2/gold7000。实际结算world经Session/Store复核后补命名cold，未重播死亡/choice，无重复奖励。 |
| Web | 从m4 route2/mapStep2结算后的worldStep3进入；boss旁敌存活仍胜，固定route2/worldStep4/gold9000，命名档冷启1→UI32恢复同一世界，继续档字节不改。 |

Android证据目录为`temp/qa-chapter-content/android-m5-20261102-135922-62c3fa89`：
`m5-modern46-source46-class8-information.png`、`m5-modern70-source46-class24-information.png`、
`m5-modern46-independent.png`、`m5-actual-next4-choice.png`、`m5-branch-boss-dialogue-02.png/json`，
以及`battle_round3-native-queue-1x.mp4`和对应`m5-native-queue-video-*.png`。
Web目录为`temp/qa-chapter-content/web-m5-20261102-135912-92b4dc0c/attempt-2`：
`m5-modern70-class24-independent.png`、`m5-fixed-boss-dialogue-2.png`、
`m5-fixed-world-settled.png`、`m5-fixed-named-world-cold-once.png`。以上关键像素均已实际查看。

有效8项fixtures为`m5-fixtures-20261102-integrated-v2`，真Matrix/Flow→Session/Store/JSON/零初始化RNG，
21.469秒；前置均按真实阶段辅助结算，不是自然重打前关。quiet HP/显隐/move和战斗站位明确受控。
六上下文、blocked/邻格/显示mask、required失败优先、另一分支留headless；不重复旧关/Probe/codec/横屏矩阵。
本批六项真实from/to均相同，视频证明逐人聚焦和原格显现，不声称证明邻格移动。
终局battle按合同拒绝encode，存读只用结算世界；旁敌存活证据取540时完整战局，世界party裁剪后不再查敌ID。

保留两类QA失败：Android已点击分叉并生成正确world，但世界叙文尚未ready时仍查84导致StopIteration，
只补经校验的实际world尾段；Web两单击未打开第二资料菜单导致超时，完整恢复后只补未完成duel/boss。
70重试沿旧REPL闭包仍用了两单击并成功；新原生clickCount2另在固定boss菜单实际验证并留原始输入，
不把70成功误归因于新双击。共用harness已改为一次原生双击；JSON数字逐项int和双击经验集中记在
`docs/agents/verification.md`，产品规则/阈值未改。

Android入口10.479秒、六槽13.002、队列/冷读32.969、普通/冷读21.430，
boss至choice的原分项13.519秒（含末尾QA异常），实际world/命名尾段17.912，共109.311秒证据链。
Web通过入口14.282、普通/冷读26.495、boss/命名24.226，共65.003秒；早期失败输入40.716秒另列。
计时包括case冷启/UI调速/输入/截图/相应存读，不含单独未测的模拟器启动、安装、完整备份恢复和离线复核，
无同场景旧版基线，不宣称加速比。bulk UI32、代表队列1倍、取独立动作UI4，每次冷启动核1倍。

Android两批fresh原2个JSON/方向均完整恢复并关AVD；Web两批各35项type/offset/length/字节/Date/mode
先恢复核对全部原项再清新增，最后正常启动新canvas后35项仍不变，console均为空。
证明为各批`records/restored.json`或`restored.json`及Web `attempt-2/normal-startup-proof.json`。
原音乐/设置/方向保留，未改视口；8766已关，8765保留最新包，原游戏标签正常打开。

## m6补给站实际验收（2026-11-02）

[#41](https://github.com/mxp-xc/emblem-rekindled/issues/41)两端最小矩阵已通过，剩余项为无；
Web `20261102-152112-6270c200`、Android `20261102-152136-560b7b17`，实际canvas/进程/APK核对，原8765 PCK由协调者验证。
汇总`temp/qa-chapter-content/m6-platform-summary.json`，以下所有fixture均明确受控，不称自然整关。

- 两端真实世界取消不改继续档，再进入m6/cmd4/46单位、普通85独立战斗、菜单保存cold1→UI32，完整状态相同。
  Web直接复用实际m5 route2/worldStep4/gold9000命名档；Android由合法M5 next6辅助结算生成route4/worldStep2入口，Session/Store/JSON零初始化RNG已过（9.251秒）。
- Android七旧槽从南侧+3入场，新4不计入旧槽；原1倍视频8.458秒已看3.3/3.4/3.5秒帧，从屏底部分出现至七人向北到达。
  两focus精确22/10tick复用已过Main1倍证据；本批世界和开场UI32，只以南入作平台1倍代表。
- 回复之戒81底层耐久0仍生效：敌阶段末HP8，新轮HP15（max60，增7在6..12内），无额外治疗表现，戒指未耗，保存冷读不重抽。
  Web实际点右箭头的库存页清晰显示勇者枪28、铁盾4、回复之戒“-”（底层0）、原G补入的钢铁纹章1。
  Android误命名库存截图仍是战斗数据页，不计库存可见性；没有为此重收Android。
- 普通546/547、boss85退场后33仍活且不胜；独立的受控最后敌33清场才胜。Android覆盖548/488，实际route4/worldStep3/gold8000，
  Web覆盖548/549、route2/worldStep5/gold10000；两端命名world cold奖励不重复。
  敌ID只在完整战局阶段读取，世界进度出现/party裁剪后停止敌查找。

Android有效批次`temp/qa-chapter-content/android-m6-20261102-152136-560b7b17/attempt-2`：
`m6-ordinary-independent.png`、`m6-ring81-new-round-result.json`、`m6-ring81-trace.json`、
`m6-boss-retired-other-enemy-no-victory.png`、`m6-seven-slots-south-1x.mp4`及`m6-south-video-3.3s/3.5s.png`。
实际m7前置保留在该批`m6-named-world-slot.json`，没有留在用户原记录中。
Web批次`temp/qa-chapter-content/web-m6-20261102-152112-6270c200`的
`m6-boss85-ring81-zero-inventory.png`为实际库存可见证据；`m6-fixed-ordinary-and-ring-held-cold-equal`及
`m6-fixed-named-world-cold-once`保存完整state/字节恢复证据。

Android五case为15.394/17.860/24.846/11.433/19.351秒，共88.884秒；Web13.390/25.157/22.294，共60.841秒。
首批旧世界1倍展开在45秒等待尾端超时，紧接抓图worldReady已true，未进m6；该失败51.992秒保留，不算通过或提速基线。
之后只补未进入的链。计时包含各case启动/UI调速/输入/截图/相应存冷读，安装、完整保护和离线复核未单独计时，不报加速比。
Android两批原2JSON及方向均完整恢复、AVD关；Web35项type/offset/length/字节/Date/mode先恢复原项再清新增，
正常启动新canvas后35项不变、console为空。证明在各批`records/restored.json`或`restored.json`及Web `normal-startup-proof.json`。
原音乐/设置/视口复原，8766已关，8765保留最新包；六上下文、戒指逆序/RNG/边界与旧关全量回归留既有headless矩阵。

## 阶段门槛

| 阶段 | 必须取得的结果 |
| --- | --- |
| #36首次落地 | 最终章级库和关卡配置已被实际运行时消费；m0/m1及旧记录回归；m2六条可达路线的配置集成；配置新增fixture完成进入、事件、结算及存读；相关完整检查和两轴审查；m0/m1实际Android/Web包回归。 |
| #35完整m2 | 在上述基础上，两端实际输入通过世界进入、地图操作、独立战斗、战斗存读/冷启动、胜败与结算返回世界；部署和事件差异覆盖六个上下文。 |
| 后续m3～m7 | 逐关关联实施票，验证每关配置及新增差异；复用已稳定的公共规则测试，不把库导入或stub通过计为地图完成。每关取得实际包短流程证据后更新章进度。 |

完整检查、模块定向检查、实际平台输入分别记载。headless通过不能代替实际平台流程；
读到buildId不能证明操作正确；受控HP、站位、回合边界不能称为自然整关通关。

## 配置集成矩阵

m2六个上下文共用一份关卡定义。`step`是进入本关前路线前缀长度，已有成员按招募顺序进入槽位，
本关新加入人物7不占已有成员槽位。party数组重新排列不应改变绑定。

| route | step | 已有正式队伍槽位顺序 | 空槽临时身份 |
| --- | --- | --- | --- |
| 0 | 2 | 0、9、6 | 95～98 |
| 3 | 2 | 0、9、3 | 95～98 |
| 4 | 7 | 0、9、2、4、5、1、6 | 无 |
| 5 | 4 | 0、9、2、8、3 | 95～96 |
| 6 | 4 | 0、9、5、1、6 | 95～96 |
| 7 | 7 | 0、9、5、4、2、8、3 | 无 |

这一矩阵验证实际章配置与库，检查部署身份、当前职业、图片/武器/动作绑定、继承数值与物品，
不能仅向纯binder传入假profile。随机部署另覆盖包边矩形、重叠去重、已占格、空候选跳过；
保存恢复保持既有结果，恢复过程不重抽初始化随机。移动后的坐标按当前地图校验。

所有关卡都验证错误先于场景采用和存档写入：缺profile、缺clip、重复身份、非法路线/槽位、
不适用的记录均不能部分替换当前场景或覆盖继续档。m0/m1旧记录是独立回归输入。

| 关卡 | 本关定向差异 | 原版依据与边界 |
| --- | --- | --- |
| m2 | 38条部署、7槽、3条随机部署；第1/3/11轮入场，第9轮策略变化不显现隐藏单位；boss82首战/死亡对白；胜利优先、路线保持、战序对白与1000金一次结算。 | `temp/m2/original-deployment/`、`temp/m2/original-events/`；六条路线原初始化及受控事件，不是自然整关。 |
| m3 | 39条部署、6槽；IDs107～110为既有敌军；第2轮分组显现/入场；先判必保人物失败，再判非隐藏敌军全灭；step1选择节点2/4，后续不重复选择。 | `temp/m3-m7/deployments/summary.json`、`events/summary.json`；特殊AI字节码条件不可达，不能补成第10轮追击。 |
| m4 | 36条部署、7槽、9条随机部署及重叠多矩形；坚持到bo>10，杀boss不提前胜；第2轮我方入场；3/4/5周期优先克隆、105～127池满/复用、不同出生代物品身份与存读。 | 同上；第10/11轮、同时死亡失败、重复克隆与池满已有受控原版证据。 |
| m5 | 36条部署、6槽、6条随机部署；第1/3轮事件；boss84胜利；step1选择节点4/6；必保人物失败优先。 | 同上；特殊AI不可达，不能补成第12轮追击。 |
| m6 | 46条部署、7槽；开场双焦点、第2轮入场；非隐藏敌军全灭；战序2与其他战序胜后对白不同；保持路线。 | 原版部署六上下文已运行；事件探针存在残留瞬态，原版胜败运行边界标记`reliable=false`。采用已定位静态分支和公共契约，不能写成已自然复现原版完整流程。 |
| m7 | 42条部署、6槽、4条随机部署；第2/4轮事件；非隐藏敌军全灭；step1选择节点6/8；必保人物失败优先。 | 同上；受控事件/胜败与静态首战/死亡对白分开记录。 |

## 实际包短流程

每次运行使用一个已冻结的集成版本，负责人统一安排设备和原地址。
Android与Web实际buildId分别记录，不要求两个平台buildId相同。
每个关卡至少在两端各完成以下同一业务链；路线组合、周期/边界细项由配置集成和定向规则测试补足，
需要显示差异的早期/后期队伍另取平台样本。

| 检查点 | 真实输入与结果 | 证据 |
| --- | --- | --- |
| 启动与入口 | 冷启动为1倍；通过游戏设置临时选32倍；从合法前置世界进度选择目标节点；先取消确认，再确认前往。 | 实际buildId、原继续档取消前后字节、世界/关卡ID、开场截图。 |
| 开场与部署 | 推进实际叙事、目标和指挥官设置；人物和新队员正确，隐藏援军不提前出现。 | 输入顺序、ready快照、竖屏截图；可选横屏定向截图。 |
| 移动与独立战斗 | 真实选人、移动、选择合法装备、确认目标；看到独立战斗，再返回地图。 | 开战截图/状态、地图回归、行动已结束、HP与耐久实际结果；出现临时或新怪物职业时复核对应表现。 |
| 存档与冷恢复 | 行动间隙通过菜单保存；force-stop/刷新；先核对1倍，再重新调速并读取进度。 | 保存字节、冷恢复战局相等、实际地图/队伍/事件标记，未重复入场或奖励。 |
| 回合与胜败 | 通过结束回合推进本关关键事件；使用明确标记的受控胜败边界检查正常对白与结算。 | 回合、显隐/策略/克隆出生代、一次性标记、分支选择与失败结果。 |
| 世界返回 | 完成正常胜利剧情与必要路线选择；核对驻留地点、route/step、正式队伍、仓库、物品耐久与资金；命名世界档保存/重开/读取。 | world快照、世界/商店截图、命名档与继续档隔离；重读不重复1000金。 |
| 返回与布局 | Android真实Back、Web Esc逐层返回，取消不提交；地图/对白/菜单/HUD不越出地图区域。 | 返回前后状态及关键截图。 |

用于压缩前置时间的world/battle fixture必须由同一最终内容和统一打开接口在隔离环境生成，
保持合法路线、招募前缀与物品身份。调整过的HP、站位或回合单列为受控边界。
不以直接写入新关战斗档代替世界确认进入，也不以辅助直接通关代替至少一次实际独立战斗。

## 记录保护与可复用入口

Android复用`tools/android_playtest.py`的只读相关请求、`AndroidInput`真实输入与UI调速，
使用`tools/qa_records.py`建立每批新完整备份。启动测试前force-stop，枚举与读取失败立即停止。
在`finally`中force-stop，恢复并逐字节验证全部原文件后再清理新增JSON；恢复失败保留备份，
不写成功结果。轮转设置若被修改需单独备份、恢复与核对。每批安装当前APK并验证已安装身份。

Web固定原地址`http://127.0.0.1:8765/`，完整备份该源IndexedDB的键、字节与元数据，
停止游戏写入后再恢复；恢复后启动并复核，不能通过清站点数据规避缓存问题。
视口覆盖、音乐及其他临时设置在批次结束恢复。平台负责人复用当前可用Computer Use入口，
历史浏览器tab/session句柄不可假定有效。

Web现有只读探针可以复用Engine公开的`copyToFS(path, buffer)`：将仅含唯一`requestId`的JSON写入
当前游戏userfs下的`playtest_request.json`，随后读取IndexedDB的`playtest_state.json`，
只接受`requestId`一致且`ok=true`的响应，并核对其buildId。原游戏仍通过真实键盘、点击操作，
探针不发游戏命令、不代替保存，也不修改速率。该路径已在本批实际候选中验证；
helper保留在Web批次的`input-harness.json`，使用时先读取当前浏览器文档并绑定有效tab。
不能读取`engine.rtenv.FS`或试探未导出的FS getter：当前Emscripten构建会直接abort页面。
本批原始console错误、重载后的真实输入和35项记录恢复凭证均保留；该已确认陷阱属于QA探针使用错误，
不能当作游戏本身的报错。

已有`tools/playtest_first_battle.py`适用于m0自然回归；其规划器不是m2～m7通用规划器。
`temp/code/python/m1_android.py`与`m1_android_flow.py`包含已移除的旧`client.enable`调速入口，
只作为历史输入与证据参考，不能原样复跑。新批次调用`AndroidInput.set_speed(32)`，每次重启核对1倍。
不需要为本轮新增生产写入调试接口。

真实驱动按实际战斗结果检查耐久：原规则中未命中的攻击不扣武器次数，不能固定断言每次攻击都减少1。
保存后先等待本次持久记录达到目标战局，再冷停；输入已发送或地图ready不代表保存操作已经消费并落盘。
以目标记录中的行动编号、坐标、HP/库存等业务状态确认，不以固定sleep替代。

Android旋转时，游戏viewport已横向或ready只表示应用侧完成布局，不能证明系统compositor旋转动画结束。
最终横屏截图须等待系统旋转动画退出，再实际看图确认地图与HUD水平、四角无倾斜截断；
旋转中间帧只保留作过程证据，不能作为横屏布局通过图。

## 耗时与结果记录

批次证据保留在`temp/qa-chapter-content/`，按集成版本和平台分目录。
记录导出、安装、启动及调速、入口演出、移动/战斗、保存、冷启动恢复、结算、记录恢复的独立耗时，
总时间与ADB查询/输入次数一起报告。已有软件渲染无窗口模式固定流程11.9～12.6秒是旧m1样本，
不能当作本轮新流程结果或把不同操作数的整关样本作严格同比。

采用已知输入批量发送和业务状态处检查，截图放在关键布局、结果与失败处；避免每次输入都重新截图。
合法配置矩阵集中headless验证，实际平台覆盖新内容链与可见差异，减少反复自然打前置关卡。
所有阶段的最终结果记录实际命令、buildId、改动范围、审查/修复、证据路径、未测项及原记录恢复凭证，
再由协调者更新对应实施票、章级计数与整体索引。用户集中验收保持单独状态。
