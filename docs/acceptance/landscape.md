# 横屏布局与旋转验收

实施与证据入口：[补齐首关横屏布局、旋转操作与平台验收](https://github.com/mxp-xc/emblem-rekindled/issues/27)。

## 布局与操作契约

- Android 使用系统感应方向；Web 随窗口长宽比适配。逻辑短边720，竖屏及两个横屏方向共用同一战局。
- 战场保留全宽地图、底部HUD及角色旁行动菜单；弹窗、对白和战斗界面限定在实际地图与系统安全区。
- 世界图使用安全区内的横向空间；原贴图以外保留底色，不重复边缘像素。世界节点、路线和角色使用原坐标。
- 资料、指挥官、档槽、整理与独立战斗保留已有信息层级，按可用高度缩放；宽屏可居中留空。
- 旋转保留当前人物、页面、战局、物品确认与世界菜单，不自动提交操作；取消旧触点、鼠标拖动、资料滑动和原生按钮按压，下一次完整输入正常工作。
- 点击、拖动、滚轮与逐层返回沿用首关操作；Android Back 与键盘 Esc 各自验证。

## 自动回归

`test_rotation.gd` 覆盖画布方向、旧地图触点、新坐标、物品确认、资料滑动、世界菜单与安全区。
`test_rotation_confirmation.gd` 通过真实 `Input.parse_input_event` 覆盖触屏和鼠标按住确认后旋转、旧释放不提交、新输入只提交一次。
`test_rotation_navigation.gd` 覆盖取消鼠标事件不会推进标题、对白或地图选择。
已有 `test_dialogue_layout.gd`、`test_desktop_layout.gd`、`test_world_focus.gd` 继续覆盖多比例、全图、菜单/资料布局及焦点恢复。

```sh
uv run python tools/check_godot.py --test test_rotation.gd --test test_rotation_confirmation.gd
bun run check
```

## 平台复核

实际包必须通过 `tools/delivery.py` 导出并核对 buildId；Web 还需核对用户原地址 canvas 的 `data-emblem-build-id`。
平台检查、具体构建身份、截图和真实操作结果保存在实施票关联的 `temp/landscape/` 批次，不用自动坐标检查代替视觉复核。
测试写入前完整备份用户 JSON，结束逐字节恢复；Web 同样保护原地址 IndexedDB 记录。

复核范围包含开场/对白、地图点选和拖动、行动取消、资料/物品/交换、设置/指挥官、独立战斗、世界菜单/整理/档槽及返回。
在稳定战场、物品确认和世界菜单中切换竖屏与两个横屏；Web 覆盖常见横屏、宽横屏和手机竖屏。
自然完整首关证据沿用首关验收，本阶段定向验证方向切换；实体设备、安全区硬件差异与扬声器听感仍暂缓。
