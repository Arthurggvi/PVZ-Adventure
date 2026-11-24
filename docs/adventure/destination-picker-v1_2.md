# 地区选择 v1.2 首次完整实装

2026-11-03；施工前 HEAD：6fe13d4；原工作区干净，直接在用户指定工程 develop 中施工。

## 审计与实际范围

原工程只有 V8 → AdventureSession.open_adventure() → zombie_island.tscn，没有地区选择器。V8 继承 V6 / StartMenuRoot，F5 和主场景注册表均已指向 V8。原冒险入口按原生当前玩家读取 user://<玩家>/adventure/zombie_island_v1.json，仅缺档初始化；坏档拒绝。地图原返回路径直达 V8。

安装器核对 v1.2 下载包与工程目录：New=0、identical=12、total=12。资源已安装但原被 assets 忽略规则排除；本次将 layout.json 和 11 张原始 PNG 精确纳入版本管理。未替换或生成美术，未加入概念 JPG、ZIP、导入缓存或其他版本资源。

本次才建立的模块：

- scenes/adventure/AdventureDestinationPicker.tscn、scripts/adventure/adventure_destination_picker.gd：独立纸图、遮罩、关闭、错误弹窗、目录卡片装配、显式焦点环与等比安全区。
- scenes/adventure/DestinationCard.tscn、scripts/adventure/destination_card.gd：可复用预览 → 禁用层 → 完整相框 → 交互状态 → 名称组件；使用项目中文主题。字体原生最小行高 35px，采用 188×32 的固定 NameBounds 安全框及居中 Label，保持配置字号 26 和文字中心。
- scripts/adventure/destination_catalog.gd：唯一 v1.2 JSON 适配，校验资源、完整矩形、重复 ID 与交叠；开放配置与代码路由注册必须同时满足。仅 zombie_island 注册，town 没有可进入路由。
- scripts/ui/start_menu/main_menu_v8.gd：开始冒险挂载单实例选择器；关闭回收并恢复原菜单输入和焦点。选择僵尸岛后调用原 AdventureSession.open_adventure()，错误显示在选择器。没有新 Autoload、存档管理或音乐播放器。
- tests/adventure/test_destination_picker.gd、.tscn 和对应 UID：本轮定向技术验收。
- tests/adventure/test_island_flow.gd、test_adventure_entry.gd、test_menu_v6.gd、test_menu_v8.gd：仅同步经过 V8 的新地区选择步骤，保留旧 V6 直达语义。
- docs/superpowers/plans/2026-11-03-destination-picker.md 及本文：实施与交付记录。

## 实际测试结果

使用本机 Godot 4.7.2，所有运行 APPDATA 位于工程 .godot 下的隔离目录，未使用真实玩家存档。

1. RED：新场景不存在时定向测试明确失败；实现后通过。
2. 隔离编辑器导入退出 0，无 ERROR / SCRIPT ERROR。桌面引擎初次导入的设置 Safe save failed，已通过工程内现成 .godot/tools/isolated-godot/Godot.exe 及其 _sc_ 配置重跑解决，未改系统设置。
3. 图形进程 test_destination_picker.tscn 退出 0、PASS：真实点击 V8 冒险按钮打开选择器；重复按钮请求只保留一个实例和一组信号；Tab 焦点环不落到底层，点击底层设置按钮无效。
4. 鼠标悬停/按下状态、释放进入真实僵尸岛、Enter 焦点确认通过；城镇 disabled / FOCUS_NONE，鼠标、Enter、Space、手柄 A 和伪造 town 选择意图均不能进入。测试主动尝试给禁用控件焦点会产生预期的 can't grab focus 警告。
5. X、ESC 两次往返保留同一菜单实例、玩家与身份文件、焦点，无残留层；1066×600、1280×720、1920×1080、1024×768 窗口下，纸张、完整两卡和关闭按钮均在视口内，画布等比；逻辑卡片与名称安全框位置符合配置。
6. 打开/关闭不创建冒险文件，不重写全局存档或当前玩家配置。选择僵尸岛才首次初始化并触发原引导；完成引导并准备已有解锁状态后重新进入，存档字节不变、第二关仍开放、引导不重播。损坏测试档拒绝进入、明确提示、原字节不变。
7. 单一既有 BGM 播放器和城镇曲目身份保持，播放位置连续；另运行既有 test_menu_v8.tscn，退出 0、PASS：原生 A/B/A 档案、音乐连续、音量/静音、设置/帮助及退出回调通过。
8. git diff --check 通过；project.godot、AdventureSession、IslandProgress、僵尸岛地图、SoundManager、UserManager、SaveService 和环境 FX 均未修改。

日志：.godot/picker-red.log、picker-import-isolated.log、picker-final.log、picker-v8-regression.log。没有运行旧战斗/截图套件、全量无关回归，也没有截图、录屏、GIF 或模型审美验收。

## 复核、边界和阻断

一次独立只读代码审查未发现 Critical、Important 或 Minor 问题。保留当前范围的工程判断：未实现地区先禁用；正常包有效，布局损坏只报错并允许 ESC 返回；菜单在模态期间暂停处理；原安全入口内部错误、旧存档与音乐实现继续归原模块负责；不扩展这些模块。

无本次功能阻断。仍有原工程既存的旧资源 UID 回退/重复警告；测试强制聚焦禁用控件的警告是预期结果。视觉观感、卡片位置、文字及动画质量由用户实机验收。

实机入口：F5 → V8「开始冒险」→ 纸图；僵尸岛进入已有地图，城镇保持锁定，X/ESC 返回原 V8；地图返回仍沿原路径直达 V8。
