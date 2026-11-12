# 主菜单美术制作管线｜单入口、配置驱动、可复现

当前港口为 S7B 返工候选；旧 S7 已被退回，不得继续将旧遮罩与最近RGB映射作为通过基线。

## 权威入口
- 代码：本目录。`menu.py` 是唯一命令入口；`python/` 为确定性构建器，`godot/` 为共享受光/动态宿主与捕获代码。`.gdignore` 避免生产游戏自动导入制作工具。
- 当前资产工作目录：`C:\Dev\Tools\ArtControl\runs\main-menu-stage7b-harbor-rework-20261112`。
- 原生工具路径：`C:\Dev\Tools\ArtControl\config.json`，复用现有 `artctl.py`。不安装新服务、不开放端口。
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
$entry='C:\Dev\PvZ\PVZ-Adventure\tools\art_bake\main_menu\menu.py'
$work='C:\Dev\Tools\ArtControl\runs\main-menu-stage7b-harbor-rework-20261112'
$tools='C:\Dev\Tools\ArtControl\config.json'
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

## 原生工作副本与数据所有权

XCF 保留原图保护层、必要部件、四张控制蒙版、GPU 参考与UI。参考静帧不是实时参数源，编辑部件前关闭参考组。手工 XCF 修改不会自动回写 JSON/浮点映射；先另存，再明确导回路径。GIMP 原生蒙版继续使用 Y u8 数值存取，禁止对控制数据额外做 gamma 变换。

源图尺寸 1672×941；母图SHA256为 `71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02`。常规画面导出1066×600，原像素近景另存；移动和位移均使用原图像素单位。

## 验收与未完成事项

按项目 AGENTS 未新增/运行测试套件。交付核对涵盖构建前后静态一致性、关闭动态与S6逐像素对照、固定码头/动态范围外像素、循环首尾、原图与历史文件哈希、XCF保存重开。真实输出记录在工作目录 reports，不用旧报告冒充新结果。

尚未完成：生产菜单替换、真实入口交互、其余风/布料/烟等动态、本机时间的清晨/昼夜闭环与绑定。没有新增场景物件或生成图片。

官方技术参考：Godot SubViewport/ViewportTexture，用于实时受光纹理的二级采样；本方案关闭 HDR2D，保持已核对的颜色编码。
https://docs.godotengine.org/en/stable/tutorials/rendering/viewports.html
https://docs.godotengine.org/en/stable/classes/class_viewporttexture.html
