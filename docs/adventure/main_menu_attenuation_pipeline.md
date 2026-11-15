# 主菜单光衰减重调｜第 6 阶段

> S6静态光照已认可并保留。本轮可复用入口和港口动态见[港口制作管线](main_menu_harbor_pipeline.md)；不要继续在历史目录上叠加新的活动部件实现。


## 手机预览
- previews/night.jpg：重调后的完整夜景。
- previews/night_before_after.jpg：上为上一版、下为当前版；相同母图、地表、环境色、窗灯与光晕。
- previews/falloff_closeups.jpg：研究室与商店近景，左旧右新。
- previews/night_no_halo.jpg：关闭光晕的实际渲染。
- previews/halo_off_comparison.jpg：最终候选与无光晕对照。
- previews/day.jpg、dusk.jpg、night_ui.jpg：白天/黄昏与独立 UI 预览。

本轮不生成新图，不重画场景，不新增建筑或道具。所有预览都是已有母图的程序渲染，比较板仅做裁切、排版和标签。

## 改动范围与统一模型
唯一母图为 1672×941，SHA256：71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02。
S5 原工作目录、地表整理、shader 和 time_profile 均保留原样。新工作目录：
D:\Dev\Tools\ArtControl\runs\main-menu-stage6-attenuation-20261112

局部受光采用统一公式：
`A(d) = I / (d*d + core*core) * max(1 - (d/range)^4, 0)^2 * max(dot(N,L), 0)`

参考 Filament 的平方反比与平滑范围截止形式；有限 soft core 用来避免近点不稳定。在远场接近平方反比，范围末端的强度与斜率平滑归零。公式没有把椭圆光斑当作独立灯源，没有旧的 74.8% 直射光保底。

- 十二个墙/地面分离光斑整理为七个位置代理源，同一光源位置用于距离和方向，兼顾既有墙面与公共地表。
- 取消每盏灯独立的门前光斑多边形、center 与椭圆半径。保留真实可见表面/物体边界；这些边界不是照明范围。
- 不再按绿色分类扣去 80% 地面直射光；草地仍用自身底色参与接收。
- 光场使用 float32 累加并作为 RGBA32F 纹理读取；没有 0～1 截顶，也不在 1/255 处砍掉弱光。
- 未增加三维模型、面光采样系统、动态阴影或逐灯实现。既有窗灯/光晕、UI 不变。

这仍是固定视角的二维近似：source 的 Z 是代理深度，距离单位不是重建的真实米；现有大面法线与画中投影保留。采用常用衰减不等于完成物理准确的三维光照。

## 唯一调整入口
`attenuation_config.json`：
- lights[].position：同一光源的 x、屏幕 y、代理 z，距源衰减和朝向使用同一位置。
- lights[].intensity：亮度/光能，调整不改变原图；重建场后重新渲染。
- lights[].range：影响距离，接近外缘平滑归零。
- core_radius：近场软核心，共用一个数值；不是额外的光晕。
- lights[].surfaces / ground：哪些既有墙面及可见地面接收该光；不添加独立门前光斑。
- ground_polygon / ground_normal：全场可见地面的近似接收范围与方向。

`time_profile.json`：沿用 S5 的整体时段、窗灯、光晕与 local_strength/local_color。只改总体强度或色温时无需重建场。
`scene_relight.gdshader`：与 S5 完全相同，仍按表面底色接收局部光。此次修正发生在光场源头，未叠加修补 shader。

## 数据与工作副本
权威链：
`母图/既有区域法线 + attenuation_config → build_attenuation.py → attenuation_maps/receivers.rgba32f → capture_attenuation.gd → Godot实际截图 → assemble_previews.py`

浮点文件为小端 float32，布局 H×W×RGBA，四通道依次 home/library/shop/research。capture 使用 Image.FORMAT_RGBAF；不可当作颜色纹理额外做 gamma 变换，不能换成普通 8 位 PNG 后继续声称无截顶。

`attenuation_maps/receive_*.png`、`receivers_preview.png` 仅是归一化显示代理。当前显示倍率为 2：PNG/原生蒙版值需要乘 2 才对应近似光场，但存在 8 位量化，不能反过来覆盖浮点权威源。精确倍率见 attenuation_report.json。

`MainMenu_Attenuation_v05.xcf` 保存锁定母图、沿用地表、四张归一化接收光显示蒙版、既有窗灯/光晕、法线、实际 GPU 对照和 UI 占位。默认夜间参考可见；编辑前关闭 50_GPU_REFERENCE。XCF 仍是可编辑查看副本，不会自动回写配置或浮点场。

旧光场只在 baseline/local_receivers.png 中，用于前后复现；正常渲染仅读取新的浮点场。

## 复现
先复制本阶段到新的调整目录，保留相对路径。依赖已接通的 ArtControl、Python/Pillow/NumPy/OpenCV、Godot 和 GIMP，无新增软件。

```powershell
$root='D:\Dev\Tools\ArtControl'
$work='D:\Dev\Tools\ArtControl\runs\main-menu-stage6-attenuation-20261112'
$python=(Get-Content "$root\config.json" -Raw | ConvertFrom-Json).python
& $python "$work\build_attenuation.py"
if($LASTEXITCODE -ne 0){throw 'Field build failed'}
& $python "$root\artctl.py" godot "$work\capture_attenuation.gd" --run-dir $work
if($LASTEXITCODE -ne 0){throw 'GPU render failed'}
& $python "$work\assemble_previews.py"
if($LASTEXITCODE -ne 0){throw 'Preview check failed'}
& $python "$root\artctl.py" gimp "$work\build_workfile.py" --run-dir $work
if($LASTEXITCODE -ne 0){throw 'XCF build failed'}
```

没有 baseline_protection.json 时不会检查其他机器上的历史源文件；仍核对当前母图、输入、实际渲染与范围。基线保护清单不属于可搬迁运行依赖。

## 本轮核对记录
- 母图、地表及 S5 的 25 个记录文件不变。
- 关闭处理的 GPU 输出与原图逐像素一致；本轮白天与 S5 白天完全一致。
- 使用旧场重渲染得到的 before_night 与 S5 夜景完全一致；仅窗灯状态也完全一致。
- 新场峰值约 1.0393，479 个大于 1 的数值保留，未截成 1；float32 写入与读回逐值一致。
- 局部光支持范围外像素一致；117,819 个不透明 UI 像素在日/夜保持一致。
- XCF 保存重开后母图、保护锁定和四张显示蒙版一致。
- 已完成文件、数值、像素与实际预览检查；未新增或运行测试套件，未启动正式游戏或读取玩家存档。

GIMP 退出仍有既有 g_object_unref 告警，未隐藏；输出保存/重开核对成功。最终视觉仍待用户验收，不宣称物理准确或全部场景制作完成。

## 参考
Google Filament / Punctual lights / Attenuation function：
https://google.github.io/filament/main/filament.html
Godot Image / FORMAT_RGBAF：
https://docs.godotengine.org/en/stable/classes/class_image.html
