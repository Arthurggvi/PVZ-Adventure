# 地图关卡预览

## 唯一入口

僵尸岛 `scripts/adventure/zombie_island.gd` 与奇境大陆 `scripts/adventure/world_map/world_map_stage_ui.gd` 共用 `scripts/adventure/ui/stage_preview_panel.gd`。正式关卡数据通过 `StagePreviewData.build()` 投影；未通关仍显示问号，未开放地区仍只显示介绍。

## 输入与生命周期

- `request(data, anchor)` 延迟展示；相同数据、相同锚点的往返悬停保留滚动位置，切换关卡重新归顶。
- 节点鼠标或焦点移出接 `release_hover()`，留出 0.35 秒跨越空隙；指针留在原节点或面板内时保持阅读。
- `cancel()` 用于模态、移图、返回等立即关闭；`dismissed` 发出后地图释放预览身份。
- 奇境大陆逐帧只恢复实际鼠标悬停，键盘展示由 `focus_entered` 驱动，禁止旧按钮焦点抢走正在阅读的内容。
- `stage_preview_view.gd` 使用唯一原生 `ScrollContainer` 接收滚轮、滚动条和触摸；面板与滚动条阻止滚动事件传给地图。没有自动往返滚动时钟。
- Android 保留既有“首次轻触查看、再次轻触同一关进入”流程；面板内滑动不等于点选关卡。

## 数据与显示

- `stage_preview_data.gd` 只消费已合并的 `StageDefinition`。`daytime=true` 显示白日；`daytime=false/daytime_sun=true` 显示黄昏；两者为假显示夜晚。噩梦、终末标签仅在对应阶段实际存在时追加。
- `stage_preview_drops.gd` 沿用正式掉落表和既有事件过滤，提供物品名称、类别、图标及配方来源；不读取库存、不执行掉落、不修改概率或奖励规则。
- `recipe_drops` 按物品 ID 去重，`sources` 合并普通、噩梦、通关和指定 Boss 遭遇。数量不跨来源累加；顶部摘要不显示数量、不承诺必掉。
- `stage_preview_content.gd` 将“本关可掉落植物配方”置于正文最前，金色边框、84 像素图标、完整名称和来源共同突出；完整阶段掉落网格继续保留 56 像素图标及原数量角标。
- `stage_preview_art.gd` 复用背包配方美术、图鉴头像与等阶徽章。新增关卡或配方应维护权威目录，不在 UI 添加按关卡编号分支。

## 本轮核验边界

2026-11-19：按 `AGENTS.md` 不新增、不运行测试或实机游戏。完成源码与调用关系审查、Godot 4.7.2 工程编辑器导入检查（退出码 0、无报错）及 Git 差异检查；桌面实际交互和 Android 实机效果待运行验收，不能把源码接入写成实机通过。
