# 9A｜建筑悬停、点击进入与返回（候选验收）

## 先看预览
- `previews/building_interaction.mp4`：真实GUI输入录像，包含昼夜悬停、打开图鉴/研究室/地图、关闭返回、未开放/未解锁、UI阻挡、拖出取消、键盘Enter。
- `previews/night_building_hover.mp4`：夜间悬停短段，便于单独看高亮强度与船/布料同步。
- `previews/hover_day_night.jpg`：白天图书馆、夜晚研究室。
- `previews/real_function_windows.jpg`：点击后真正打开的原游戏窗口，不是绘制的占位界面。
- `previews/locked_and_unavailable.jpg`：未解锁研究室和未开放商店分别说明。
- `previews/layout_*.jpg`：改变原生窗口尺寸后的实际绘制，黑边/视口与窗口像素分别记录。

本轮没有生图。母图、已有昼夜光照、港口与风参数沿用已通过的S8。正式启动仍为原来的01StartMenuV8，完整日周期和本机时钟属于9B，本轮不实施。

## 入口对应关系与真实状态
| 场景对象 | 功能 | 本轮行为 |
|---|---|---|
| 图书馆 | 冒险图鉴 almanac | 有效档案可打开原有模态窗口 |
| 研究室 | research | 原任务“初次远征”领奖后开放；复用原研究室与条件 |
| 港口/船 | map | 同一个冒险地图入口，只打开地区选择，不自行启动关卡 |
| 家 | home | 尚未开放；不跳回旧花园，也不擅自改成玩家面板 |
| 商店 | store | 尚未开放；不绕过状态打开旧商店 |
| 戴夫皮卡 | 无 | 保留场景对象，不添加第二个商店/任务入口 |

悬停只显示高亮和名称；鼠标左键同一目标按下释放才进入。移动到空地释放取消；按下后出现上层界面时，释放仍需核对实际最上层控件，不能因鼠标捕获而穿透。可用入口用温和提亮/内侧边强调，不缩放建筑、不持续闪烁。锁定/未开放弱反馈且明确原因。键盘焦点复用同一表现，Enter经过同一打开门面。

## 权威源码与所有权
**功能唯一入口**：`scripts/adventure/ui/toolbar_entry_host.gd`（由原toolbar_controller继承）。
- `feature_status(feature_id)`：查询已注册的真正解锁条件与当前宿主/模态状态。
- `request_feature(feature_id)`：提交时再次核验，再调用原功能构造/导航；工具栏与建筑共用。
- `scene_entries_blocked()`：阻止背景建筑在窗口、导航、暂停或教学遮罩上方继续响应。
原 `_hooks`、`_modal` 与释放流程被移到同一基类，不存在第二份模态管理器或解锁存档。控制器仍拥有宿主场景、地图导航和教学编排。研究室、地图旧公开入口转到同一门面。

**建筑输入**：`scripts/ui/start_menu/building_entry_hit.gd` / `building_entry_layer.gd`。
- `_has_point` 使用稳定原画坐标多边形，排除皮卡等对象；不追随细索具每帧漂动。
- 原生GUI路由决定最上层目标，档案框/工具栏/弹窗不穿透；图像层和说明标签不抢鼠标。
- 输入层只接收显式注入的状态/请求/阻塞Callable，不创建窗口或复制玩家状态。
- 教学虽不属于普通模态，也通过quest_onboarding.blocks_scene_entries只读查询阻止背景键盘/鼠标；不破坏教学本来允许点击的工具栏目标。

**高亮表现**：`tools/art_bake/main_menu/godot/entry_highlight.gd` / `.gdshader`。
- 顺序是同一实时受光 → 可选入口高亮 → 已有陆地风动 → 港口/船/旗 → 独立UI。
- 因而高亮沿既有采样/遮挡走，不另写一份船运动、布料位移或漂浮描边。
- 只画内侧强调，细索具不使用强描边，避免夜间变成闪白细线。
- 没有entries配置的历史目录直接走旧管线；高亮强度为零时透传原画面。

## 配置与调参
`config/entries.json`：唯一入口配置。
- `entries[].id/feature/name/title`：场景身份、业务功能ID、显示名称；不能在这里伪造功能解锁。
- `hit` / `exclude`：稳定命中轮廓与排除区域。
- `shape` / `exclude_green` / `include_boat`：可见高亮范围，由entry_assets构建；命中区与可见蒙版不是同一个概念。
- `anchor`：名称牌原画位置，与画布同一等比变换。
- `style.fade_in_seconds/fade_out_seconds`：可打断的进入/离开过渡；换目标时蒙版与强度同帧更新，避免闪亮。
- `fill_gain/inner_edge_gain/inner_edge_width_px/outline_min_width_px`：填色与内侧强调，细结构抑制；边缘宽度改变需重新构建蒙版。
- `available_color/locked_color/locked_strength/pressed_multiplier`：可用/不可用/按下反馈。
- `entries[].thin_structure_fill`：细结构填色比例；港口设为0，只强调有足够宽度的船身/船舱/码头，避免索具在夜晚成为亮虚线。

`entry_assets/{id}.png` 为R=可见作用范围、G=宽物体内侧边、B=0；`{id}_alpha.png` 用于原生蒙版查看。高亮贴图不携带解锁数据。手工编辑XCF不会自动回写JSON或运行纹理。

## 可复现入口与隔离演示
权威工具入口：`tools/art_bake/main_menu/menu.py`。
本轮资产目录：`C:\Dev\Tools\ArtControl\runs\main-menu-stage9a-entries-20261112`。

```powershell
$entry='C:\Dev\PvZ\PVZ-Adventure\tools\art_bake\main_menu\menu.py'
$work='C:\Dev\Tools\ArtControl\runs\main-menu-stage9a-entries-20261112'
$tools='C:\Dev\Tools\ArtControl\config.json'
python $entry entries --workspace $work --tools-config $tools
# 仅重排已录制真实帧，不再次启动游戏服务：
python $entry entries-preview --workspace $work --tools-config $tools
# 原生分层工作副本（依赖已有离线render输出）：
python $entry workfile --workspace $work --tools-config $tools
```

`entries` 自动构建必要入口数据、部署runtime、建立隔离工程并使用真实游戏服务录制。隔离manifest/user路径在工作目录的native_project中；资源目录链接原工程，仅复用资源与已导入缓存。**不要把native_project目录或其链接递归打包，也不要在其中运行额外editor导入。** 它不是可以脱离原游戏的独立发布包。

隔离 `user://` 使用 `PVZ-Menu9A-Isolated-20261112`。录制器通过原UserManager/SaveService建立演示档案，然后在该临时档案中设置任务/发现记录，分别展示真实已解锁和锁定路径。正式用户存档没有被复制、读取或修改；隔离目录本身会产生演示存档和日志。研究室演示档案没有材料，不声称合成/强化事务已验收；地区选择没有继续进入战斗。

实际UI由 `entry_preview_root.gd` 组合，`entry_record.gd` 只发送原生鼠标/键盘事件并截取视口；可见鼠标和右上字幕是录制标记。录制器鼠标移动使用Viewport.warp_mouse及视口坐标，不用窗口物理像素补丁。运行时真人鼠标仍走原生GUI事件。

头像/存档按钮和选项功能台沿用已认可的占位素材；本轮只保证其区域不穿透。工具栏、图鉴、研究室和地图导航为真实现有实现。最终头像动作、功能台按钮及主菜单整合归9B，不将它们冒充已经接入的最终UI。

## 验收边界与记录
`reports/entry_record.json`记录每个截图的实际hover、模态、导航、状态和接受/拒绝请求；`entry_delivery.json`只根据同次记录核对，不拿旧截图冒充新输出。
`native_record_environment.json`记录独立user目录、生产project哈希、未替换正式启动、原生错误状态。
本轮核对真实打开/关闭、UI与教学阻挡、锁定拒绝、拖出取消、按下后被前景盖住再释放、键盘Enter、不同窗口比例、母图和已通过资产哈希。按AGENTS没有新增或运行游戏测试套件，不能写成完整回归通过。

`MainMenu_Entries_Working_v09.xcf`保留原始锁定母图、已有港口/风控制与五张建筑高亮蒙版、命中审阅图；原生显示层不是实时交互状态。高亮和进入的最终观感仍待用户验收。
未实施：完整清晨/昼夜与本机时钟、最终主菜单替换、未开放建筑业务、全部显示设备/移动触控适配、生产性能测量。

录制中的“前景界面”短段是明确标注的输入边界演示面板，不是新业务窗口。它在建筑按下后出现，用于确认原生鼠标捕获的释放不会穿透；图鉴/研究室/地图段仍是真正功能窗口。前后证据见reports/pointer_capture_guard.json及录制事件。
