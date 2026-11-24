# 启动与场景加载：权威管线（2026-11-14）

本文件定义正式资源拥有者、调用契约、故障行为及验收方式。Godot 4.7.2；不新增依赖。本轮关注点击后进入地图、战斗及首次打开功能窗口；资源读取、主线程构造、渲染与可交互是不同阶段。

## 一、唯一入口与职责

- `project.godot → scenes/main/00Bootstrap.tscn`：轻量首屏，不直接引用战斗、卡牌总览或海滨母图；由同一个 `SceneTransition` 进入 `01StartMenuCoastal.tscn`。
- `scenes/ui/transitions/SceneTransition.tscn` / `scripts/ui/transitions/scene_transition.gd`：**唯一**正式场景切换组件，负责遮幕、输入锁、资源准备、成功交接及失败复原；地图、战场与首屏复用，不另建页面专用 Loader。
- `SceneTransition.change_scene(path, after_switch=Callable(), resource_paths=PackedStringArray()) -> bool`：第三参数为可选的本次动态依赖路径，原两参数调用兼容。返回值仅表示**已接受请求**，不代表切场完成。目标和显式依赖在遮幕开始时立即提交，与动画重叠；不得等遮幕完成才开始读取。
- 统一请求实现是 `scripts/ui/transitions/resource_load_batch.gd`（代码别名 `ResourceBatch`）：每批最多 **2 个根资源请求在途**，`load_threaded_request(..., false)` 禁用额外子线程。已有缓存直接取得强引用；引擎报告 `THREAD_LOAD_LOADED` 或 `THREAD_LOAD_FAILED` 后才调用 `load_threaded_get` 回收句柄。并发上限属于单批次，不是全进程线程数承诺；批次不是第二个全局缓存。
- PackedScene 就绪后，可从目标根脚本的静态 `get_initial_resource_paths() -> PackedStringArray` 补齐首屏动态依赖；继承场景沿基础根查找。读取脚本声明不实例化目标。战斗额外依赖由 `battle_resource_plan.gd` 根据本局参数、库存卡与注册表收集，禁止恢复全物种预加载。
- 遮幕和资源准备都完成后，在主线程**只实例化一次真实目标**，给目标设置 `prepared_resources` metadata 持有已加载资源，再用 Godot 4.7 的 `SceneTree.change_scene_to_node(target)` 交接。回调先保存到局部变量，只有 SceneTree 接受后才调用，早于目标入树及 `_ready`；禁止为校验再构造一张目标场景。
- `transition_failed` 必须恢复原场景遮幕和输入，不执行成功回调或清空战斗/存档；繁忙时拒绝重复请求。取消或失败停止新提交，已提交请求继续异步回收。`ResourceBatch` 对同一路径复用在途请求，每帧最多查询一次；单个请求连续 20 秒无进展时，批次走原有失败路径。宿主可以继续接受新操作，超时请求由场景树低频查询，直到引擎报告结束才回收，不保留已完成资源。
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
- 专属地区战场通过 `StageDefinition.battle_scene/return_scene` 声明路径，未指定时仍使用原版环境注册表与僵尸岛地图。致幻洋流正式编号 101 走相同 `enter_stage`、UID 选卡和资源准备入口；重开自动取得当前战场的 `SceneTransition`，按 Session 当前阶段构建布局与底图。跨地区通关记录按稳定关卡 ID 的地区前缀存储，不借用第一关进度。
- 战斗返图：优先使用本战场的 `SceneTransition`，`_commit_map_return` 只在成功交接后清理本局状态并恢复暂停/鼠标。通关奖励保存后返图失败，原战场解除遮幕并显示重试入口，重试只重新请求地图。没有组件的历史测试入口保留同步回退，正式场景不得新增旁路。
- 功能窗口：`AdventureToolbar.request_feature()` 先检查当前宿主与正式解锁条件，立即创建可取消的 `modal_loading_view.gd`，并通过同一 `ResourceBatch` 开始准备脚本和静态 `get_initial_resource_paths()` 声明；加载提示及其遮罩按第四节延迟展开。真正窗口在主线程构造，支持 `is_content_ready()` 的窗口等首批内容就绪才替换反馈；`modal_for()` 只返回已发布窗口。
- 模态生命周期：请求序号、源场景、玩家名和 `AdventureState` 对象身份共同约束发布。取消、换档、重载和离场撤销旧请求的交付资格，释放旧表现并异步回收已提交任务；失败反馈可关闭，旧完成回调不得打开到新宿主。窗口通过 `prepared_resources` metadata 保持准备资源的强引用。
- 可见项与分帧：背包只准备当前页，以实际构造耗时约 4ms 为一片让帧，不给空格增加固定等待。研究和图书馆复用 `prepared_visual_queue.gd`，图鉴使用自身的可见项队列；每帧最多装配一个预览。研究室强化主卡的属性说明也通过预览队列读取场景结构，选卡时直接更新槽位和报价。滚动裁剪、隐藏页签及被重绘释放的目标不应触发全量角色构造。冒险候选卡及开场僵尸按约 4ms 构造预算让帧，单个节点不可拆分，因此预算不是帧耗时硬上限。候选卡仍保留完整 UID 索引和库存顺序，管理器等待就绪后连接交互；战场通过 `is_visual_ready()` 阻止提前揭幕。可见内容完成和入场动画稳定仍须分别观察。

## 四、共享加载表现与连续交接

### 2026-11-22：v1.1.1 Android 加载停滞 P0 重构

- 正式入口仍只使用 `ResourceBatch.start/poll/cancel/abandon/get_resource`，不增加 Autoload 或另一个 UI Loader。其实现拆分为 `resource_load_batch.gd`（公共批次及整批截止时间）、`resource_load_frame_backend.gd`（Android）和 `resource_load_threaded_backend.gd`（桌面），保留原有状态码与资源强引用交付契约。
- Android 不发起 `load_threaded_request`：仅命中已有资源缓存或每个游戏帧同步读取最多一个未缓存根资源。此举规避疑似 Android 原生线程请求长期 `IN_PROGRESS` 的情况，但单次 `ResourceLoader.load` 仍然不可抢占，单资源超大时可能出现长帧；不得将“每帧最多一项”宣称为 4ms 硬上限。
- 桌面仍采用最多两条在途根资源的受控线程加载。已取消请求移除观察者，允许健康的在途请求继续复用；无观察者请求最多每 250ms 回收 20 次后停止计时器并隔离，不再反复创建永久回收任务。停滞请求隔离后不重新提交同一路径，终态则由状态查询取回资源并释放句柄；不能把业务取消写成 Godot 底层线程终止。
- `ResourceBatch` 的批次期限从首次提交计算，不被微小进度重置：地图选择器和功能模态各 12s，正式场景默认 45s。到期结束业务交付并恢复原有错误反馈；取消后的旧请求（含已经读完但未发布的请求）不能再发布窗口或改变战斗状态。
- `AdventureToolbar.retire_resource_batch` 直接把回收责任移交加载后端，不再保留持续逐帧 poll 的退休批次数组；窗口构造后首屏无法就绪另有 12s 业务期限。现有输入锁、首次出现延迟、完整资源强引用、玩家身份和切场原子交接保持不变。
- 本轮验收范围：Windows 既有线程切场、地图/设置、启动/音效、战斗往返及图形揭幕，以及以 `ResourceBatch.new(true)` 强制执行的三份真实资源分帧后端测试。隔离调试 Android APK 导出成功，ZIP CRC、三个目标 ABI、正式资源排除范围及新加载脚本入包均已核对；调试签名包不代替正式发布包，也不等于 OPPO Android 真机验证。保留已有退出时 ObjectDB/resource warning 的独立调查，不认定为本轮清除。

### 2026-11-22：资源超过三秒提示与可反馈的加载断点

- **界面规则**：`loading_resource_hint.gd` 是原 `loading_presentation.gd` 画布内的一行标签，只有底层确实在执行同一资源超过 **3000ms** 才显示文件名与耗时；正常加载、资源已完成、取消和失败时立即隐藏。紧凑模态位于进度条上方空白，全屏位于草皮下方，不增标题、背景板、动效或额外取消操作。Windows 后台并发取最早开始的活跃请求，完整路径不直接显示给玩家。
- **Android 限制**：Android 的 `ResourceLoader.load()` 在主线程同步读取时无法更新 UI；**不能**宣称第 3 秒会绘制文字或在该点取消单次阻塞。进入同步根资源前必须执行 `resource_load_checkpoint.gd.begin()`、flush 到独立 `user://load_checkpoint.json`，返回后按结果执行 `finish()`。上次未完成断点在下次启动归档为“未记录完成”，不等同引擎崩溃或确认故障资源。场景及功能窗口主线程实例化也采用相同断点，不假装它们是 PNG 资源。
- **轻量报告**：`user://load_diagnostic.json` 仅保留最近有意义的一条完整 `res://` 路径、阶段、版本、平台/机型、时间和状态，不读玩家存档、姓名或安装路径。写入有界；成功但慢资源不会覆盖待反馈的失败/中断。菜单只有上次失败/未结束且未确认时才出现暖黑浅铜色“复制上次加载记录”按钮；设置在存在报告时于原底栏左侧提供“复制加载记录”。复制后标记已确认，菜单不再重复提示，设置仍能复制。
- **验收边界**：以隔离用户目录运行两独立 Godot 进程验证中断恢复、慢成功、复制确认；以实际 Godot 图形帧核对 3 秒阈值、原全屏与紧凑版，以及主菜单/设置入口。Windows 真实场景回归验证代码交接。正式 Android APK、OPPO/ColorOS 真机、主线程硬阻塞下的实际记录仍需后续验证；不以 Windows 模拟替代手机结论。

2026-11-14 按用户反馈修订：短加载没有阅读时间，原版标题、阶段说明、口号和装饰动效造成额外打扰。当前版本删除正常加载文案和品牌字，也删除漂浮、呼吸与光点；不能重新添加为了展示自身而抢占注意力的内容。

- `scripts/ui/transitions/loading_presentation.gd` 是 Bootstrap、场景切换、功能窗口与地区选择器共用的纯表现组件，只拥有布局、进度、透明度和失败信息。它不请求资源、不缓存场景、不保存玩家状态；加载与取消仍由原有 `SceneTransition`、`ResourceBatch` 和业务宿主负责，不增加 Loader、Autoload 或全局缓存。
- 正常全屏加载只保留暖墨绿背景、静态花园插画和原版泥土/草皮进度条。紧凑版为设计尺寸 **312×112** 的小提示，仅有进度条与“取消”；不显示插画、大卡片、标题或阶段说明。只有失败时显示简短原因与返回/重试操作。插画导入最长边仍为 **512px**，已有 `.ctex` 为 **130,834 bytes**；加载表现已移除 `Sun2.png` 和 `Bake_Soda.otf` 预加载，必要按钮及错误文字使用系统字体，不静态引用角色场景、功能窗口或大型中文字库。
- 场景切换、模态与地区选择反馈的内容均延迟 **0.45 秒**展开，按真实时间计算；模态遮罩同样在 0.45 秒后才开始淡入，最高透明度 **12%**。资源立即开始准备；延迟不是最短停留或业务超时，完成更快的请求立即交接。Bootstrap 原有首屏直接显示静态插画，交由统一过渡接管，不重复等待。
- `set_progress()` 只单调推进，准备阶段上限为 **0.94**，不显示数字。场景首批资源映射到 `0..0.65`，补充动态依赖映射到 `0.65..0.90`，主线程构造推进至 `0.94`；`finish()` 只将目标改为 `1.0`，宿主不等待草皮填满才交付内容或揭幕。表现只在透明度或进度变化时运行 `_process()`，到达目标或隐藏后停止；不保留装饰用累计时间、动画相位或循环重绘。
- 源场景在目标入树前写入 `loading_presentation_state` metadata，包含 `snapshot()` 纯表现快照、真实请求起点与内容是否已经展开。快照字段仅为 `compact/displayed/target/opacity/target_opacity/error/message`，不携带节点、资源或业务回调。目标 `SceneTransition._ready()` 在首帧前 `restore()` 并消费 metadata，继续原来的展开延迟、进度和透明度；宿主满足 `is_visual_ready()` 并经过两个真实绘制帧后，整层 Curtain 连同内容一起淡出，不能先隐藏内容造成空幕或进度回零。
- Bootstrap 首屏通过 `adopt_presentation(snapshot)` 将已经覆盖的首屏直接交给统一过渡，同时隐藏底层表现。失败仍保留启动页；统一过渡恢复输入后显示“菜单加载失败。”并聚焦“重试”，确认键继续有效。
- 模态 `dismiss()` 的 **0.14 秒**淡出仅负责视觉收尾：调用当下即禁用鼠标拦截、输入处理、动作按钮与焦点，再异步释放旧表现。取消资格由原业务宿主同步撤销，淡出不能推迟取消、阻挡新窗口输入或清掉后来的请求。淡入淡出不受游戏暂停或倍速影响。

## 五、验收命令及判断边界

在隔离用户目录**串行**运行。Windows GUI 版 Godot 通过输出管道 `| Out-String` 等待进程结束，不能只连续启动多个 `& $exe`；各测试使用自己要求的隔离目录标记：

```powershell
$review = "D:\Dev\PvZ\_review\interaction_loading_20261114"
$exe = "C:\Users\Arthu\Desktop\Godot_v4.7.2-stable_win64.exe"
$project = "D:\Dev\PvZ\PVZ-Adventure"
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
- 本轮图形诊断资料位于仓外 `D:\Dev\PvZ\_review\interaction_loading_20261114`：`interaction_diagnostic.gd/.tscn` 和 `run_interaction_diagnostic.ps1`，隔离目录必须含 `startup-interaction-test`。`all/routes` 经过真实菜单、地图选择器、地图、首次/第二次关卡1与返图；`all/modals` 记录背包、图鉴、角色、设置的首次/第二次打开，并输出 JSON、日志与 PNG。未解锁的研究室/图书馆/商店须明确记录未覆盖，不能把新档诊断称为全功能验收。
- 诊断端点分别是菜单可见且解除遮幕、地图解除遮幕、战斗 `card_manager.is_norm_appeared`、窗口 `modal_for()/is_content_ready()`；选卡标记早于候选槽入场动画稳定，因此截图另等动画结束。入口同步调用时间、到就绪耗时、墙钟帧间隔分开记录；帧间隔包含渲染/调度等待，不等同纯 CPU 时间。`all` 先跑战斗，后续窗口资源可能已预热；需要冷窗口数据时另开 `modals` 进程。
- 本轮接入与诊断入口不表示已取得性能或验收结论。实测结论必须引用对应日志/JSON及运行条件；冷/温启动至少各三次，区分引擎 Autoload、Bootstrap→菜单、点击→内容就绪、图形首帧和发行包，不把不同文件缓存状态的单次结果算成加速比例。
- **上一轮历史基线（2026-11-14，非本轮点击后交互数据）**：Headless Autoload 原两次约 6.84–6.86 秒；上一轮极短启动三次 2165/2134/2156ms，中位数约 2.156 秒。独立 Bootstrap→交互菜单当时为 Headless 683ms、Windows 图形 1094ms。这些范围不同，均不能证明本轮首次地图、关卡或窗口变快，也不等同发行包冷启动。上一轮五帧即退出三次正常的记录同样不能代替本轮资源批次退出检查。

## 六、异步加载管线既有验收与剩余边界

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

## 七、初版花园加载表现历史验收（2026-11-14）

以下记录对应精简文案与动效之前的初版（提交 `c1169f71`），只作历史证据，不能代替当前第四节实现的重新验收。该轮日志、图形驱动与截图保存在仓外 `D:\Dev\PvZ\_review\garden_loading_20261114`。编辑器导入记录为 `editor_parse.log`；以下 **八项既有验收均记录 PASS**，分别对应目录中的同名 `.stdout.log` / `.stderr.log`，未新增测试套件：

| 既有验收 | 本轮确认范围 |
|---|---|
| `test_lazy_startup` | 惰性启动资源、旧注册接口与卡牌模板 |
| `test_lazy_audio` | 惰性音效目录、缓存与空操作 |
| `test_threaded_scene_loading` | 正式线程切场和目标 `_ready` 前成功回调 |
| `test_threaded_battle_route` | 地图→战斗→地图、延后状态交接和档案连续性 |
| `test_boot_to_menu` | Bootstrap→完成渲染且可交互的城镇 |
| `test_lazy_toolbar_modal` | 工具栏按需创建与释放功能窗口 |
| `test_destination_picker` | 地区导航、打断/缩放/输入锁、失败恢复和原有保存边界 |
| `test_scene_transition_frames` | 同步准备后仍保留实际绘制的揭幕中间帧 |

图形驱动 `garden_loading_preview.gd/.tscn` 在 Windows 显示后端、60fps 上限下完成观察；最终结果为 `garden_preview_1794670712.json`、`preview_final.stdout.log` 和 `preview_1794670712_*.png`。全屏 **1280×720、1920×1080、960×540、1280×800** 四个尺寸，以及 1280×720 的紧凑版与错误反馈均完成图形核对。该驱动包含模拟进度和为截图设置的观察等待，仅验证表现，不是资源加载或性能基准，也不表示正式流程增加等待。

连续性交接使用正式 `SceneTransition.change_scene()` 路径和专用缓存目标：最终记录源场景 **16 帧**、目标场景 **48 帧**，缺失遮幕/表现的间隙帧为 **0**；标题与内容透明度保持，动画累计时间和已显示进度均不倒退。取消/退出检查确认 `dismiss()` 调用当下即释放输入与按钮焦点，观察 **0.2 秒**后旧反馈已释放。真实窗口/导航取消诊断的六条路径再次通过，包含即时取消、准备中取消和换档重开；结果为 `cancel_final.stdout.log`。原仓外诊断使用旧 `_caption` 的失效断言已改为当前反馈标题/错误状态，再重新完整运行。

图形驱动自身记录 `errors: []`，但部分正式验收与预览进程退出时仍有 `ObjectDB instances were leaked` warning。上述结论是功能与图形表现验收通过，不能表述为完全无错误或退出资源回收问题已解决；本轮也不据此宣称冷启动加速、发行包性能改善或未覆盖功能已经验收。

## 八、精简表现修订验收（2026-11-14）

当前版本的记录位于仓外 `D:\Dev\PvZ\_review\quiet_loading_20261114`。第七节列出的八项既有测试重新执行，全部退出码为0并记录功能断言PASS；`test_threaded_battle_route`退出仍出现5个ObjectDB实例和2个资源未释放的告警/错误，其余部分测试及图形预览仍有ObjectDB退出告警。测试中没有解析错误、SCRIPT ERROR或功能FAIL；这里仅确认功能断言，不能称作无错误运行。没有新增仓库测试。

`quiet_preview_1794671365.json`、`preview.stdout.log`及六张`preview_1794671365_*.png`记录四种全屏尺寸和紧凑/失败表现。图形断言确认正常加载无可见说明标签、四种尺寸插画位置保持静止、隐藏停止处理；模态约0.2秒时内容仍透明，约0.75秒时小提示可见；退出立即释放鼠标/输入/焦点，0.2秒后释放旧节点。正式切场采样源16帧、目标48帧，无表现空帧，进度和内容透明度保持连续。驱动有明确的截图观察等待，不是加载性能测量，也不构成正式流程的等待时间。
