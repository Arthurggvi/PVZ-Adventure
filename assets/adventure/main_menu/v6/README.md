# PVZ-Adventure 主菜单美术资源 v6（装配候选包）

## 用途与范围

基于本轮全新生成的 9 张独立素材制作。仅包括**美术和 UI 装配数据**；不修改原 Godot 工程、不包含游戏逻辑、不触及任何存档。

- `background/coastal_yard.png`：**纯底图**，无房屋、研究棚、补给车、船、按钮或菜单文字（保留环境里的码头、树木、草地、围栏和灯塔）。
- `subjects/`：**4 张独立 RGBA 透明 PNG**：房屋/开放院子、冒险船、研究棚、补给皮卡。
- `buttons/*_blank.png`：**4 张独立、无功能名的 RGBA 木牌**。
- `buttons/states/`：各入口独立的 hover / pressed / disabled 状态图，来自同一木牌的程序化亮度/饱和度变体；均无功能名。
- `overlays/contact_shadows.png`：地面接触阴影，独立透明层。
- `overlays/dock_foreground.png`：由纯底图原位抽取的码头前景遮挡层，用于使船位于码头背后；独立 RGBA PNG。
- `overlays/ship_waterline_ripples.png`：可选轻水纹透明层，已避开木码头。
- `overlays/example_runtime_text_only.png`：**仅演示用**的独立文字图层；Godot 正式集成应使用 Label 动态显示四个中文功能名。
- `layout.json`：主场景 1920×1080 逻辑坐标与各 PNG 的实际位置/大小。
- `previews/`：实际由独立 PNG 合成的四入口菜单预览，包含三种分辨率和一张无字版；不是 AI 画的“展示板”。
- `qa/`：质量检查、文件尺寸、透明度与 SHA256 校验信息。
- `docs/Godot_Integration.md`：给 Codex 的场景装配说明。
- `install_to_godot.ps1`：安全复制美术资源到项目内的版本化路径，不改动存档或已有主菜单文件。

## 入口与文字

| 入口 | 屏幕位置 | 牌面文字 | 导航预期 |
|---|---|---|---|
| 家园 | 左上 | 家园 | 花园/家园（尚未实装的功能由原项目规则控制） |
| 补给车 | 左下 | 补给车 | 仓库/商店，具体功能仍待确定 |
| 研究棚 | 中下 | 研究棚 | 合成、强化、配方（当前阶段未实装） |
| 即刻启航 | 右侧 | 即刻启航 | 从原生左上角**当前玩家**的冒险存档继续/首次进入，禁止覆盖存档 |

**不提供新玩家选择器**。原版玩家档案选择、设置、帮助和退出控件应从原项目 UI 保留并置于这组美术之上。主菜单不应出现开始/继续二选一重置弹窗。

## 安装

在 PowerShell 中进入解压目录后执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install_to_godot.ps1 -ProjectRoot "D:\Dev\PvZ\PVZ-Adventure"
```

资源会创建于 `D:\Dev\PvZ\PVZ-Adventure\assets\adventure\main_menu\v6\`，相应 Godot 路径为 `res://assets/adventure/main_menu/v6/`。若该版本目标已存在，安装脚本将拒绝覆盖，以保护已有修改。

## 技术和视觉限制

- PNG 可直接作为 Godot TextureRect / TextureButton 贴图使用；**尚未经用户机器上的 Godot 导入、点击交互与存档回归测试**。
- 船帆、车轮、门和船体目前各自仍在**一个主体 PNG 内部**；不支持独立机械摆动。船体整体浮动可在 Godot 做轻微 Tween；不应把不存在的子层宣传为已提供。
- 本版是**独立素材包与合成演示**，不是 Godot `.tscn` 工程，也不包含中文字体文件。
- 本项目为非商业同人游戏；如果公开分发，应另外确认原作元素、名称和二创使用权。
