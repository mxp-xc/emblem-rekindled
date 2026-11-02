# 首关验收

本页记录的验收批次范围是初章第一战及其开场、结算、驻留世界、四档存读与物品整理。
后续关卡的当前进展由章级票维护，入口见[决策地图](https://github.com/mxp-xc/emblem-rekindled/issues/1)逐关推进。

首关开发及本轮自测已完成，可集中验收。[第二轮12项反馈](https://github.com/mxp-xc/emblem-rekindled/issues/21)、[内部API与快速回归](https://github.com/mxp-xc/emblem-rekindled/issues/22)、[敌军掉落名称高亮](https://github.com/mxp-xc/emblem-rekindled/issues/23)均已完成对应验证。新增[滚轮导航与通关辅助](https://github.com/mxp-xc/emblem-rekindled/issues/24)已补齐相关自动与两端验证。

[架构改进与滚轮频率修复](https://github.com/mxp-xc/emblem-rekindled/issues/26)已完成自动与两端定向验证：132份脚本解析、86项游戏行为测试及15项工具测试通过，两个独立审查轴均无未解决发现。菜单连续滚轮合并与限速、人物资料焦点恢复及世界失焦手势取消已覆盖；本轮没有重跑自然整关。两端原JSON均已逐字节恢复，Android模拟器已关闭。

## 验收条件

- Android 使用既有 `Emblem_API_36`，Android 16 / API 36 / ARM64，540×960。
  用户已确认本轮保证模拟器即可，真机暂不作为完成条件。
- 电脑 Web 使用 Chrome；手机浏览器和 iPhone 未纳入本轮实测。
- 原 JAR 是正常行为的对照来源。已批准修正圣武器自疗耗尽后的幽灵装备异常：
  按实际库存重新装备，没有武器便不能攻击或反击，不错误扣药草次数。
- 模拟器的音频输出信号不等于实体手机扬声器听感；长屏布局检查不等于实体设备实测。

这些裁决见[当前验收范围](https://github.com/mxp-xc/emblem-rekindled/issues/3#issuecomment-6541114668)
和[耗尽自疗规则](https://github.com/mxp-xc/emblem-rekindled/issues/17#issuecomment-6541109250)。

## 逐项证据

| 要求 | 验证入口与当前结果 |
| --- | --- |
| 原地图、正式队伍与初始配置 | `test_new_battle.gd`、`test_content.gd`；导入器从本地来源生成内容，导出包只读取随包数据与素材。 |
| 新游戏、世界入场、对白、配置、教学、部队显隐与等待 | `test_entry_ui.gd`、`test_story_timing.gd`、`test_opening_visibility.gd`、`test_world_intro.gd`；最新版两端实际新游戏开场通过，动画完成后才推进对白。 |
| 单屏选人、移动、寻路、拖动、缩放、取消与人物资料 | `test_movement*.gd`、`test_battlefield_ui.gd`、`test_map_input.gd`、`test_unit_information_ui.gd`、`test_back_navigation.gd`；两端真实输入与系统 Back / Esc 分层验证通过。 |
| 滚轮平移、菜单选项、人物属性翻页及行动优先项 | `test_battlefield_ui.gd`、`test_menu_wheel.gd`、`test_unit_menu_ui.gd`；Web真实滚轮确认地图仅垂直平移，菜单不穿透，资料页前后切换，设置嵌套控件可连续导航；行动默认优先可执行交互。 |
| 连续滚轮频率、输入归属与世界失焦取消 | `test_wheel_pacing.gd`、`test_navigation_ownership.gd`、`test_world_focus.gd`；Web原地址实际8次微小滚动仅切一项/一页，详情不翻、地图连续；受控漏release回归通过，未声称OS实际丢事件已复现。 |
| 设置辅助与确认式直接通关 | `test_assisted_victory.gd`、`test_assistance_ui.gd`；Web/APK真实确认/取消和Esc/系统Back逐层返回通过，路线0/6000金币，原队伍持有物品不变；正常胜利剧情与世界保存复用，不额外发击杀掉落。 |
| 攻击公式、反击、命中、未中、必杀、成长与耐久 | `test_combat_forecast.gd`、`test_combat_round.gd`、`test_rewards.gd`、`test_combat_rewards.gd`、`test_experience_limits.gd`；独立原来源样本覆盖公式与关键分支。耗尽异常另由本页明确的批准差异处理。 |
| 物品、装备、丢弃、治疗、交换与行动限制 | `test_item_operations.gd`、`test_equipment.gd`、`test_staff_ui.gd`、`test_exchange_ui.gd`、`test_trade_commit.gd`；真实 APK / Web 操作、当前次数与默认详情耐久均已核对。 |
| 敌军掉落名称高亮 | `test_drop_highlight.gd`覆盖32单位、三个正常绿色名、同模板重复、零耐久、不可装备、阵营/标记变化与移除；两端三名敌军、选中详情和Web宽屏实际通过。仅名称为原#00DD00，图标和耐久不变，转移后按拥有者重算。 |
| 自疗耗尽后的装备、跨回合、主动攻击、敌方反击与存读档 | `test_expired_self_heal.gd`单独通过；空装备不反击，药草3次不变，跳过不适配的杖选择铁剑，存档拒绝悬空引用。该裁决阶段完整检查与两轴审查通过；第二轮反馈修复另验。 |
| 敌军与友军策略、有限回合推进、首轮援军 | `test_ai.gd`对照17组原队列/接近/攻击/防御/跟随/治疗样本；`test_turns.gd`、`test_turn_ui.gd`、`test_automatic_presentation.gd`覆盖权威行动与范围/路线/目标演出。APK / Web 已实际回到第2回合并保存。 |
| 独立战斗、HP变化、朝向/叠层、反击衔接、死亡及地图返回 | `test_battle_clips.gd`、`test_battle_hp.gd`、`test_battle_animation.gd`、`test_battle_ui.gd`；原动作与时钟样本、实际两端攻击、APK 战斗后台恢复均已验证。 |
| 破损、掉落、经验、首次教学、升级/成长顺序 | `test_action_feedback.gd`、`test_reward_sequence.gd`、`test_reward_timeline.gd`、`test_healing_timeline.gd`；两端实际治疗和首次教学通过，教学替代 HUD。 |
| 全灭与南撤两条胜利；胜败冲突优先级 | `test_outcomes.gd`、`test_ending_ui.gd`；南撤须结束行动，全灭优先于同时失败。两端已有实际全灭通关；本轮正常速APK从新游戏43次操作/9回合全灭通过，路线0/6000金币，未改HP/位置/RNG。额外32倍API驱动33次操作/6回合检查点完成通关，倍速不代替正常节奏验收。 |
| 雅木死亡、赛丽卡死亡、失败后读旧档 | `test_ending_ui.gd`；APK 实际敌方攻击、失败返回标题、精确读取原稳定档两例通过。HP与站位为受控边界，不称自然整关。 |
| 胜利对白、四条路线、结算与奖励只发一次 | `test_story_choices.gd`、`test_completion.gd`、`test_ending_ui.gd`、`test_progress_ui.gd`；路线0/2/4/6均保存，重读不重复奖励；两端实际结算进入驻留世界通过。 |
| 行动间隙、临时继续、四命名档与失败保护 | `test_battle_record.gd`、`test_save_slots.gd`、`test_slot_errors_ui.gd`、`test_world_slots_ui.gd`；两端保存/覆盖取消/读取/关闭重开通过，剧情与未确认移动不能保存。随机源不入档，读档允许重新尝试后续随机结果。 |
| 驻留世界、仓库存取、非邻接交换、原商品买卖与测试金币 | `test_world_inventory*.gd`、`test_world_shop.gd`、`test_world_gold.gd`；两端实际整理→存档→重开恢复通过，取消和写入失败不部分改动，不自动覆盖命名档。 |
| 地图内对白、菜单、资料与 HUD；宽屏、长屏和安全区 | `test_dialogue_layout.gd`、`test_desktop_layout.gd`、`test_map_hud_ui.gd`；540×960、1280×720、2048×1152、1080×2400、1440×3200布局回归通过，两端实际画面复核限定在中央游戏区域。 |
| 音乐循环、切项/指针不重播、后台恢复 | `test_music_continuity.gd`、`test_title_music.gd`；Web 实际110秒、跨两循环与 PCM 信号通过，无长 Sample 重复分配；模拟器 AudioTrack 未静音且帧计数前进。 |
| Android 前后台与战斗恢复不重复结算 | APK 实际 Home→恢复 PID 不变，稳定战局状态不变；战斗中切后台后返回，行动编号只增加一次，可继续保存。 |
| 格式、lint、脚本解析、全部行为测试及审查 | 当前132份脚本解析、86项行为测试、15项工具测试及lint/格式/启动检查通过；Standards/Spec与后续修正复审零未解决发现。 |

自动测试文件均位于 `game/tests/`，执行方式见[开发说明](../development.md)。
受控位置、HP、随机源或时钟仅用于对应验证，不属于正式游戏运行路径。

## 运行证据入口

- [首关整局与开场记录](https://github.com/mxp-xc/emblem-rekindled/issues/16#issuecomment-6536767686)：
  从新游戏开始的 APK 全灭通关、Web 失败后读取实际旧档并通关；二者流程与次数分别记录。
- [音乐、演出与界面反馈修复](https://github.com/mxp-xc/emblem-rekindled/issues/20#issuecomment-6539216167)：
  最新版两端开场、范围、资料、教学、敌军行动与真实记录续玩结局，以及音频信号。
- [四档存读与驻留世界](https://github.com/mxp-xc/emblem-rekindled/issues/18#issuecomment-6538080055)。
- [12项界面修复及正常速首关整局](https://github.com/mxp-xc/emblem-rekindled/issues/21#issuecomment-6542360630)：本地ff25421，正常速43次行动/9回合全灭，实际两端新界面与恢复证据齐备。
- [世界物品整理闭环](https://github.com/mxp-xc/emblem-rekindled/issues/19#issuecomment-6541052401)：
  两端最终5600金币、4件唯一物品，命名档与冷启动恢复一致。

快速回归使用 `uv run er qa first-battle`：通过只读实时接口规划，仍走真实ADB输入，每轮保存一次。一次实际运行98.43秒、33动作、6次回合存档完成通关，记录在`temp/playtest/d0c490e1/`；正常速度完整通关是另一个独立验证，不混为同次运行。

本地运行产物位于忽略的 `temp/first-battle/`、`temp/gameplay-feedback/`、
`temp/save-slots/`、`temp/world-inventory/`、`temp/feedback-v2/`、`temp/playtest/`、`temp/playtest-api/` 和 `temp/scroll-assistance/`，具体入口由对应实施票记录。
本轮最终平台测试均备份原有 JSON，并在结束后核对恢复；模拟器批次结束即关闭。

## 产物与后续范围

- APK：`build/android/emblem-rekindled.apk`。
- Web：`build/web/`，本地预览 `http://127.0.0.1:8765/`。
- 横屏布局与旋转另见 [横屏验收](landscape.md)；后续关卡、完整三章主线、实体设备及扬声器听感仍单独推进，不将其写为已验证。
