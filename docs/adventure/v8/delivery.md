# v8 全量菜单接入

基线 af5fc84；工作区初始干净。本轮按完整任务施工后，依最新精简附件收尾，不再截图、录制或等待动画。此前生成的证据留于忽略的 .godot/v8-prior-full-evidence，不纳入交付素材。

## 关键文件

- scenes/main/01StartMenuV8.tscn：完整分层菜单，保留 v6 背景、四主体、木牌及码头水线；四张 v8 阴影按1920×1080整幅对齐，替代旧整体阴影以免堆黑。车辆围栏草、岸边草在主体上层；功能台岩石透明度降至0.35，避免厚重灰色底座。乌鸦低于所有按钮与文字。
- scripts/ui/start_menu/main_menu_v8.gd：继承现有 v6 适配与音频逻辑，仅替换原生玩家牌外观、调整长中文名，并隐藏旧辅助按钮。新功能台沿用原选项、帮助、退出回调；旧家园、补给车程序入口也保持禁用。
- project.godot、scripts/autoload/global/main_scene_registry.gd、scripts/adventure/zombie_island.gd：主入口及菜单返回路径统一至 v8，不修改地图、音乐和存档业务。
- assets/adventure/main_menu/v8/：显式跟踪32个必要资源及来源文件。19张增量UI/阴影/前景、布局；乌鸦场景/脚本/UID、四帧与来源清单，以及四张获准的原始姿态。其他未用姿态、预览、ZIP、参考库未强制加入。
- tests/adventure/test_menu_v8.gd、.tscn：相关入口、原生玩家、辅助回调、音乐与音量自检；最终精简版不生成截图/GIF，也不等待飞掠或测试未改动战斗。

## 资源与安装

资源已全部落盘，未重新执行安装脚本，没有覆盖现有PNG。乌鸦已启用，仅一个 CrowFlyby 实例，约7fps，首次3秒、后续随机14～26秒；末段淡出，隐藏时不接收GUI输入。四帧来自本机原始 pose_16→24→17→18，不是拼图低清替代。源哈希与清单一致，并在临时目录用原构建器重新生成后逐像素匹配四帧；未改写运行帧。时序为项目自制，不是官方原始动画序列。

## 实际技术检查

- Godot 4.7.2：`--headless --editor --path <项目> --import` 完成。桌面可执行文件的编辑器首次报告 Safe save failed；使用同一可执行文件在项目 .godot/tools/isolated-godot 的独立编辑器目录重跑成功，无该错误或脚本解析错误。没有修改系统设置。
- 最终场景加载：`--headless --path <项目> --quit-after 8`，退出0，无脚本或场景加载错误。
- 最终相关测试：`--path <项目> --resolution 1066x600 --max-fps 60 res://tests/adventure/test_menu_v8.tscn --quit-after 2000`，隔离 APPDATA，输出 `PASS: v8 callbacks, disabled entries, native profiles, shared town music and volume`。验证禁用输入与旧程序入口、原生A/B切换及长中文名、新功能台选项/帮助鼠标悬停/按下/回调与退出、冒险文件字节不变、赠卡不重复、城镇播放位置连续、音量/静音保留。
- 在精简附件前，完整图形版本也实际执行过三分辨率、两次正式间隔飞掠及原草坪胜利返回回归，日志记录PASS；本记录不将其解释为主观视觉验收。
- `git diff --check` 通过。鼠标悬停断言需要图形视口，Headless运行该交互测试失败，不计为通过；最终以图形模式复核通过。日志位于 .godot/v8-import-isolated.log、v8-final-entry.log、v8-lean-verified.log；帧源复核为 v8-frame-source.log。所有测试档均位于项目隔离目录，未操作实际玩家存档。

无本轮未解决技术阻断；仍有旧资源UID警告。视觉观感、阴影遮挡及飞掠效果由玩家启动游戏验收，不作主观结论。没有修改 UserManager/SaveService、mus_town.wav、六关地图、战斗或经济系统。
