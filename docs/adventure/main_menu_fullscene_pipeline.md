# 主菜单全景静态受光与统一时段｜第 4 阶段

> 本文保留 S4 全景时段基线。当前地表组织与局部照明候选见 [静态收口管线](main_menu_static_finish_pipeline.md)；不要覆盖本阶段基线。


## 先看预览
- previews/day.jpg、dusk.jpg、night.jpg：全景白天、黄昏、夜晚。
- previews/day_dusk_night.jpg：三种时段纵向对照。
- previews/time_transition.gif：48 个实际 Godot 渲染时段帧，正放后倒放形成无跳变循环；94 个显示帧，无补帧、无风水烟动画。
- previews/normal_comparison.jpg：相同黄昏参数，法线关闭/开启。
- previews/window_comparison.jpg：相同夜间参数，窗灯与溢光关闭/开启。
- previews/control_maps.jpg：实际参与构建和渲染的技术贴图。
- previews/day_ui.jpg、dusk_ui.jpg、night_ui.jpg、ui_comparison.jpg：沿用上一阶段真实 UI 素材与尺寸的布局合成，尚未实装。

## 权威源与可调整节点
唯一母图为 master_original.png，1672×941，SHA256：71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02。
原母图和已认可的研究室样板均未改动。此前误生成的昼夜图片未参与本轮。

scene_config.json：46 个大面/简化曲面区域、28 个窗灯范围及天空、水面、远景、植被配置。按源图坐标编辑：
- surfaces[].shape / normal / curve / weight / exposure：物体范围、方向和法线响应。
- selectors：在限定范围内辨别玻璃、植被等；不能当成完整自动语义分割。
- windows[].shape / selector / power / blur / spill_gain：窗洞、窗灯强弱和扩散。
- spots[].center / radius / strength：局部地面溢光位置与范围。
- repairs：局部底色修整，含范围、增益、羽化和亮面门限。禁止直接改写原母图。
- atmosphere：天空范围、天空颜色筛选、水域/远景范围、云层识别、植被简化受光。

time_profile.json：day / dusk / night 关键帧。每个关键帧含光向、环境色、主光颜色、饱和度、天空顶/地平线/云色、水面与远景色、窗灯颜色/强度、溢光颜色/强度。参数不是分散在各建筑脚本里。reference 是原日光校准参数，不能随时段一起改变。

共享执行链：
`母图 + scene_config → build_scene_maps.py → maps / working_base → time_profile.json + time_profile.gd + scene_relight.gdshader → capture_scene.gd → renders / transition → assemble_previews.py`

MainMenu_FullScene_Lighting_v03.xcf：可编辑的原图保护层、工作底图、九张灰度/原生蒙版、法线/区域数据、实际 GPU 截图、独立 UI 组。修改底层前关闭 40_GPU_REFERENCES；截图组不是实时光照。XCF 手工修改不会反向同步 JSON，重建会覆盖派生 XCF，先另存并明确导回路径。

## 技术约定
法线为视空间 X 向右、Y 向上、Z 向观察者，RGB=(N+1)/2；由明确面方向和简化曲面构建。它不是完整三维几何，也不是由原图亮度猜测高度。
- maps/controls.png：R=法线作用权重，G=曝光乘子，B=窗灯强度。
- maps/environment.png：R=天空，G=水域，B=远景，A=云权重。
- maps/spill.png：独立近处溢光。
- 其他单通道图与 region_* 供原生编辑、检查与重新打包。
- 控制贴图按数值读取，颜色计算在 shader 内显式 sRGB/linear 转换；避免再叠加隐式 gamma 转换。
- GIMP 原生蒙版使用 Y u8 数值写入/回读；不要改为 Y' u8 进行数据转换。
- UI 位于材质外的独立节点，透明区域自然露出变暗的背景；不透明文字/图标不随场景压暗。

## 复现（当前 Sancho 制作环境）
本机目录：D:\Dev\Tools\ArtControl\runs\main-menu-stage4-fullscene-20261112。
依赖：已验证的 ArtControl 原生启动器、Python/Pillow/NumPy/OpenCV、GIMP、Godot。配置在 D:\Dev\Tools\ArtControl\config.json。

在新副本中编辑，不覆盖已交付基线。把本目录的母图、scene_config、time_profile、ui 文件夹和上述脚本复制到新目录，保留相对路径；本轮代码不再依赖上一阶段绝对路径。

```powershell
$root='D:\Dev\Tools\ArtControl'
$work='D:\Dev\Tools\ArtControl\runs\main-menu-stage4-fullscene-20261112'
$python=(Get-Content "$root\config.json" -Raw | ConvertFrom-Json).python
& $python "$work\build_scene_maps.py"
if($LASTEXITCODE -ne 0){throw 'Map build failed'}
& $python "$root\artctl.py" godot "$work\capture_scene.gd" --run-dir $work
if($LASTEXITCODE -ne 0){throw 'GPU render failed'}
& $python "$root\artctl.py" gimp "$work\build_workfile.py" --run-dir $work
if($LASTEXITCODE -ne 0){throw 'XCF build failed'}
& $python "$work\assemble_previews.py"
if($LASTEXITCODE -ne 0){throw 'Preview assembly failed'}
```

仅改 time_profile 时无需重建贴图；改结构/窗洞/修整时从地图构建开始。正式实装需把运行资源移入工程并清除制作路径依赖。

## 本轮实际核对
- 原图哈希与研究室基线 28 个已记录文件保持不变。
- 关闭处理的真实 GPU 输出与母图逐像素一致。
- UI 的 117,819 个全不透明像素，白天/夜晚逐像素一致。
- 关闭窗灯及溢光，仅影响对应支持范围，范围外最大通道差为 0。
- XCF 保存、重开后原图像素与锁定状态保留，九张原生蒙版数值一致。
- 48 个实际引擎过渡帧均已输出；最大相邻帧平均通道变化约 3.63/255。
- 已按实际文件作输出核对与人工审阅；未新增或运行测试套件，不宣称游戏测试通过。

证据：build_report.json、render_report.json、workfile_report.json、delivery_checks.json。

## 自审与限制
已修正初版天际线亮边及商店玻璃不均匀发光。天空只改变原有天空/云的色彩，不添加月亮、太阳、星星或新建筑。画中对象没有移动、重绘或重新生成。
目前属于完整全景的静态时段预览，使用手绘近似法线；原图投影只做局部可撤销整理，未实现太阳随时段移动的真实几何投影、反射或全局照明。水面只有颜色变化，没有运动。夜间窗灯可调，入口功能与 UI 风格仍沿用占位方案。
尚未做：船体等移动部件提取及补底、风/水/烟动画、本机时钟绑定、正式主菜单替换和交互验收。
GIMP 3.0.4 退出仍有已记录的 g_object_unref 告警；文件保存/重开与数值核对成功，未隐藏告警。
字体只用于预览中文字栅格化，交付不含字体文件。

基线保护清单属于本机审计记录，不打入可搬迁源包。预览整理在存在该记录时额外核对上一阶段文件；没有该记录时只核对当前包，不能声称重新核验了历史基线。
