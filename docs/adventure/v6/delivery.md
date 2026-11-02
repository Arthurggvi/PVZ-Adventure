# 主菜单 v6 与城镇音乐交付

2026-11-02。本轮从 4f52912 开始，工作区初始干净。

## 实装与文件清单

- project.godot：主场景改为 res://scenes/main/01StartMenuV6.tscn。
- scenes/main/01StartMenuV6.tscn：按照 v6 layout 的 1920×1080 坐标建立可编辑分层场景。独立环境、接触阴影、四主体、码头前缘、水纹、四木牌和四 Label，未使用预览或示例文字图。继承原 01StartMenu.tscn 以复用原生 User、设置、帮助、退出及相关信号，旧美术隐藏。
- scripts/ui/start_menu/main_menu_v6.gd（及 UID）：画布统一等比适配；复用原玩家名 Label、原档案按钮并紧凑放入左上安全区，原辅助控件置于右下，原弹窗保持在美术上方。
- scripts/autoload/global/main_scene_registry.gd、scripts/adventure/zombie_island.gd：原菜单返回路径统一到 v6；地图播放城镇音乐。
- scripts/autoload/sound_manager.gd：新增 play_town_bgm()，使用现有 BGMPlay 和 play_bgm_if_changed()，设置 WAV 循环；不新增播放器，不修改音量总线。
- scripts/adventure/island_stage_button.gd：锁定节点 disabled、不可键盘聚焦；尚无战斗实现的第2关即使历史进度已开放也禁用交互，保留“已开放·待建设”文案和正常图片。只有既有草坪战斗可启动；解锁与通关状态仍来自当前玩家 progress。
- assets/adventure/main_menu/v6/：27 个实际素材/说明文件（24 PNG、layout.json、README、Godot_Integration）。项目安装目录原缺后两份说明，已从用户原下载包补齐。未加入 example_runtime_text_only、预览、ZIP 或整个原作素材库。
- assets/adventure/audio/mus_town.wav：仅从本地 FVM-Reborn/sounds/mus_town/mus_town.wav 复制指定一首，未修改参考库。SHA256 为 FBAF0522CF9112690FE1E28AA7D3014AB1668ED29418377BCCF41FE6B23BC0E1，与源文件一致。
- tests/adventure/test_menu_v6.gd（及 UID）、test_menu_v6.tscn：本轮图形、输入、音频及进度集成验收。
- docs/adventure/v6/screenshots/：实际 Godot 窗口 1920×1080、1280×720、1066×600 截图；本记录。

未实现的家园、研究棚、补给车均禁用；主体灰度材质、木牌 disabled 贴图、灰色 Label 同时生效。不以草坪首通假装启用研究棚。即刻启航沿用原 open_adventure() 与原生 UserManager，不调用 start_new()、不改变存档格式、目录、赠卡或胜负语义。

## 已执行验证

本机 Godot 4.7.2，APPDATA 隔离到项目 .godot/v6-test-user，没有操作真实玩家存档。执行文件为 C:/Users/Arthu/Desktop/Godot_v4.7.2-stable_win64.exe（此前 console.exe 已不在本机，使用 GUI 可执行文件的 headless/日志参数）。

1. --headless --editor --path <项目> --import：完成新贴图与 WAV 导入，无新增脚本解析错误。日志 .godot/v6-import.log。
2. --path <项目> --max-fps 60 res://tests/adventure/test_menu_v6.tscn --quit-after 9000 --log-file <日志>：实际图形运行输出 `PASS: v6 three resolutions, disabled input, native profiles, town continuity, volume/mute, battle and victory return`。最终日志 .godot/v6-verified.log 无 SCRIPT ERROR、Assertion、FAIL。
3. 三个真实 Window.size 分辨率逐一截图，检查画布等比、四入口文本、透明图层和码头遮挡。截图均为真正分层场景渲染。
4. 对三块禁用牌面发送鼠标按下/释放与 ui_accept，验证仍在菜单且不能获取键盘焦点；检查对应主体材质、木牌 disabled 状态、文字颜色。禁用控件主动 grab_focus 的拒绝警告为该验收的预期结果。
5. 原生创建/选择 A、B、再返回 A：B 无卡且未完成引导，A 的冒险文件字节不变、已跳过戴夫不重复显示；所有存档仅在隔离目录。
6. 读取同一 BGMPlay 实例的 stream 和 get_playback_position()，验证菜单→地图→菜单不重置进度；实际 BGM 滑块控制原总线，静音与已保存的总音量在场景切换/切回玩家后保留。不同玩家仍沿用原生配置加载语义。
7. 实际进入既有草坪，等待正常战斗启动，确认音乐不是城镇曲目；沿用原调试清怪推进自然十波、点击真实奖杯，返回地图时城镇音乐恢复且正在播放。未直接写入通关标记。
8. --headless --script res://tests/adventure/test_island_progress.gd --quit-after 1000：状态持久化、幂等、备份和损坏保护输出 PASS。日志 .godot/v6-progress.log。
9. git diff --check 与暂存区检查通过。

测试早期发现并修正两处测试设置问题：音乐滑块路径漏了 Option；直接调整总音量后未调用既有 save_config，导致切回玩家正确恢复原保存值、与测试期望不符。最终测试通过原配置服务保存后核验，未为迎合测试改变原生配置机制。

## 限制与复查

原工程仍报告部分原版资源 UID 警告及僵王贴图缺失；不是本轮新素材错误。未补入来源不明的原版素材，也未更改无关战斗模块。本轮图形与音频状态均实际运行；音频文件身份通过源文件 SHA256 核对，播放连续性以播放器实时位置验证，未宣称进行人工听音或无调试辅助的完整通关。

若人工复查，直接 F5：左上角原生档案按钮选择玩家；即刻启航进入原进度；设置/帮助/退出为原控件。其他三处入口及地图未实装战斗均不可进入。音乐通过原 BGM 总线控制，主菜单和地图间保持连续。
