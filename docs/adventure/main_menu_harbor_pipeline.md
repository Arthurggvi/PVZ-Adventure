# 主菜单第 7 阶段｜制作流程封装与港口动态

## 先看手机预览
- previews/harbor_day_night.gif：白天/夜晚并排的港口动态，6 秒循环。
- previews/day_harbor_full.mp4、night_harbor_full.mp4：完整场景，24 FPS，各6秒。
- previews/day_harbor_closeup.mp4、night_harbor_closeup.mp4：原像素港口近景放大；便于检查船体、索具、固定栏杆和波纹。
- previews/harbor_day_night.jpg、full_day_night.jpg：动态中的静帧，不代替视频验收。
- previews/day_ui.jpg、night_ui.jpg：沿用真实界面素材与位置的占位检查。

所有帧均由同一母图在 Godot 实际渲染，没有调用生图工具，没有生成式补帧。静态光照沿用已认可的 S6，未改变整体气氛。

## 本轮先完成的封装
权威代码在工程 `tools/art_bake/main_menu`；统一入口 menu.py。技术贴图、地面、窗灯、浮点受光、时段、港口素材和动态预览各有明确责任。

- base_maps：基础明暗/区域/大面法线。
- ground_emitters：地面与窗灯/光晕；旧十二光斑逻辑已移除。
- light_field：已认可的统一平方反比浮点光场。
- harbor_assets：船体、固定遮挡、水域、原像素补底采样映射。
- scene_host：统一时段受光视口＋有界动态合成视口，UI独立。
- capture / previews / workfile：分别负责真实导出、手机整理和原生分层副本。

构建缓存检查输入内容与派生文件，不靠文件日期。只调整 motion/time_profile 不重建整套灰度/法线；轮廓/光源/地面改变才重建相应依赖。代码导入不执行构建，局部数组与配置封装在函数中。

## 调参位置
| 调整 | 配置 |
|---|---|
| 浮动大小/轻微摆动 | config/motion.json → boat.heave_px、sway_px、roll_degrees |
| 速度/周期 | motion.loop_seconds；运行相位与导出长度共用此值 |
| 水面流动、亮纹、夜间幅度 | motion.water |
| 接触波纹 | motion.contact |
| 昼夜光色、灯窗、光晕 | config/time_profile.json |
| 局部光源位置/范围 | config/attenuation_config.json |
| 既有地面/窗灯区域 | config/finish_config.json |
| 轮廓、法线和全景区域 | config/scene_config.json |
| 船体与固定前景边界、补底和运动包络 | config/harbor_layout.json |

常规运动上限限定在已检查的微幅范围；超出时拒绝渲染，需要重新检查遮挡和补底，不静默放宽。

## 本轮港口效果
船体、桅杆、索具与窗灯同步微浮动；码头、前方立柱和栏绳固定。水面有低幅采样流动和克制亮纹，船边少量波纹随动，夜晚强度降低。没有添加树风、落叶、鸟、烟或新的场景物件。

受光先由同一母图与S6材质实时计算，动态层随后采样该结果。没有从固定日景/夜景各抠一艘船，因此船舱窗与船体共享同一运动变换和当前时段。

补底使用邻近已有水面像素，遮挡后的船身使用可见船身像素小范围补齐；目标仅为本轮微幅浮动可能露出的区域。完整隐藏区域并非新绘制的空港口。系缆以有限幅度随船，靠码头端由固定前景遮挡，没有绳索物理模拟；没有真实动态倒影或完整水体模拟。

## 交付核对
- 原母图SHA256保持 `71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02`。
- 封装后重建的工作底图、地表、法线、打包控制图、窗灯/光晕、RGBA32F光场与S6逐字节相同。
- 关闭动态的白天和夜晚，与S6相应GPU截图逐像素相同。
- 白天和夜晚各144个实际GPU帧，6秒24 FPS；循环同一端点的最大通道差为1/255，固定码头和动态范围外最大差为0。
- 原生XCF已保存重开：原母图像素与保护锁定保留，四张控制蒙版数值一致。
- S6 的25个已记录源文件保持不变。
- 没有新增/运行测试套件；以上是本轮文件、像素、渲染输出和原生文件重开核对，不能称为完整游戏测试通过。

## 原生文件与复现
`MainMenu_Harbor_Working_v06.xcf` 保存原图保护层、必要部件、补底、控制层、真实静帧和UI。编辑部件前关闭40_GPU_REFERENCES。手工编辑不会自动回写JSON或UV映射，重建前另存。

代码说明见源码 README.md。交付包包含 pipeline_source，可以用包内入口指定解压工作目录：

```powershell
python pipeline_source/menu.py all --workspace . --tools-config C:\Dev\Tools\ArtControl\config.json
```

当前本机入口：
```powershell
python C:\Dev\PvZ\PVZ-Adventure\tools\art_bake\main_menu\menu.py all --workspace C:\Dev\Tools\ArtControl\runs\main-menu-stage7-harbor-20261112 --tools-config C:\Dev\Tools\ArtControl\config.json
```

runtime/是执行副本，不是第二份源码。reports中的缓存/输出核对记录可重新生成。只改参数时仍应在新工作副本保留当前已审版本。

## 当前边界
尚未替换正式菜单或接入真实入口交互，没有读取玩家存档，没有本机时钟绑定。清晨/昼夜完整日周期及其他环境动态尚待后续。制作代码不会作为生产游戏的绝对路径依赖。
GIMP 3.0.4 退出时仍有既有 g_object_unref 告警，保存/重开检查成功，未隐藏告警。字体仅用于预览标题栅格化，不打入交付包。
