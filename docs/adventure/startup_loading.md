# 启动与场景加载：权威管线（2026-11-14）

本文件只定义正式资源拥有者、调用契约、故障行为及验收方式。Godot 4.7.2；不新增依赖。

## 一、唯一入口与职责

- `project.godot → scenes/main/00Bootstrap.tscn`：轻量首屏，不直接引用战斗、卡牌目录或海滨母图；由同一个 `SceneTransition` 进入 `01StartMenuCoastal.tscn`。
- `scenes/ui/transitions/SceneTransition.tscn` / `scripts/ui/transitions/scene_transition.gd`：**唯一**场景切换与加载显示组件。负责遮幕、输入锁、线程化资源请求、进度、成功交接及失败复原。地图、战场与首屏都必须复用；不另建页面专用 Loader。
- `SceneTransition.change_scene(path, after_switch=Callable()) -> bool`：返回值仅表示**已接受请求**，不代表切场完成。加载使用 `ResourceLoader.load_threaded_request` / `load_threaded_get_status` / `load_threaded_get`；完成后使用 `SceneTree.change_scene_to_packed`。仅确认 SceneTree 接受目标后调用 `after_switch`，其执行早于新场景的 `_ready`。
- `SceneTransition.transition_failed`：线程失败、非法资源或切场失败时使用；遮幕必须揭开、输入必须恢复。繁忙状态拒绝重复请求，不允许在失败路径清空战斗或存档。
- `SceneTransition.run(action)`：仅保留历史非场景动作兼容。**新增场景跳转一律走 `change_scene`**，禁止在遮幕回调中直接调用 `change_scene_to_file` 绕开异步管线。
- `coastal_menu.is_visual_ready()`：正式主菜单需先初始化多视口合成并可见，场景揭幕再等待两个真实渲染帧；禁止用固定秒数代替首帧就绪协议。

## 二、启动资产与延迟加载

| 公共门面 | 唯一资源拥有者及首次加载行为 |
|---|---|
| `AllCards` | `scripts/autoload/lazy_card_catalog.gd` 保留原五个方法；首次实际请求后才将唯一 `scenes/autoload/all_cards.tscn` 实例化并完成模板索引。任何调用方不得单独加载第二份卡牌目录。 |
| `Global.character_registry` | `scripts/autoload/global/character_registry.gd` 常量表仅存身份、标量、路径；`get_plant_info/get_plant_scene/get_zombie_info/get_zombie_boss_info` 对资源字段首次按需解析并缓存，原返回类型不变。禁止在静态映射重新放置场景/种植条件的 `preload`。 |
| `SceneRegistry` | `scripts/autoload/scene_registry.gd` 保持 `SceneRegistry.SUN` 等属性接口；路径表与统一缓存负责惰性获取 `PackedScene`。禁止新增重复全局资源目录。 |
| `SoundManager` | 五组 SFX 名称与随机候选只存资源路径；`_select_stream/_stream` 第一次播放时解析并缓存，现有总线和音效池不变；Boss 咆哮仅于首次播放时加载。 |
| `AdventureToolbar` | 工具栏控制器常驻业务门面，`_ensure_presenter` 只在支持工具栏的场景实例化 View、导航和教学；各模态脚本仅在点击入口时载入。Bootstrap 阶段不得构造此类 HUD。 |

新增角色、卡、音效、场景时先编辑已有权威注册表与入口。不要在别的 Autoload 创建第二个缓存、第二份模板树或全局逐帧轮询。静态元数据查询不应触发重型场景载入。

## 三、场景与玩家状态事务

- 菜单与地图：`MapNavigation` 调用 `AdventureSession.prepare_adventure()` 完成现有存档/解锁校验，再请求 `SceneTransition.change_scene`；地图不自行切场。失败留在原场景供玩家重试。
- 地图与战斗：`AdventureSession.enter_stage(..., transition)` 先构造本局参数但**不发布**；只有成功加载并被 SceneTree 接受后，`_commit_battle_entry` 才发布 `active_level/active_phase/Global.game_para`，保持原引擎读取契约。
- 战斗返回地图：`AdventureSession.return_to_map()` 优先走所属战斗场景的同一 `SceneTransition`；`_commit_map_return` 只在成功交接后释放本局状态并恢复暂停/鼠标。无组件的历史测试场景可采用原同步回退，不得为正式关卡再造旁路。
- 正式战斗根：`scenes/main/MainGame00Base.tscn` 统一挂载 `SceneTransition`，所有派生战斗环境复用。

## 四、验收命令及判断边界

在隔离用户数据目录运行 Godot（正式用户的存档不得被测试覆盖）：

```powershell
$env:APPDATA = "C:\Dev\PvZ\_review\startup_refactor_20261114\Roaming"
$env:LOCALAPPDATA = "C:\Dev\PvZ\_review\startup_refactor_20261114\Local"
$exe = "C:\Users\Arthu\Desktop\Godot_v4.7.2-stable_win64.exe"
$project = "C:\Dev\PvZ\PVZ-Adventure"
& $exe --headless --path $project --quit-after 120 --benchmark
& $exe --headless --path $project --scene res://tests/adventure/test_lazy_startup.tscn
& $exe --headless --path $project --scene res://tests/adventure/test_lazy_audio.tscn
& $exe --headless --path $project --scene res://tests/adventure/test_threaded_scene_loading.tscn
& $exe --headless --path $project --scene res://tests/adventure/test_threaded_battle_route.tscn
& $exe --headless --path $project --scene res://tests/adventure/test_boot_to_menu.tscn
& $exe --headless --path $project --scene res://tests/adventure/test_lazy_toolbar_modal.tscn
```

- 日志不仅看退出码，还必须排除 `SCRIPT ERROR`、解析失败及测试 `FAIL`；Godot headless 的 shader backend 不代表 GPU 首帧完整验收。
- 内置 `--benchmark` 的 `Load Autoloads`、`Load Game` 与真实图形首帧应分开记录；冷启动和温启动至少各测三次，禁止拿不同文件缓存状态的单次数据声称加速比例。
- 每次改动卡牌、音效、地图/战斗入口或 GUI 可视状态，必须重新验证首次请求、重复请求、非法资源、失败复原、线程加载后 callback 顺序与独立玩家档连续性。
- 图形模式请独立运行 `test_boot_to_menu.tscn`，验证进入实际可交互菜单；`project.godot` 的 `ui_accept` 同时保留 Enter、数字键盘 Enter、Space 和手柄 A，避免导航测试与实际输入映射不一致。
- 首次进入岛屿时 `AdventureSession.prepare_adventure` 可能先持久化已接受的「启程」事实，之后才请求地图资源；加载失败不重复发奖，原场景保持可重试。战斗参数与玩家持久启程是不同事务，不应混称为同一次提交。
- 2026-11-14 基线：原 Headless Autoload 两次约 6.84–6.86 秒；改造后极短启动重复三次分别为 2165/2134/2156ms，中位数约 2.156 秒。独立 Bootstrap→交互菜单测得 Headless 683ms、Windows 图形模式 1094ms；这不等于发行包冷启动。
- 玩家在加载中直接退出时，SceneTransition._exit_tree 必须完成正在运行的 Godot 线程化资源请求后再释放；短启动五帧即退出连测三次均正常退出。普通场景切换路径不应调用任何同步等待。
- Windows 图形模式 `test_scene_transition_frames.tscn` 按真实 `frame_post_draw` 采样，验证淡出时存在连续中间透明度帧；本测试不使用 Headless。
