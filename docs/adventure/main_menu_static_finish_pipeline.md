# 主菜单第 5 阶段｜地表组织与局部照明

> 本文保留 S5 地表与旧照明基线。光衰减当前已改为 [统一平方反比与浮点场](main_menu_attenuation_pipeline.md)，不得继续把本页旧门前光斑、保底和 8 位接收光当作最新实现。


## 当前成果与预览
本轮只对已批准母图作确定性处理与实际 Godot 渲染，没有调用生图、没有添加建筑/道具、没有位移原有物件。中央仍保留公共空地。本轮为静态观感候选，尚未替换游戏主菜单。

- previews/day.jpg、dusk.jpg、night.jpg：完整日/暮/夜候选。
- previews/day_before_after.jpg、night_before_after.jpg：与 S4 相同构图的前后对照。
- previews/ground_switch.jpg：只关闭/开启地面整理。
- previews/lighting_switches.jpg：仅窗灯 → 加入材质接收光（无光晕）→ 最终弱光晕。
- previews/receiver_closeups.jpg：商店与研究室近景，无光晕状态也能看到受光。
- previews/control_maps.jpg：通路、空地、商店及研究室接收区域。
- previews/night_ui.jpg、night_ui_1066x600.jpg：沿用真实 UI 素材的独立占位预览，未接正式交互。

## 权威来源与调整节点
本机目录：`C:\Dev\Tools\ArtControl\runs\main-menu-stage5-static-finish-20261112`。
唯一原图：`master_original.png`，1672×941，SHA256 `71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02`。
S4 原始文件保持不动；baseline/ 保留 S4 日/暮/夜截图供比较。不要拿重新生成的日夜图片替换任何输入。

### 地表
`finish_config.json / ground`：
- allowed_polygon、edge_feather：限定所有地面修改；建筑/植被另行排除。
- routes[].points/widths：五条宽缓通路的控制点与宽度；Catmull-Rom 插值只改变原有地表色值与纹理对比。
- route_color_lift、route_detail_retention、route_blur：路面明暗、纹理保留与过渡宽度。
- central_plaza：中央区域、纹理保留、色值偏移；没有添加中心景物。
- forecourts：四处门前承接区的范围、羽化与色值，不复制等大的铺装块。
- shader 的 ground_strength：运行时整体强度，设 0 可回到 S4 工作底图。该操作发生在照明前，不能把夜间暖光烘焙进白天地面。

### 局部灯光
`finish_config.json / lighting`：四组 home/library/shop/research，共十二个光源—接收区域定义，全部走同一构建器。
- groups：每组窗灯倍率、灯源光晕宽度/强度。
- sources[].source：固定视角的屏幕 X/Y 与近似向外高度参数；不是完整世界坐标。
- center/radius/falloff/power：接收区域内的衰减中心、范围与强度。
- receiver.surfaces/polygon/feather/exclude_polygons：可受光表面、额外地面区域、边缘和排除区。
- normal_influence：构建固定光场时大面法线对方向响应的权重。

`time_profile.json`：
- local_strength / local_color：局部材质受光的总强度与颜色。
- halo_strength / halo_color：独立灯源光晕；当前夜间为 0.16，关闭设 0。
- window_energy、window_color：窗灯本体。emission_balance 控制新的分组明暗，1 为本轮、0 为旧窗灯权重。
- legacy_spill_strength：旧 S4 简单溢光开关，本轮为 0，避免重复叠加。
- ground_strength：各时段的地表整理开关，当前均为 1。
- 全局环境/天空/水面/主光沿用 S4，未通过额外压暗整个画面伪造灯光对比。

`scene_relight.gdshader`：同一材质内完成环境受光、局部材质受光、窗灯、少量灯源光晕；UI 放在其外。`local_group_energy` 是四组接收光倍率，当前默认全 1；需要运行时独立组调参时由调用者设置，不声称已有调参 UI。

## 源数据与派生资源关系
`scene_config.json + 母图 → build_scene_maps.py → S4 基础工作底图/法线/区域图`
`finish_config.json + 基础工作底图/区域图 → build_finish_maps.py → ground_finished.png / finish_maps/*`
`time_profile.json + time_profile.gd + scene_relight.gdshader → capture_finish.gd → renders / transition`
`renders + baseline → assemble_finish_previews.py → previews`
`原图/工作底图/控制图/实际截图 → build_finish_workfile.py → MainMenu_Static_Finish_v04.xcf`

局部光场采用配置化接收区域、范围衰减与近似法线预计算；改光源位置、范围、接收面或法线要重新构建，强度/颜色由 shader 参数控制。这不等同于动态三维点光或真实遮挡投影。

### 通道约定
- finish_maps/local_receivers.png：RGBA 分别为 home/library/shop/research 接收光权重。
- local_emission.png、source_halo.png：相同分组顺序。
- base_group_emission.png：旧主要建筑窗灯占用范围，防止旧新窗灯重复添加；船和灯塔原发光保留。
- ground_allowed/routes/plaza/forecourts：独立地表控制。
- 相同内容同时保存各组单通道 PNG 便于查看与原生蒙版编辑。运行时使用打包图，不能只改单通道图就声称已同步打包数据。
- 既有法线仍是视空间 X 向右、Y 向上、Z 向观察者；控制图作为数值处理。GIMP 原生蒙版使用 Y u8 存取，不作颜色 gamma 变换。

## 可编辑 XCF
`MainMenu_Static_Finish_v04.xcf`：锁定母图、上一阶段工作底图、地表整理底图、16 张可独立编辑的控制层及原生蒙版、已有大面法线、实际 GPU 参考图与 UI 组。
默认显示夜间参考。编辑底层前关闭 70_GPU_REFERENCES，截图不是实时参数源。手工 XCF 修改不会自动回写 JSON；先另存，并明确导回流程。重建 XCF 会从源数据覆盖派生内容。

## 复现（先复制本目录到新调整目录，勿覆盖已批准基线）
依赖现有 ArtControl、Python/Pillow/NumPy/OpenCV、Godot、GIMP；字体只用于栅格化标题，不在源包中。

```powershell
$root='C:\Dev\Tools\ArtControl'
$work='C:\Dev\Tools\ArtControl\runs\main-menu-stage5-static-finish-20261112'
$python=(Get-Content "$root\config.json" -Raw | ConvertFrom-Json).python
& $python "$work\build_scene_maps.py"
if($LASTEXITCODE -ne 0){throw 'Base maps failed'}
& $python "$work\build_finish_maps.py"
if($LASTEXITCODE -ne 0){throw 'Finish maps failed'}
& $python "$root\artctl.py" godot "$work\capture_finish.gd" --run-dir $work
if($LASTEXITCODE -ne 0){throw 'GPU render failed'}
& $python "$root\artctl.py" gimp "$work\build_finish_workfile.py" --run-dir $work
if($LASTEXITCODE -ne 0){throw 'XCF build failed'}
& $python "$work\assemble_finish_previews.py"
if($LASTEXITCODE -ne 0){throw 'Output verification failed'}
```

仅调整 time_profile 时可以跳过两个地图构建。编辑 finish_config 时只需要重新构建 finish_maps；修改原有表面/法线要从基础图开始。保留 baseline 日/暮/夜和 ui 文件夹；不依赖其他阶段的绝对制作路径。本机 baseline_protection.json 只用于额外核对 S4 原文件，不包含在搬迁源包中。

## 本轮实际核对与边界
- 原图哈希与 S4 的 28 个记录文件不变；关闭处理的实际 GPU 输出与母图逐像素相同。
- 地表修改及其渲染只发生在允许区域；局部受光与光晕也只影响各自支持范围，范围外逐像素相同。
- 117,819 个不透明 UI 像素在日/夜一致；夜景没有 RGB 全部达到 254 的全白截断像素。
- XCF 保存重开后原图、内容/位置锁定和 16 张原生蒙版数值一致。
- 这是交付文件/像素/实际渲染与人工自审，没有运行测试套件，不声称游戏测试通过。

保留中央空地，地面修改故意克制；没有用物件填满画面。受光为固定视角美术近似，门前光区经过手工配置，不包含真正三维遮挡、全局照明或动态反射。未做船/水/风/烟动画，未读取本机时间，未替换生产菜单或玩家数据。
GIMP 退出仍记录既有 g_object_unref 告警；本次保存/重开与数据核对成功，未隐藏告警。
