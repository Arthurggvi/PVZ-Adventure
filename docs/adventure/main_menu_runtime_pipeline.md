# 9B｜正式海滨主菜单、全天时态与真实功能

## 0｜当前权威入口

- **正式启动场景**：`res://scenes/main/01StartMenuCoastal.tscn`。`project.godot` 与 `MainSceneRegistry.StartMenu` 已同时切换，地图返回也只读注册表。
- **运行组件**：`scripts/ui/start_menu/coastal/`；**运行材质**：`shaders/ui/main_menu/`；**发布资源**：`assets/adventure/main_menu/coastal/`。
- **制作入口**：`tools/art_bake/main_menu/menu.py`。制作端的scene_host/wind_layer/entry_highlight/time_profile只是继承正式实现的入口，不能在其中重新实现一份算法。
- **本轮交付目录**：`D:\Dev\Tools\ArtControl\runs\main-menu-stage9b-runtime-20261112`。母图/分层制作基线仍在各已批准阶段，正式运行不依赖这些绝对路径。
- **母图**：1672×941，SHA256 `71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02`。本轮未生图、未重画任何场景物件。

## 1｜运行与制作的所有权

运行时按 `texture_catalog.json` 读取原生压缩 ImageTexture 资源及 JSON。母图颜色、预乘透明部件、灰度、法线和 RGBA32F 光场在发布时保存并重开逐字节比对，`asset_store.gd` 对同一宿主中的重复引用只加载一次。

受光阶段将旧溢光权重和旧灯组自发光分别写入 `working_base.png` 和 `maps/controls.png` 对应运行纹理的 Alpha 通道。原 RGB 和两张灰度图的数值逐字节保留，两张灰度图仍是制作输入。发布与制作预览共享通道布局，受光材质使用 8 个自定义采样器，适配 16 个片元纹理槽的 Compatibility 设备。

离线原始PNG/浮点读取只用于制作目录；正式res目录没有catalog时直接拒绝，不静默回退到某台机器的外部路径。发布入口只复制必要输入，不携带录制档案、用户路径、GIMP/Python或原生项目链接。

`scene_host.gd` 按统一受光 → 建筑高亮 → 陆地风 → 港口的顺序使用四个视口，UI 在背景材质之外。最终视口先画全景水面底层，再在 256×315 原画像素内绘制船和旗，在 210×130 原画像素内绘制固定码头。船旗与码头使用预乘透明混合，各层共享陆地风视口的输出作为取光参考。`apply_uniforms()` 是日周期和旧 0～1 预览共用的参数提交入口。

每次 Compatibility 绘制最多使用 8 个自定义纹理采样器。以片元纹理单元数为 16 的设备为基准，槽 0 绑定 `TEXTURE`，引擎会在槽 9 起的高位范围绑定 Canvas 内部输入，自定义材质使用槽 1～8。新增或调整材质时，应按实际绘制拆分并核对这一预算。

## 2｜全天时间与调参

运行配置：`assets/adventure/main_menu/coastal/config/daily_cycle.json`。

| 时段 | 默认小时 | 说明 |
|---|---:|---|
| 午夜／深夜 | 0／4.5 | 沿用已通过夜间参数 |
| 黎明 | 6 | 独立设计的柔和冷暖变化，不倒放黄昏 |
| 清晨 | 7.5 | 逐步接近日间，窗灯逐步关闭 |
| 白天／下午 | 9／16 | 沿用已通过白天参数 |
| 黄昏 | 18.5 | 沿用已通过黄昏参数 |
| 夜晚 | 20.5 | 沿用已通过夜间参数并跨午夜连续保持 |

这些时刻是可编辑美术安排，不是根据地理位置计算日出。关键帧的hour升序，uniforms键集合保持一致；`daily_cycle.gd` 在24小时环上平滑插值，最后一段连到次日第一段。

`menu_clock.gd` 默认读取电脑当地时间，15秒采样一次，焦点恢复时重新校准；变化以1.2秒在材质参数之间衔接，不用快速播放中间一天来赶时间。启动即读取当前时段，在离屏合成准备和原有揭幕完成前不暴露白天默认帧。

`coastal_menu.gd` 的风、水、船和交互过渡使用单调计时，单次恢复步长钳制；系统时钟只影响显示光色，绝不修改任务日期、战斗计时或存档时间。时钟来源可注入供预览；默认不保存指向自身的Callable，避免RefCounted循环引用。

手动预览：`set_preview_hour(hour)`；恢复本机时间：`use_local_time()`。二者不修改电脑系统时间。制作回放可以设置 `motion_paused` 并指定host动作秒数，不能把这些录制标记持久化进玩家档案。

## 3｜真实UI与原有业务共用

- 头像/等级/名字复用 `adventure_profile_hud.gd`，通过新增的显式画布布局参数保持已确认位置；未传参数的地图和战斗HUD行为不变。
- 原旧菜单User节点提取为 `scenes/ui/profile_selector.tscn`，保留原 `UserManager/SaveService/User` 的校验、保存、切换和失败回滚，不重新实现档案事务。
- 档案动作在头像右侧，位置由 `coastal/config/ui_layout.json` 配置。
- 工具栏齿轮通过 `AdventureToolbar.request_feature("settings")` 打开居中的桌面设置窗。
- 关闭系统窗口时先确认，再经原 SaveService 保存当前已加载的档案。保存失败会显示原因并留在菜单。正常退出先回收本菜单，再结束进程。
- 档案和退出窗口由菜单独有的顶层管理器维护。工具栏及建筑通过同一查询避免输入穿透。
- 建筑功能仍为图书馆→图鉴、研究室→既有研究功能、港口/船→地图；家/商店未开放，皮卡无独立入口。解锁来自真实档案，不写入entries配置。

## 4｜启动、返回与旧实现收口

`project.godot`、`main_scene_registry.gd` 和 `zombie_island.gd` 返回路径已统一。旧 `01StartMenu.tscn`、V6、V8只剩轻量重定向，不再实例化旧天空/落叶/牌匾/乌鸦或另一套功能台。`main_menu_v6.gd` / `main_menu_v8.gd` 重复运行脚本已删除。

历史图片没有整包粗暴删除：功能台等仍被复用，制作基线留作历史记录。新增运行场景不依赖旧菜单的环境节点。已有通用测试的失效场景地址已同步；版本专用V6/V8美术探针标明退役，未迁移全部旧节点断言，不能当成新菜单回归证据。

## 5｜发布、预览与资源包复现

```powershell
$entry='D:\Dev\PvZ\PVZ-Adventure\tools\art_bake\main_menu\menu.py'
$tools='D:\Dev\Tools\ArtControl\config.json'
# 从已批准制作目录重新发布原生贴图，保留运行侧的 daily_cycle/ui_layout/effect_profile。
python $entry publish-runtime --workspace D:\Dev\Tools\ArtControl\runs\main-menu-stage9a-entries-20261112 --tools-config $tools
# 使用正式场景/真实业务，在独立user目录录制；不修改生产存档。
python $entry runtime-preview --workspace D:\Dev\Tools\ArtControl\runs\main-menu-stage9b-runtime-20261112 --tools-config $tools
# 只整理已有真实输出，不重新打开游戏服务。
python $entry runtime-preview-images --workspace D:\Dev\Tools\ArtControl\runs\main-menu-stage9b-runtime-20261112 --tools-config $tools
```

只改运行时刻、色温、UI位置不必重做法线；改母图结构或制作贴图先走已有构建管线，再显式发布。`runtime_inputs.json` 列出唯一发布输入集合。制作工具不自动把新生成素材覆盖成正式资源。

JSON与shader include已纳入原有导出规则。自定义RGBA原始数据不参与正式导出，运行版为原生.res。独立空工程加载 `CoastalMenu_RuntimeAssets.pck` 后可绘制同一菜单，未链接原游戏目录；这是资源可搬迁性核对，**不是完整游戏exe导出**。本机没有安装导出模板，本轮未生成或验证完整exe、Android/iOS包。

## 6｜本轮实际证据与边界

- 9B 首次交付的 31 份原生纹理保存重开像素/float 数据一致，见 `reports/native_resources.json`。随后 Compatibility 受光纹理合并了两张独立灰度场。
- 全天240帧、24FPS；23:59:59与00:00:01在固定动作相位下最大像素差0。清晨/日/暮/夜实际静帧见renders。
- 完整使用流程556帧、24FPS：真实图鉴/设置/帮助、档案A↔B、研究室权限刷新、地区选择、进入僵尸岛地图、实际返回新菜单、退出保存。没有进入战斗或验收合成事务。
- 隔离目录 `PVZ-Menu9B-Isolated-20261112`；仅演示档案写盘。没有读取、复制、修改正式玩家档案。录制注入时钟没有修改操作系统时间，未物理测试电脑睡眠唤醒。
- 新菜单宿主在进入地图后释放；返回仍为Coastal场景，档案不变。最终完整日志无脚本/材质ERROR或退出资源泄漏报告。
- 本轮空闲120帧观测：RTX5060 Laptop GPU、1066×600、未截图读回时平均4.166ms、P95 4.252ms。Godot所报进程总纹理内存约724.8MB，包含游戏autoload，不是“菜单独占显存”。该短采样不等于全平台性能保证。
- 不同窗口1280×720、1066×800已按同一画布核对悬停；移动触屏/全部显示设备未验收。
- 独立PCK绘制与正式运行背景对比：白天最大通道差0、夜晚1/255，见 `reports/pack_portability.json` 与 `runtime_delivery.json`。
- 按AGENTS未新增或运行游戏测试套件；以上为本轮实际渲染、输入回放、资源/像素和生命周期核对。不得写成完整回归通过。

## 7｜预览文件

`previews/daily_cycle_overview.jpg`：六时段完整菜单；`morning_night.jpg`：清晨/夜晚。
`previews/runtime_ui_overview.jpg`：真实档案、设置、帮助、锁定、地图及返回。
`daily_cycle.mp4`：10秒完整日周期；`runtime_walkthrough.mp4`：约23秒真实输入流程。

XCF仍归已批准的9A美术工作副本，本轮没有重新绘制图层；新的时间、UI和正式运行状态以配置/源码及实际截图为权威，不另存一个会被误认为实时交互的“成品XCF”。

## 8｜效果算法与时间调制（后续封装）

hover材质替换、四组灯光呼吸/闪烁、水面算法与独立周期统一见 [效果接口索引](main_menu_effects_api.md)。正式effect_profile已启用低幅度错相灯光和独立水周期；空hover对象使用当前默认高亮算法。即时重载入口为菜单reload_visual_effects/host.reload_effects；普通几何、命中、风动参数的加载周期仍按索引区分。

日周期只提交实际relight参数，water_time_gain显式路由到港口材质；local/emission/halo组倍率由效果控制器拥有，不得在daily_cycle内重复维护。新运行profile已加入发布保护，旧制作目录不会覆盖它。

## 9｜2026-11-13 视觉与交互整理

- 白天不再与reference校准参数完全相同；较低环境光与方向光分开塑造墙面，下午有独立方向。天空地平线散射、远景空气透视与轻微前景压暗复用原环境蒙版，未改变母图或新增贴图。夜间以暖窗与冷屋顶分层，海水降低蓝色竞争。
- 船周期8.4秒、风周期9.6秒、水周期11.2秒；各灯组约±3%的缓慢错相变化。均使用原显式动作时钟，位移仍处于原分层包络内，不增加持续跳动的界面元素。
- 入口名称牌使用独立 `building_entry_badge.gd`：图鉴、研究室、启程；不再展示功能串和“点击进入”。牌匾穿透鼠标，位置落在原建筑命中范围内；权限与模态仍由同一工具栏门面查询，锁定原因只在指向时显示。
- 档案通过 `configure_coastal_presentation()` 显式启用296×118紧凑布局；存档动作位于卡片内。菜单位置/比例由ui_layout控制；地图和战斗未启用时继续原有构造。
- 运行调色、运动和入口表现已成为正式配置：`daily_cycle/ui_layout/effect_profile/time_profile/motion/wind/entries` 均由runtime_inputs保护，旧工作目录发布贴图不会覆盖调参。若重建入口蒙版，须将新的几何同时明确同步到正式entries并核对牌匾位置；只发布贴图不能代替几何同步。
- 当前核对与截图目录：`D:\Dev\PvZ\_review\menu_polish_20261113`。使用独立用户目录 `PVZ-Menu-Polish-Isolated-20261113` 的演示档案，未运行游戏测试套件。第6节的数据属于原9B交付，不能当作本轮性能或完整流程验收。
