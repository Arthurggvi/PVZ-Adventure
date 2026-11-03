# Adventure Destination Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. 本次由当前会话一次执行，用户明确免除分阶段确认。

**Goal:** 首次实装 V8 → 纸质地区选择 → 原僵尸岛入口，以及关闭返回同一 V8 实例。

**Architecture:** 独立可编辑 Picker / Card 场景；目录适配器读取唯一 v1.2 layout。V8 只负责挂载、回收和明确映射到 AdventureSession.open_adventure()；不改存档、地图、音乐实现。采用弹层是本次工程判断，可原样保留菜单与玩家上下文。

**Tech Stack:** Godot 4.7.2、GDScript、现有 island_ui 主题。

**Spec:** C:/Users/Arthu/Downloads/Codex_PVZ_Adventure_Destination_Picker_v1_2_Full_Implementation.md；用户本轮要求优先。

## Global Constraints

- 在 C:/Dev/PvZ/PVZ-Adventure 当前干净 develop 检出施工；不创建额外工作树。
- 当前只有 zombie_island 可进入，town 始终不可进入；JSON 字符串不能执行脚本。
- 唯一美术源 assets/adventure/destination_picker/v1_2/layout.json；1920×1080 等比缩放，最低 1066×600。
- 不新增 Autoload、存档、播放器，不改地图/战斗/进度/环境 FX；开关界面不写盘。
- 不截图、录屏、GIF、审美验收或无关全量回归；只运行定向技术验收。
- 变量、常量、函数按 AGENTS.md 加中文用途注释。

## Review Focus

- 重复点击和重复开关不能堆叠界面或连接；实际两次往返测试。
- 禁用城镇以及伪造选择意图都不能进入；鼠标、键盘、手柄确认测试。
- 卡片完整边框和关闭按钮在小窗口与非16:9窗口内；几何边界断言。
- 新玩家开关不能创建进度，已有档案不能被重写，坏档必须原样拒绝；隔离 APPDATA 文件字节断言。
- 弹层必须阻挡底层菜单输入并保留焦点、音乐播放位置及原生玩家；真实输入与播放器身份断言。

### Task 1: 首次实现目录、卡片和选择界面并接入 V8

**Files:** Create scripts/adventure/destination_catalog.gd, destination_card.gd, adventure_destination_picker.gd; scenes/adventure/DestinationCard.tscn, AdventureDestinationPicker.tscn; tests/adventure/test_destination_picker.gd, .tscn. Modify scripts/ui/start_menu/main_menu_v8.gd.

**Interfaces:** Catalog.load_layout() 返回验证后的字典；Catalog.can_enter(destination) 实施代码注册的开放条件。Card.configure(destination, card_layout)；Picker.destination_selected(id)、close_requested 信号。V8 调用原 AdventureSession.open_adventure() 并在原弹层错误框报告失败。

- [x] 写定向真实场景集成测试，先确认缺少新场景导致 RED。
- [x] 检查原工程导入基线并记录已有资源问题。
- [x] 实现目录验证、独立卡片分层状态与运行时名称、Picker 等比布局及 ESC/X、V8 单实例弹层生命周期和受控路由。
- [x] 运行 Godot 导入和定向集成测试，修复本次错误直至 PASS；不运行旧战斗/截图套件。

### Task 2: 兼容测试引用、复核和交付

**Files:** Update tests/adventure/test_menu_v8.gd, test_menu_v6.gd, test_island_flow.gd, test_adventure_entry.gd 中经过 V8 的旧直达假设；docs/adventure/destination-picker-v1_2.md。

**Interfaces:** 原场景按钮仍使用 _on_button_1_pressed；旧测试需在 V8 点击后选择 zombie_island，旧 V6 直达路径保留。

- [x] 仅同步已失效的测试入口引用，不扩展其验证范围或运行昂贵战斗套件。
- [x] 完成一次独立代码审查和相关测试，检查 diff --check 及受保护文件未改。
- [x] 显式提交本次代码、测试、文档及 v1.2 唯一资源（不提交其他 ignored assets 或 import 缓存）；报告实际 Hash 和已知问题。
