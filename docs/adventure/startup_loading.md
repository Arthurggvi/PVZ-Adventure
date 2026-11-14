# 启动与场景加载：权威管线（2026-11-14）

本文件定义正式资源拥有者、调用契约、故障行为及验收方式。Godot 4.7.2；不新增依赖。本轮关注点击后进入地图、战斗及首次打开功能窗口；资源读取、主线程构造、渲染与可交互是不同阶段。

## 一、唯一入口与职责

- `project.godot → scenes/main/00Bootstrap.tscn`：轻量首屏，不直接引用战斗、卡牌总览或海滨母图；由同一个 `SceneTransition` 进入 `01StartMenuCoastal.tscn`。
- `scenes/ui/transitions/SceneTransition.tscn` / `scripts/ui/transitions/scene_transition.gd`：**唯一**正式场景切换组件，负责遮幕、输入锁、资源准备、成功交接及失败复原；地图、战场与首屏复用，不另建页面专用 Loader。
- `SceneTransition.change_scene(path, after_switch=Callable(), resource_paths=PackedStringArray()) -> bool`：第三参数为可选的本次动态依赖路径，原两参数调用兼容。返回值仅表示**已接受请求**，不代表切场完成。目标和显式依赖在遮幕开始时立即提交，与动画重叠；不得等遮幕完成才开始读取。
- 统一请求实现是 `scripts/ui/transitions/resource_load_batch.gd`（代码别名 `ResourceBatch`）：每批最多 **2 个根资源请求在途**，`load_threaded_request(..., false)` 禁用额外子线程。已有缓存直接取得强引用；正常轮询只在 `THREAD_LOAD_LOADED` 后调用 `load_threaded_get`。并发上限属于单批次，不是全进程线程数承诺；批次不是第二个全局缓存。
- PackedScene 就绪后，可从目标根脚本的静态 `get_initial_resource_paths() -> PackedStringArray` 补齐首屏动态依赖；继承场景沿基础根查找。读取脚本声明不实例化目标。战斗额外依赖由 `battle_resource_plan.gd` 根据本局参数、库存卡与注册表收集，禁止恢复全物种预加载。
- 遮幕和资源准备都完成后，在主线程**只实例化一次真实目标**，给目标设置 `prepared_resources` metadata 持有已加载资源，再用 Godot 4.7 的 `SceneTree.change_scene_to_node(target)` 交接。回调先保存到局部变量，只有 SceneTree 接受后才调用，早于目标入树及 `_ready`；禁止为校验再构造一张目标场景。
- `transition_failed` 必须恢复原场景遮幕和输入，不执行成功回调或清空战斗/存档；繁忙时拒绝重复请求。取消/失败停止新提交，已提交请求继续异步回收；仅宿主销毁或程序退出使用 `finish_on_exit()` 完成剩余请求，正常切场与关闭窗口不得同步等待未完成加载。
- `SceneTransition.run(action)` 只保留历史兼容。新增场景跳转一律走 `change_scene`，禁止在遮幕回调中直调 `change_scene_to_file` 绕过准备管线。
- `coastal_menu.is_visual_ready()`：菜单先完成多视口合成并可见，再经过两个真实绘制帧才揭幕。`ResourceBatch.progress()` 仅表示当前资源批次的估计读取比例，不包含实例化、`_ready`、GPU 首帧或交互动画；百分比完成不能冒充可交互。

## 二、资源拥有者与按需构造

| 公共门面 | 唯一资源拥有者及首次加载行为 |
|---|---|
| `AllCards` | `scripts/autoload/lazy_card_catalog.gd` 保留原五个公开方法；`get_references/is_battle_card/get_template_path/get_resource_paths` 只读 `card_catalog_manifest.gd` 的身份与路径，不装配卡面。`get_template/create_card/create_static_preview` 只加载请求物种的单卡模板，已请求模板由同一门面持有。`is_catalog_materialized()` 表示已构造至少一个模板，不再表示全目录已构造。 |
| 卡牌编辑源 | `scenes/autoload/all_cards.tscn` 是编辑总览与顺序聚合，运行时不得实例化整棵总览。当前 `scenes/ui/all_cards/templates/` 有 **84 个逐卡场景**，生成 manifest 有 **83 个运行时基础引用**；模仿身份复用目标植物模板。单卡内容与总览顺序仍是编辑源，manifest 不得手工维护。 |
| `Global.character_registry` | 身份、标量、路径静态保存；`get_plant_info/get_plant_scene/get_zombie_info/get_zombie_boss_info` 的资源字段首次按需解析并缓存，原返回类型不变。不得把场景或种植条件重新放回静态 `preload`。 |
| `SceneRegistry` | 保留 `SceneRegistry.SUN` 等属性接口，由既有路径表及缓存惰性取得 `PackedScene`，不新增重复目录。 |
| `SoundManager` | SFX 名称与随机候选只存路径，首次播放解析并缓存，现有总线和音效池不变；Boss 咆哮首次播放时加载。 |
| `AdventureToolbar` | 常驻业务门面，`_ensure_presenter` 仅在真实工具栏宿主构造 View、导航和教学；Bootstrap 不构造 HUD。模态请求统一异步准备，详见下一节。 |

修改单卡身份、总览顺序或逐卡场景后运行 `python tools/card_catalog.py` 更新 manifest，再运行 `python tools/card_catalog.py --check` 核对源与生成结果一致。`--split` 仅用于迁移尚未拆分的旧总览，不是日常再生成步骤。新增角色、卡、音效、场景仍维护已有权威门面；禁止在其他 Autoload 建立全量模板树或独立资源缓存。

## 三、关卡、模态与玩家状态事务

- 菜单到地图：地区选择页先展示共用加载反馈，`MapNavigation` 从 `DestinationCatalog` 已校验的布局提取动态纹理路径，复用 `ResourceBatch` 准备后再构造选择器；准备期间也持有导航输入锁，关闭、换档和离场会取消交付。选择地区后，经 `AdventureSession.prepare_adventure()` 完成档案/进度校验，再请求统一切场。首次启程可能先保存已接受的启程事实；资源失败保留原场景且不重复发奖，不能把持久启程与战斗状态提交混为一笔事务。
- 关卡配置：`enter_stage` 只调用一次 `load_stage`，同一个 `StageDefinition` 依次传给 `entry_error_for_stage` 和本局构建。`AdventureStageRegistry` 缓存合并后的私有模板，`resolve()` 对外返回深拷贝以隔离预览、测试及本局修改；`invalidate_cache(index=0)` 可显式失效。带 editor feature 的运行在准备进入地图/成功返图时由 `begin_map_visit()` 刷新，发行包复用解析模板；首次关卡配置读取本身仍是同步步骤。
- 地形检查：`validate_terrain` 仅使用 `BoardDefinition` 或 `MainSceneRegistry.LEGACY_SPAWN_ROWS` 的静态行协议，保留物种水陆兼容、覆盖行数及固定预排行检查，禁止加载/实例化战场来读行数。前院/泳池/屋顶对应 5 陆、6 行陆陆水水陆陆、5 陆；`BoardSceneAdapter` 在真实旧战场装配且尚未应用本局地形覆盖时核对节点与静态表。修改基础场景行布局须同步维护协议；自定义布局沿用自己的 `BoardDefinition`。
- 地图到战斗：先准备本局参数但不发布；SceneTree 接受目标后，`_commit_battle_entry` 才发布 `active_level/active_phase/Global.game_para`。`MainGame00Base.tscn` 提供所有派生战场共用的过渡组件。后台读取不会自动把实例化、管理器初始化或角色装配变成后台工作。
- 战斗返图：优先使用本战场的 `SceneTransition`，`_commit_map_return` 只在成功交接后清理本局状态并恢复暂停/鼠标。没有组件的历史测试入口保留同步回退，正式场景不得新增旁路。
- 功能窗口：`AdventureToolbar.request_feature()` 先检查当前宿主与正式解锁条件，立即显示可关闭的 `modal_loading_view.gd`，再通过同一 `ResourceBatch` 准备脚本和静态 `get_initial_resource_paths()` 声明。真正窗口在主线程构造，支持 `is_content_ready()` 的窗口等首批内容就绪才替换反馈；`modal_for()` 只返回已发布窗口。
- 模态生命周期：请求序号、源场景、玩家名和 `AdventureState` 对象身份共同约束发布。取消、换档、重载和离场撤销旧请求的交付资格，释放旧表现并异步回收已提交任务；失败反馈可关闭，旧完成回调不得打开到新宿主。窗口通过 `prepared_resources` metadata 保持准备资源的强引用。
- 可见项与分帧：背包只准备当前页，以实际构造耗时约 4ms 为一片让帧，不给空格增加固定等待。研究和图书馆复用 `prepared_visual_queue.gd`，图鉴使用自身的可见项队列；每帧最多装配一个预览。滚动裁剪、隐藏页签及被重绘释放的目标不应触发全量角色构造。冒险候选卡及开场僵尸按约 4ms 构造预算让帧，单个节点不可拆分，因此预算不是帧耗时硬上限。候选卡仍保留完整 UID 索引和库存顺序，管理器等待就绪后连接交互；战场通过 `is_visual_ready()` 阻止提前揭幕。可见内容完成和入场动画稳定仍须分别观察。

## 四、验收命令及判断边界

在隔离用户目录**串行**运行。Windows GUI 版 Godot 通过输出管道 `| Out-String` 等待进程结束，不能只连续启动多个 `& $exe`；各测试使用自己要求的隔离目录标记：

```powershell
$review = "C:\Dev\PvZ\_review\interaction_loading_20261114"
$exe = "C:\Users\Arthu\Desktop\Godot_v4.7.2-stable_win64.exe"
$project = "C:\Dev\PvZ\PVZ-Adventure"
function Invoke-LoadingCheck {
    param([string]$Name, [string[]]$GodotArgs)
    $env:APPDATA = Join-Path $review $Name
    $env:LOCALAPPDATA = Join-Path $review ($Name + "-local")
    New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null
    & $exe --path $project @GodotArgs 2>&1 | Out-String | Tee-Object -FilePath (Join-Path $review ($Name + ".log"))
    if ($LASTEXITCODE -ne 0) { throw "Godot check failed: $Name" }
}
python tools/card_catalog.py --check
Invoke-LoadingCheck -Name "startup-benchmark" -GodotArgs @("--headless", "--quit-after", "120", "--benchmark")
Invoke-LoadingCheck -Name "startup-lazy-test" -GodotArgs @("--headless", "--scene", "res://tests/adventure/test_lazy_startup.tscn")
Invoke-LoadingCheck -Name "startup-audio-test" -GodotArgs @("--headless", "--scene", "res://tests/adventure/test_lazy_audio.tscn")
Invoke-LoadingCheck -Name "startup-threaded-test" -GodotArgs @("--headless", "--scene", "res://tests/adventure/test_threaded_scene_loading.tscn")
Invoke-LoadingCheck -Name "startup-battle-test" -GodotArgs @("--headless", "--scene", "res://tests/adventure/test_threaded_battle_route.tscn")
Invoke-LoadingCheck -Name "startup-boot-test" -GodotArgs @("--headless", "--scene", "res://tests/adventure/test_boot_to_menu.tscn")
Invoke-LoadingCheck -Name "startup-toolbar-test" -GodotArgs @("--headless", "--scene", "res://tests/adventure/test_lazy_toolbar_modal.tscn")
Invoke-LoadingCheck -Name "startup-boot-test-graphical" -GodotArgs @("--max-fps", "60", "--scene", "res://tests/adventure/test_boot_to_menu.tscn")
Invoke-LoadingCheck -Name "transition-frame-test" -GodotArgs @("--max-fps", "60", "--scene", "res://tests/adventure/test_scene_transition_frames.tscn")
```

- 退出码不是唯一判断：逐份排除 `SCRIPT ERROR`、解析错误和 `FAIL`，再核对日志的实际覆盖范围。Headless shader backend 不能代表 GPU 首帧；图形帧测试按 `frame_post_draw` 验证淡出中间透明度，不能用 Headless 替代。
- 关联改动须覆盖首次/重复请求、非法资源、失败恢复、取消/换档/离场、交接回调顺序和独立玩家档连续性。`ui_accept` 保留 Enter、数字键盘 Enter、Space 和手柄 A，导航验收应走真实功能门面。
- 本轮图形诊断资料位于仓外 `C:\Dev\PvZ\_review\interaction_loading_20261114`：`interaction_diagnostic.gd/.tscn` 和 `run_interaction_diagnostic.ps1`，隔离目录必须含 `startup-interaction-test`。`all/routes` 经过真实菜单、地图选择器、地图、首次/第二次关卡1与返图；`all/modals` 记录背包、图鉴、角色、设置的首次/第二次打开，并输出 JSON、日志与 PNG。未解锁的研究室/图书馆/商店须明确记录未覆盖，不能把新档诊断称为全功能验收。
- 诊断端点分别是菜单可见且解除遮幕、地图解除遮幕、战斗 `card_manager.is_norm_appeared`、窗口 `modal_for()/is_content_ready()`；选卡标记早于候选槽入场动画稳定，因此截图另等动画结束。入口同步调用时间、到就绪耗时、墙钟帧间隔分开记录；帧间隔包含渲染/调度等待，不等同纯 CPU 时间。`all` 先跑战斗，后续窗口资源可能已预热；需要冷窗口数据时另开 `modals` 进程。
- 本轮接入与诊断入口不表示已取得性能或验收结论。实测结论必须引用对应日志/JSON及运行条件；冷/温启动至少各三次，区分引擎 Autoload、Bootstrap→菜单、点击→内容就绪、图形首帧和发行包，不把不同文件缓存状态的单次结果算成加速比例。
- **上一轮历史基线（2026-11-14，非本轮点击后交互数据）**：Headless Autoload 原两次约 6.84–6.86 秒；上一轮极短启动三次 2165/2134/2156ms，中位数约 2.156 秒。独立 Bootstrap→交互菜单当时为 Headless 683ms、Windows 图形 1094ms。这些范围不同，均不能证明本轮首次地图、关卡或窗口变快，也不等同发行包冷启动。上一轮五帧即退出三次正常的记录同样不能代替本轮资源批次退出检查。

## 五、本轮已执行的验收与剩余边界

2026-11-14 本轮集中验收：编辑器导入/解析、卡牌 manifest 一致性，以及六项指定加载验收均通过功能断言；地区导航、图形过渡帧、背包和研究室原有验收也通过。日志为仓外目录下的 `editor_integrated_final.log`、`final_test_*.stdout.log/.stderr.log`。另外，图形取消诊断的六条路径通过：窗口即时/准备中取消、同帧换档重开、导航即时/准备中取消及准备中换档；旧失败通知不会影响后来请求。动态美术图形诊断另覆盖向日葵一/三/四转（含三转眨眼）、23号僵尸三/五阶及准备中快速切阶；实际窗口持有预期纹理，旧阶级结果不会覆盖新选择，截图已核对。十星一转卡快照的纯路径查询覆盖全部26张动态图，查询本身不载入图片。

以下为 Windows / Godot 4.7.2 / OpenGL Compatibility / RTX 5060 Laptop / 1280×720、60fps 上限的**三次独立进程首次访问**结果。地图与关卡使用两张初始卡；窗口另开进程，未先进入战斗，但四个窗口按背包、图鉴、角色、设置顺序打开，可共享先前窗口已准备的资源。系统文件缓存未清空，编辑器同时开启，不是发行包冷启动，也没有相同口径的旧实现对照，不能据此计算提速比例。

| 路径 | 入口同步调用中位数 | 到内容就绪中位数 | 三次中最大的帧间隔 |
|---|---:|---:|---:|
| 首次地区选择页 | 1.24ms | 400ms | 29ms |
| 地区选择页→地图 | 0.56ms | 1083ms | 34ms |
| 首次地图→关卡选卡开始 | 12.85ms | 3363ms | 66ms |
| 首次背包 | 1.27ms | 438ms | 27ms |
| 首次图鉴 | 1.34ms | 600ms | 34ms |
| 首次角色 | 1.62ms | 201ms | 28ms |
| 首次设置 | 1.33ms | 67ms | 27ms |

原始数据是 `sample_routes_1..3.stdout.log`、`sample_modals_1..3.stdout.log` 及相应 JSON；聚合为 `final_interaction_summary.json`。关卡的约 3.36 秒包含原有 1 秒停留和 2 秒镜头运动，不是 3 秒主线程冻结；选卡入场动画稳定另计。167 张卡的独立压力样本首次到选卡开始 4881ms、最大帧间隔 51ms，第二次 4450ms、39ms；该单次压力样本不能用来推断普通档案的稳定上限。

仍有明确边界：Bootstrap 后菜单首次合成在采样中出现约 0.44～0.50 秒帧间隔；部分验收与诊断退出时仍报告 `ObjectDB instances were leaked`，少数短测试伴随 `resources still in use`，尚未归因，因此这里只记功能断言通过，不宣称退出资源回收完全正常。图书馆/商店的真实解锁后完整流程、用户现有老档及发行包未实测。后续优化须针对这些具体路径采样，不再把加载百分比或 Autoload 数据当成交互流畅度。
