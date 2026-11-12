# 港口动态返工 S7B｜通道分离、透明边缘与遮挡归属

## 状态与来源
上一轮 S7 港口动态已被用户退回，不能继续标为通过。本轮在独立目录重做，不覆盖原母图或 S6 已认可静态光照；旧 S7 保留作前后反例。

当前制作目录：`C:\Dev\Tools\ArtControl\runs\main-menu-stage7b-harbor-rework-20261112`。
权威代码：`tools/art_bake/main_menu`，单入口仍为 `menu.py`。
唯一母图 SHA256：`71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02`，1672×941。
没有调用生图，也没有新增船、柱子或道具。船体幅度/周期沿用原配置，没有靠降低运动幅度隐藏问题。

## 先看预览
- `previews/day_harbor_closeup.mp4`、`night_harbor_closeup.mp4`：6秒24FPS实际GPU近景，应优先检查。
- `previews/day_harbor_full.mp4`、`night_harbor_full.mp4`：全景动态。
- `previews/rework_before_after.jpg`：上为退回版、下为返工版，比较两个极限相位。
- `previews/harbor_day_night.gif`、`harbor_day_night.jpg`：昼夜并排循环与静帧；GIF量化不代替MP4验收。
- `previews/day_phase_review.jpg`、`night_phase_review.jpg`：每个时段8个实际相位及船底放大。
- `previews/matte_review.png`：黑/灰/白底透明边缘检查，不当作成品背景。

## 根因与本轮替换
旧实现的问题不仅是“多边形不够细”：固定层包含船身像素、舷内柱与船运动不一致，最近像素RGB映射把补底拉成条带，透明边缘还混着原海色。

旧的直接最近RGB补底和粗多边形整块回盖已从当前管线删除。替代链路：
1. 语义区域只限定搜索范围，色差通道负责海水/物体区分，明度辅助细索具。
2. 封闭船体保留蓝色窗户和涂装；窄trimap估计覆盖率，前景木柱用RGB方向判别，避免红船漆混入固定层。
3. 透明边缘反解原底色，运行资产使用预乘RGBA32F；颜色与alpha一起过滤。
4. 根据母图体积关系，舷内木柱归船体；码头前方栏柱和栏绳为独立固定前景，不用大范围遮挡块切船。
5. 被前柱挡住的有限船身区域，用同一涂色带取样和连续延拓补齐。补底的海水样本与码头样本分开，不让船漆/木柱污染海面。
6. 接触波纹从移动后的船底轮廓派生，不再用独立椭圆掩盖水线。

本轮背景重建仍只服务已限制的微幅运动；不能把 clean_plate 当作完整无船场景。移动幅度显著增加时，需要重新检查缺失区域，不能只放宽上限。

## 当前数据/渲染职责
`harbor_matte.py`：语义trimap、色差/明度/RGB判别、透明度、去底色与遮挡窄带连续延拓。
`harbor_assets.py`：调用统一选区方法，生成部件、背景、光照参考与预乘浮点纹理。
`scene_host.gd`：先渲染同一母图的当前受光，再供动态部件取样；UI仍独立。
`harbor.gdshader`：背景→移动船→固定前景的顺序合成，预乘透明处理；没有分别生成昼/夜船图。

资产格式：
- `boat_premult.rgba32f` / `fixed_premult.rgba32f`：H×W×RGBA小端float32，RGB已乘alpha；不能再乘一次alpha。
- `boat_light_uv.rgba32f` / `fixed_light_uv.rgba32f`：RG为对应材质的当前受光参考坐标。
- `clean_light_uv.rgba32f`：RG为海水/码头对应的受光参考坐标，B为补底范围。
- `clean_plate.png`：连续修补颜色，运行时随对应材质的当前受光比值变化；不直接用最近像素RGB替代背景。
- `harbor_masks.png`：R船、G固定前景、B水域权重、A补底范围。
- `boat.png` / `dock_foreground.png`：直通alpha查看/原生编辑版本；运行使用预乘float版本。

受光继承是固定视角和微幅移动下的近似；不声称重建完整三维几何或运动后真实阴影。窗灯与船一起变换，不固定在背景坐标。

## 下次怎么调
- 运动幅度/周期/水面/接触强度：`config/motion.json`，无需重做法线和地表。
- 选区范围、通道阈值、前后归属、遮挡区克隆与补底：`config/harbor_layout.json`（schema_version=2），重建港口资产。
- 昼夜参数：`config/time_profile.json`；其余基础配置仍按原职责。
- 缓存已包含 harbor_matte.py 源码依赖，调整选区算法不会误复用旧资产。
- 舊schema_version=1被明确拒绝；不能拿退回版配置运行新链路并误认为复现成功。

单入口：
```powershell
$entry='C:\Dev\PvZ\PVZ-Adventure\tools\art_bake\main_menu\menu.py'
$work='C:\Dev\Tools\ArtControl\runs\main-menu-stage7b-harbor-rework-20261112'
$tools='C:\Dev\Tools\ArtControl\config.json'
python $entry all --workspace $work --tools-config $tools
```

请先复制资产工作目录保留当前基线。runtime为执行副本，不是另一份权威源码。XCF手工编辑不自动回写JSON/浮点数据，重建前另存。

## 原生文件与审查原则
`MainMenu_Harbor_Rework_v07.xcf` 保存母图保护层、重做船/码头/补底、透明度/水域控制、实际GPU参考和UI。编辑前关闭参考组；GIMP蒙版继续用Y u8数值读写。

本轮检查黑/灰/白底、昼夜各8个关键相位、288个实际循环帧的完整性与连续性、固定柱关键位置、关闭动态与S6静态像素一致性、XCF保存重开及母图哈希。具体实测记录见 reports/delivery_checks.json、rework_review.json、workfile.json。

**范围外像素不变或循环数值一致，只能证明操作受控，不能证明拆层正确。** S7此前正是忽略了这一点；后续必须保留透明背景检查和实际遮挡相位复核，不以自动指标替代视觉审查。

未新增/运行游戏测试套件，未替换正式菜单，未读写玩家存档，未push。未新增其他环境动画或本机时间绑定。GIMP既有退出告警保留，保存/重开与数据核对单独记录。
