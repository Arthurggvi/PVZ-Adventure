# S8｜统一风场下的树冠、船旗与遮阳棚

> S8已获用户通过，作为后续[9A建筑交互](main_menu_entries_pipeline.md)的视觉基线，不能顺带重调。

## 先看预览
- previews/day_wind_full.mp4、night_wind_full.mp4：完整昼夜场景，各6秒、24 FPS。
- previews/day_wind_details.mp4、night_wind_details.mp4：两处树冠、遮阳棚与旗帜四格近景；没有放大运动幅度，只放大实际裁切。
- previews/wind_detail_loop.gif：日间近景循环，来自实际GPU帧，GIF仅作手机快速查看。
- previews/full_day_night.jpg、day_wind_preview.jpg、night_wind_preview.jpg：全景静帧。
- previews/wind_on_off.jpg：相同港口相位下，只关闭/开启本轮新增风动。
- previews/awning_matte_review.png：黑/灰/白底原像素布料边缘检查。

没有调用生图工具，没有新增景物、粒子、鸟、烟或重画船体。S7B港口已获用户通过，本轮保留其资产、幅度、时段受光和固定遮挡。

## 当前范围
树冠：左上和图书馆后方的叶面内部轻微风动；外轮廓、树干、枝干与建筑接缝固定，不宣称整棵树或树冠外轮廓在摆动。
遮阳棚：沿墙上边与两侧支点固定，自由外沿轻微起伏。布面从原图提取，窗户/门灯/支架保持原位；轮廓窄带只用已有背景像素修补，没有生成新背景。
船旗：旗杆根部固定在船坐标中，自由端响应风；之后统一继承已通过的船体变换，不叠加第二次船位移。船身、索具、码头和水面沿用原行为。

## 权威代码、数据与复现
代码：`tools/art_bake/main_menu`。统一入口仍为 `menu.py`。
工作目录：`C:\Dev\Tools\ArtControl\runs\main-menu-stage8-wind-20261112`。
原母图：1672×941，SHA256 `71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02`。

管线：
`已认可基础/港口 → wind_assets（新增控制与原像素布料） → 同一lit_view受光 → land_wind（树冠/棚） → harbor（已通过港口＋船局部旗帜） → 独立UI`

- wind_field.gdshaderinc：唯一公共风场函数，传入显式秒数计算，不读系统TIME、不生成随机计时器。
- wind_layer.gd：同一配置/时钟注册两个材质，各部件只提供幅度、锚点、周期倍频和响应相位。
- land_wind.gdshader：内部树冠采样与固定边布料合成。
- harbor.gdshader：沿用港口合成；旗帜先在船局部空间变形，再整体继承原船变换。
- wind_assets.py / cloth_matte.py：语义约束、颜色选区、封闭布面和透明边缘去底色；不把粗多边形直接当透明边缘。
- wind_previews.py：只裁切、排版、视频/GIF编码与本轮输出核对，没有生成式插帧。

`runtime`始终是自动部署执行副本，不可当第二份权威源码。S7B历史工作目录未修改；没有Wind配置的历史目录仍走原港口流程。

## 调参入口
| 想调整什么 | 文件/字段 | 需要重建什么 |
|---|---|---|
| 整体启停/强度/风向/阵风 | config/wind.json → enabled、field | 只重新渲染 |
| 风场周期 | wind.loop_seconds | 只重新渲染；连续预览长度在pipeline.capture.duration_seconds |
| 两处树冠幅度与相位差 | wind.canopy | 只重新渲染 |
| 遮阳棚幅度、传播和响应 | wind.awning | 只重新渲染 |
| 旗帜幅度、传播和响应 | wind.flag | 只重新渲染 |
| 叶面范围、树干排除、保边距离 | config/wind_layout.json → canopies、leaf_selector | 只重建wind资产及依赖预览 |
| 布料边界/固定线/侧支点 | wind_layout.awning | 只重建wind资产 |
| 船旗根部与选择范围 | wind_layout.flag | 只重建wind资产；不要覆盖已通过整船 |
| 时段、地面、局部光 | 原time_profile/finish/attenuation配置 | 保持之前的职责和依赖 |

各部件可以独立关闭。新增风关闭后应回到同相位已通过的S7B港口，不是关闭整个场景。两处树冠与布料共享风场但有不同响应相位，不同幅同相摆动。
最大幅度受wind.limits限制；超过已整理的轮廓/补底包络要重新审查，不能只放宽上限。

## 透明度、固定端和颜色约定
树冠权重只在绿色叶面内部生效，距原轮廓留有安全边界；树干、屋顶和固定接缝明确排除。
遮阳棚先以颜色/区域分离，再保留原黑描边、反解边缘底色；轮廓窄带修补只服务本轮微动。贴墙线与两侧固定点在布料局部坐标下约束，不能拖动侧支架。
船旗在原像素中先分为flag_premult和boat_without_flag，两者预乘颜色在线性采样前完成分配，避免在采样后硬相减造成旗杆接缝。
所有新布料运行数据为RGBA32F预乘颜色；光照参考UV仅继承当前对应材质受光，不用三套昼/暮/夜布料贴图。

## 原生工作副本
`MainMenu_Wind_Working_v08.xcf`：锁定母图、既有港口部件、新增风控制、原像素遮阳棚与旗、实际渲染参考和UI。共11张原生控制蒙版保存/重开检查；其中4张属于既有港口，7张属于本轮风动。
编辑前关闭40_GPU_REFERENCES；截图不是实时参数。XCF手工修改不会自动回写JSON/浮点图，重建前先另存并确定导回路径。原生蒙版继续按Y u8数值存取。

## 执行方式
先复制工作目录保留已认可基线；依赖已经接通的ArtControl，不安装新软件。

```powershell
$entry='C:\Dev\PvZ\PVZ-Adventure\tools\art_bake\main_menu\menu.py'
$work='C:\Dev\Tools\ArtControl\runs\main-menu-stage8-wind-20261112'
$tools='C:\Dev\Tools\ArtControl\config.json'
python $entry all --workspace $work --tools-config $tools
```

可单独执行build/render/preview/workfile。普通风动参数不进入技术贴图缓存键；改变区域或选择方法时缓存会重建wind资产，不重跑已通过灰度、法线或港口。
交付包的pipeline_source也可作为同一入口；字体仅用于标题栅格化，不打包字体文件。

## 验收依据与局限
本轮核对：源图与已通过港口文件哈希、关闭新增风动的同相位对照、两种时段各8个关键相位、固定端与作用域外像素、循环端点、288个实际GPU帧、黑/灰/白底、XCF保存重开。最终记录见reports/delivery_checks.json、wind_assets.json、workfile.json和render.json。
这些像素指标只能证明操作受控，不能替代对动态观感和边缘的人工审查。S8已获用户通过，后续交互需保持关闭新增效果后的同相位基线一致。
没有新增/运行测试套件，未启动生产游戏、未读写玩家存档；本机时间绑定、完整清晨到夜晚闭环、最终入口UI与交互仍未做。
GIMP既有退出告警保留，输出保存/重开结果单独记录。没有给原画新增动态阴影、真实风力物理或三维布料；受光随原像素采样保持一致。

官方接口参考（只作为材质接口依据，不作为本项目验收证据）：
https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html
