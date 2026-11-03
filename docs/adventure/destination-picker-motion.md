# 冒险界面开关与场景过渡

2026-11-03；基线 d200db6；在原指定 checkout 上施工，起始工作区干净。

## 表现与封装

- 纸图展开：0.26 秒，透明度 0→1、倍率 0.96→1、轻微向上归位，Cubic Ease Out。
- 纸图收起：0.18 秒，轻微下移/缩小并淡出，Cubic Ease In；背景遮罩同步淡出。
- 进入僵尸岛、地图返回 V8：0.16 秒覆盖，目标场景 0.18 秒揭幕；F5 初次菜单也柔和揭开。

`scripts/ui/transitions/modal_motion.gd` 与 `scenes/ui/transitions/ModalMotion.tscn` 为可复用弹层组件。target 指向专用表现 Control，backdrop 可选；open_seconds、close_seconds、hidden_scale、hidden_offset 在 Inspector 调整。play_open / play_close 及 opened / closed 信号描述生命周期；快速取消会先终止旧 Tween，关闭中重复请求不会叠加。Picker 的 MotionRoot 承担动画，子级 DesignCanvas 仍由原 _fit_canvas 管理适配，互不争用位置或倍率。

`scripts/ui/transitions/scene_transition.gd` 与 `scenes/ui/transitions/SceneTransition.tscn` 为每场景单实例遮幕。run(action) 在覆盖后只执行一次明确注册的 Callable；change_scene(path) 封装原场景切换。动作返回 bool / Error，且必须真正离开原场景才被视为成功；失败发出 transition_failed 并揭幕恢复。cover_seconds / reveal_seconds 可在 Inspector 调整。没有 JSON 执行、全局 Autoload、常驻对象或额外播放器。

Tween 都绑定组件并在销毁时终止，使用真实时间且独立于暂停/游戏速度。过渡期间屏蔽鼠标、键盘及手柄确认，入场中 ESC 可立即取消；纸图完全展开才恢复焦点。导航失败由 Picker 的 recover_navigation_error API 恢复交互并保留原入口给出的具体错误，菜单不访问内部错误窗口。

## 实际改动

- 新增上述两个组件的脚本、场景与 Godot UID。
- `AdventureDestinationPicker.tscn` / `adventure_destination_picker.gd`：新增独立表现容器、输入屏障和开关生命周期；目录数据、卡片美术、布局坐标不变。
- `01StartMenuV8.tscn` / `main_menu_v8.gd`：挂载场景遮幕，经遮幕调用原安全入口；切换失败恢复界面和本次会话锁，不改进度对象或文件。
- `zombie_island.tscn` / `zombie_island.gd`：挂载同一遮幕，返回菜单的直接调用改为组件调用；地图、关卡、引导、存档和音乐业务不变。
- 既有 `test_destination_picker.gd`：补充动效与失败恢复验收；四份旧入口测试同步节点路径和实际动效状态等待，不依赖任意长延迟。
- 实施计划和本交付记录。

## 定向验收

Godot 4.7.2，所有测试使用工程 .godot 下隔离 APPDATA，未操作真实玩家档案。

- 缺少动效组件时先 RED；实现后定向图形验收 PASS。
- 入场中真实 ESC、重复关闭、动画中调整分辨率；入场完成后位置、倍率和透明度精确归位。
- 开关中选择被拒绝，不创建进度；最终卡片、焦点、完整矩形及 1066×600 等既有适配测试保留。
- 菜单 → 纸图 → 真实僵尸岛 → V8；新档首次初始化、已有解锁和存档字节保持、坏档拒绝、音乐连续与原生身份保持。
- 独立审查发现旧冒险入口可能返回成功却未真正切场景。回归测试先复现永久遮幕 RED，修复后验证自动揭幕、重复请求拒绝、会话锁和界面输入恢复、明确错误提示。正常切换会立即将旧场景移出树，因此组件在动作前保存 SceneTree 引用再判断切换结果。
- 既有 V8 回归保留 A/B/A 玩家切换、设置/帮助/退出回调、音量/静音和音乐连续性检查。
- 隔离编辑器导入退出 0；最终运行日志无 SCRIPT ERROR / ERROR / Assertion / FAIL。git diff --check 通过。

日志：`.godot/motion-import.log`、`motion-failure-red.log`、`motion-picker-delivery.log`、`motion-v8-delivery.log`。初次 headless RED 探针曾同时报告原环境 ShaderCompiler 条件错误，最终实际图形进程未复现；没有修改环境 shader。既有 UID 回退警告和测试主动聚焦禁用控件的预期警告仍在。

未改 project.godot、AdventureSession、IslandProgress、原生 UserManager / SaveService、SoundManager、layout.json、PNG 或环境 FX。无本次功能阻断；动效节奏和视觉观感由用户实机验收，未制作截图、录屏或 GIF。
