# 主菜单美术制作管线｜单入口、配置驱动、可复现

## 当前正式运行入口（9B）

正式主菜单为 `res://scenes/main/01StartMenuCoastal.tscn`。受光/风/高亮唯一运行源码已迁至 `scripts/ui/start_menu/coastal/`，shader在 `shaders/ui/main_menu/`；本目录只拥有离线构建/原生发布/隔离录制。旧godot/scene_host等仅继承正式代码，不准重复实现。

`menu.py publish-runtime` 从已批准美术工作目录发布原生贴图；`runtime-preview` 使用正式场景录制真实业务，`runtime-preview-images`只整理已有帧。参数均沿用 `--workspace` 和 `--tools-config`。正式时刻/界面位置权威在 `assets/adventure/main_menu/coastal/config/daily_cycle.json` / `ui_layout.json`，不被旧美术工作目录覆盖。

完整当前维护说明：`docs/adventure/main_menu_runtime_pipeline.md`。下方为既有美术构建/参数职责，历史S7/S8/S9A目录仍作基线保留，不代表生产路径。


S7B港口与S8风动已通过。当前9A为建筑入口交互候选：真实功能门面和鼠标/键盘输入，正式启动场景尚未替换。旧S7仍为退回版。

## 权威入口
- 代码：本目录。`menu.py` 是唯一命令入口；`python/` 为确定性构建器，`godot/` 为共享受光/动态宿主与捕获代码。`.gdignore` 避免生产游戏自动导入制作工具。
- 当前资产工作目录：`D:\Dev\Tools\ArtControl\runs\main-menu-stage8-wind-20261112`。
- 原生工具路径：`D:\Dev\Tools\ArtControl\config.json`，复用现有 `artctl.py`。不安装新服务、不开放端口。
- `workspace/runtime` 是自动部署的执行副本，不得在里面修改权威源码。交付包将本目录作为 `pipeline_source/` 保存，可指向新的工作目录。

## 简单修改应该改哪里

| 目标 | 文件与字段 | 是否重建技术贴图 |
|---|---|---|
| 船浮动幅度、微摆 | `config/motion.json` 的 boat.heave_px / sway_px / roll_degrees | 否；在已核对包络内直接渲染 |
| 动作快慢 | motion.loop_seconds | 否；相位与导出长度共用这个周期 |
| 水面位移/亮纹、夜间强度 | motion.water | 否 |
| 接触波纹强度/形状 | motion.contact | 否 |
| 暂停/关闭 | 宿主 set_phase / set_elapsed；motion.enabled=false 可恢复静态基线 | 否 |
| 时段光色、窗灯与光晕 | config/time_profile.json | 否 |
| 局部光位置/范围 | config/attenuation_config.json | 只重建浮点光场 |
| 地面路径、窗灯静态区域 | config/finish_config.json | 重建地表/发光数据；受依赖变化影响的后续阶段自动重建 |
| 建筑表面/法线/全景分区 | config/scene_config.json | 重建基础图与依赖数据 |
| 船轮廓、码头遮挡、补底范围 | config/harbor_layout.json | 只重建港口资产 |
| 视频帧率、静帧相位、UI占位 | config/pipeline.json | 不改技术贴图 |

单入口依据输入内容哈希和派生文件哈希跳过未改变阶段。运动/时段参数不属于贴图构建依赖，不再为了改速度重跑灰度/法线。布局、光源或可见运动包络改变仍需相应重建，不能说所有改动都只需调整一个滑块。

## 命令

```powershell
$entry='D:\Dev\PvZ\PVZ-Adventure\tools\art_bake\main_menu\menu.py'
$work='D:\Dev\Tools\ArtControl\runs\main-menu-stage8-wind-20261112'
$tools='D:\Dev\Tools\ArtControl\config.json'
python $entry build --workspace $work --tools-config $tools
python $entry render --workspace $work --tools-config $tools
python $entry preview --workspace $work --tools-config $tools
python $entry workfile --workspace $work --tools-config $tools
# 完整顺序；调整前复制工作目录以保留已批准基线。
python $entry all --workspace $work --tools-config $tools
```

`render` 自动执行必要构建；`preview` 仅整理已有真实帧。`build --force` 强制重新派生，不修改母图。捕获静帧可把 capture.animate=false，交付动态预览时应开启。失败会中止后续步骤，不能把旧文件存在当作本轮成功。

## 统一流程与边界

1. `base_maps.build(workspace)`：母图＋scene_config→基础底图/区域/大面法线。
2. `ground_emitters.build(workspace)`：finish_config→地表整理/窗灯/光晕；旧十二个门前光斑生成路径已经删除。
3. `light_field.build(workspace)`：attenuation_config→同源平方反比 RGBA32F 光场，无截顶。
4. `harbor_assets.build(workspace)`：原母图＋局部标注→船部件、固定前景、水域作用图、通道分离/预乘部件/分材质补底。
5. `scene_host.gd`：先在 lit_view 用已批准材质实时受光，再把该 ViewportTexture 交给港口动态层。船体颜色与窗灯一起采样，不使用三张日/暮/夜船贴图。
6. `capture.gd`：显式相位/秒数驱动，输出昼夜静帧和真实循环帧；`previews.py` 只裁切、排版及视频/GIF编码，没有生成式补帧。
7. `workfile.py`：创建原生 XCF，保存重开后检查母图锁定与蒙版数值。

构建模块导入不执行文件操作；各模块只接受工作根，局部数组与配置封装在函数内。生产运行接入尚未进行，游戏不能依赖本机制作目录或完整制作脚本。

## 港口拆层与运动约束（S7B）

- `harbor_matte.py` 混合语义trimap、色差通道、明度细线、RGB柱选区与source-over去底色；`harbor_assets.py` 统一生成资产。不是把粗多边形直接当最终边缘。
- 舷内木柱属于船体组；码头栏柱/栏绳为固定前景。不能将所有柱子统一覆盖在船上，也不能用大区域固定遮罩冻结一块船身。
- 船与码头前景的运行纹理为预乘RGBA32F，颜色和透明度共同滤波。旧 clean_lookup/boat_lookup 最近RGB映射已删除，不再保留第二条运行路线。
- 背景按海水/码头材质分别从原图确定性修补；柱后船身只做同材质窄带克隆与连续延拓。仅保证当前微幅包络，不能当作完整的隐藏三维场景。
- `boat_premult.rgba32f` / `fixed_premult.rgba32f` 是预乘颜色；`boat_light_uv` / `fixed_light_uv` / `clean_light_uv` 只引用对应材质的当前受光，不用于把最近RGB拉成条带。
- `harbor_masks.png` 仍为R船/G固定前景/B水域/A补底，原图不变。接触波纹改由移动后的下船沿轮廓派生，旧独立椭圆配置已去掉。
- 普通运动调参仍只改 motion.json，未通过降低幅度掩盖旧边缘问题；需要放大幅度时必须重新审查遮挡与缺失内容。系缆固定端由前柱遮挡，没有新增绳索物理。
- 验收必须包括黑/灰/白底与极限相位，范围外像素不变、静态回退一致不能证明动态图层分离正确。

## S8 新增风场（不替代港口）

- `config/wind.json` 管总开关、强度、风向、阵风和各部件响应；普通风速/幅度只需重新渲染。`wind_layout.json`管树冠保边、布料trimap、固定点和选择范围，需要时只重建wind资产。
- `wind_assets.py` / `cloth_matte.py` 保留原像素，颜色选区与闭合轮廓避免窗玻璃混入布料；遮阳棚补底沿原窗面的列方向延拓，不用最近二维RGB把窗框拉成分叉。
- `wind_field.gdshaderinc` 是唯一公共函数；`wind_layer.gd` 持有一个显式时钟，两个材质使用同一风场，各部件有不同响应与相位。
- `lit_view → land_wind（树冠、棚）→ harbor（既有港口＋船局部旗帜）→ UI`。旗帜在原像素内预先分为flag与无旗船两个预乘分量，然后按船局部坐标变形；不重复叠加船位移。
- 树冠只动内部叶面，轮廓/树干/屋顶交界固定；遮阳棚上边及侧支点固定，自由外沿轻动。没有新物件、粒子、烟鸟或本机时间读取。
- `set_wind_enabled(false)` 只关闭本轮新增效果，同相位输出应与通过的S7B逐像素一致。整体风强度为0也旁路；树冠/遮阳棚/旗分别有enabled开关。
- 预览默认6秒24FPS，和现有港口共同循环。改周期时须让capture.duration_seconds覆盖各周期的共同循环；周期内cycles采用整数，避免首尾相位不一致。
- 近景和XCF由同一入口输出；`wind_previews.py`检查风关闭对照、作用域外、固定端和循环。此类数值不代替实际边缘/观感审查。详见 `docs/adventure/main_menu_wind_pipeline.md`。

## 原生工作副本与数据所有权

XCF 保留原图保护层、必要部件、四张控制蒙版、GPU 参考与UI。参考静帧不是实时参数源，编辑部件前关闭参考组。手工 XCF 修改不会自动回写 JSON/浮点映射；先另存，再明确导回路径。GIMP 原生蒙版继续使用 Y u8 数值存取，禁止对控制数据额外做 gamma 变换。

源图尺寸 1672×941；母图SHA256为 `71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02`。常规画面导出1066×600，原像素近景另存；移动和位移均使用原图像素单位。

## 验收与未完成事项

按项目 AGENTS 未新增/运行测试套件。交付核对涵盖构建前后静态一致性、关闭动态与S6逐像素对照、固定码头/动态范围外像素、循环首尾、原图与历史文件哈希、XCF保存重开。真实输出记录在工作目录 reports，不用旧报告冒充新结果。

尚未完成：生产菜单替换、真实入口交互、本轮以外的环境动态、本机时间的清晨/昼夜闭环与绑定。没有新增场景物件或生成图片。

官方技术参考：Godot SubViewport/ViewportTexture，用于实时受光纹理的二级采样；本方案关闭 HDR2D，保持已核对的颜色编码。
https://docs.godotengine.org/en/stable/tutorials/rendering/viewports.html
https://docs.godotengine.org/en/stable/classes/class_viewporttexture.html

## 建筑交互入口（9A）

- `menu.py entries --workspace 工作目录 --tools-config ArtControl/config.json`：必要资产构建、独立完整工程原生输入录像和预览；`entries-preview`只编码已有实际帧，不再次执行交互。
- `config/entries.json`：命中、排除、可见高亮、标签锚点和表现参数分开；可用性从实际AdventureToolbar门面读取，不能由美术配置解锁。
- `building_entry_hit/layer`归游戏UI代码；`toolbar_entry_host`是原工具栏共用门面而非第二管理器。制作代码只负责视觉与记录，不保存玩家业务状态。
- `entry_highlight`在受光后、风/船变换前，关闭即透传S8。可见蒙版R与内侧边G由entry_assets派生，RGBA中的颜色含义不能与旧法线控制图混用。
- 原生预览使用独立user目录与原游戏资源；临时演示档案明确标注。native_project是资源链接和派生manifest，不是独立可发布包，禁止递归打包或对其额外执行editor导入。
- 当前资产目录为 `D:\Dev\Tools\ArtControl\runs\main-menu-stage9a-entries-20261112`。新原生交互需要完整原工程；原all/render仍是离线美术捕获，不伪装为可点击窗口。
- 详细职责、已开放入口与未完成边界见 `docs/adventure/main_menu_entries_pipeline.md`。图鉴/研究室/地图真实打开，家/商店未开放，最终功能台/档案按钮仍待9B整合。

## 效果可替换性与案例入口

权威说明：`docs/adventure/main_menu_effects_api.md`。运行effect_profile只持有hover算法、灯组时间调制和水面算法/独立周期，默认中性；原几何、常规幅度、时态和业务仍归原配置。制作示例在effect_examples，不自动覆盖正式美术。

`python menu.py effects-preview --workspace <独立交付目录> --tools-config <ArtControl/config.json>` 复制当前菜单代码/资源到无autoload空工程，直接调用正式接口演示，输出144帧案例及恢复默认的截图。没有加载玩家存档，也不重建原母图/灰度/法线。案例不是默认效果替换决定。

publish-runtime遵守runtime_inputs.json的runtime_owned_configs，保留daily_cycle/ui_layout/effect_profile。自定义hover shader通过uniform契约绑定；水面算法扩展写在water_surface include，不复制整个harbor shader。
