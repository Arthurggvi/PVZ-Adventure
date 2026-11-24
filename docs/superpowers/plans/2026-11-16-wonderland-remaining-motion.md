# 奇境大陆剩余动效 Implementation Plan

> **For agentic workers:** 使用 superpowers:executing-plans 在当前工作区逐项实施；本文件同时作为进度账本。用户已批准设计并要求开始，不重复请求执行许可。

**Goal:** 在保留已验收水面的前提下接入其余十区环境动作，并按素材可靠性处理飞艇完整运动。

**Architecture:** 原宿主和效果总线继续拥有唯一显示时钟。场景局部工厂统一资源枚举与实例创建，表面效果和解析粒子按机制复用；局部技术蒙版由世界坐标几何和只读原画派生。

**Tech Stack:** Godot 4.7.2 Compatibility / GDScript / CanvasItem Shader / Python Pillow、NumPy、OpenCV 制作技术蒙版。

**Spec:** [已批准设计](../specs/2026-11-16-wonderland-remaining-motion-design.md)

## Global Constraints

- 世界 1774×887，底图 8192×4096，固定视野 336；已验收海洋、河流资源及光学保持原状。
- 教堂仅局部深暗；hover、HUD、导航独立。没有正式关卡/BOSS 接入。
- 不复制仓库或资源库，复用 D:/Dev/PvZ/PVZ-Adventure；保留原有 project.godot 和无关 UID 改动。
- 默认不新增、不运行测试；本次改变地图首屏资源清单，按 AGENTS.md 的专项要求执行已有启动/加载检查，不扩展测试范围。
- 所有 GDScript 变量/函数按项目规范加中文注释。所有诊断设超时并限制总日志 8 MiB，临时物置 D 盘。
- 本地提交仅包含本任务文件，不 push。新运行资源必须定向纳入 Git。

## Review Focus

1. 可选资源缺失或非法参数：局部拒绝、整批参数不部分提交、底图可用。
2. 全局暂停与单区禁用交错：冻结相位、恢复连续、独立开关不被误开。
3. 窗口与地图平移：世界坐标稳定、边界无图块重叠、不改变 hover。
4. 扁平原画遮挡：孔口不影响外框；植物根部/建筑固定；雪尘按局部遮挡消隐。
5. 飞艇素材：旧分件不可直接启用，完整补底不合格时如实保留局部风动。

## Task 1: 技术素材与区域配置

**Files:** 新建 `tools/art/build_wonderland_environment.py`；新增 `assets/adventure/wonderland/masks/runtime_fx/`；更新 `assets/adventure/wonderland/config/fx_regions.json`。

**Interfaces:** 每项声明 `kind/enabled/mask/bounds_world/mask_origin_world/mask_extent_world/style/profile`。mask 为裁切 RGBA：R 覆盖、G 可动或发光权重、B 局部深度/高度；A 固定 1。只读已验收水域与地形。

- [x] 按原生图块核准孔口、瀑布、教堂边界，生成精细局部 mask；植被限定安全内部，天气分区排除障碍。
- [x] 配置全部区域的具体风、天气、氛围和事件参数；海妖保持关闭。
- [x] 记录贴图像素存储、输出大小和素材依赖；飞艇旧分件检查后决定是否具备完整运动条件。

## Task 2: 通用运行接入

**Files:** 新建 `world_map_effect_factory.gd`、`world_map_region_effect.gd`、`world_map_surface_effect.gd`、`world_map_particle_effect.gd`、`world_map_event_schedule.gd`（均在 `scripts/adventure/world_map/`）；修改 `world_map_assets.gd`、`wonderland_map.gd`、`world_map_effect_bus.gd`。

**Interfaces:** 工厂 `resource_paths(region: Dictionary) -> PackedStringArray` 与 `create(region: Dictionary) -> Node2D`；效果 `configure(id, assets, terrain_root) -> bool`，沿用 `validate_profile/apply_profile/set_animation_seconds/set_effect_enabled` 并提供 `set_motion_paused`。事件候选由显式动作秒数推导，总线按优先级合成。

- [x] 共用数值/几何验证及暂停时钟；不增加全局管理器。
- [x] 从同一工厂表枚举首屏资源和创建实例，水域构造与校验不变。
- [x] 总线将全局暂停传至全部已注册效果，保留 subjects 的既有冻结语义。

## Task 3: 表面、光雾与粒子效果

**Files:** 新增 `shaders/adventure/wonderland/region_*.gdshader` 及共用 include；完成 Task 2 的机制组件；必要时调整地图布料的共享风驱动。

**Interfaces:** 表面采样共享原地形纹理，独立局部 mask/世界原点、显式 `effect_seconds`、事件 `event_weight`；粒子使用固定种子及时间计算，不创建逐帧节点或自身时钟。

- [x] 瀑布向下流、泡沫/水雾；草、树冠、菇缘和花叶微动；平原暖光与云影。
- [x] 熔炉黑心吸入、传送分段聚能、教堂失光与残光；最高强度事件避免同时竞争。
- [x] 雪山/冻土差异、孢子、尘土、学校枯叶、飞艇花瓣，按区域遮挡消隐。
- [x] 完成飞艇素材条件检查，采用批准的回退方案：花叶/花瓣局部风动，保留静态完整轮廓；整艇、桨叶和索具运动仍待可靠分层。

## Task 4: 有界验证、审阅与提交

**Files:** 更新 `docs/adventure/wonderland_map_pipeline.md` 和本账本；必要脚本与图形证据只在 `D:/Dev/PvZ/_review/wonderland_environment_20261116/`。

- [x] 有界 Godot 导入/解析，未记录本任务新增脚本/着色器错误。
- [x] 七构图28秒正式场景预览，核对局部深暗、孔口、瀑布、暂停/恢复及地图和菜单往返。
- [x] 按首屏依赖改动要求，串行执行已有六项启动/加载检查及图形过渡检查；两项有无显示错误的检查补做图形运行，不新增测试。
- [x] 一次独立全改动审阅并修复四项发现；核对水域基线、暂存清单与磁盘输出。实施已本地提交，收尾修复另行提交，不push。

## Progress / Rulings

- Base: `6c297509`。
- Ruling: 用户已明确要求开始，沿批准设计直接实施，不增加计划审批回合。
- Ruling: 复用当前 develop 工作区和缓存，避免复制大量资源；无关改动不暂存。
- Ruling: 不采用技能默认的新增 TDD 测试；仓库 AGENTS.md 的测试约定优先，既有加载专项检查除外。
- Ruling: 仅需表面与粒子两类绘制组件，五种机制以着色器和配置区分，避免重复生命周期代码。
- Pre-flight: Task 1 的局部 mask 几何由 Task 2 统一验证、Task 3 统一采样；Task 2 工厂同时承担资源准备与实例化，避免两份类型清单。
- Task 1–3: 首批正式场景创建28个实例（含主体和水域），有界预览7个构图正常结束，无脚本/Shader错误；随后新增落点飞沫，最终预期29个实例。26张技术图RGBA8约15.58 MiB，PNG约1.11 MiB。
- Ruling: 完整飞艇暂不启用。现有正式高清主体是无独立外轮廓的RGB裁切，旧目录只有低清单桨/藤尖和已撤回的补底，缺少与当前8K一致的完整分层及可靠索具遮挡。按已批准设计保持内部微动并交付花叶/花瓣局部风动，不冒充完整飞艇完成。
- Ruling: 静态候选表在180秒内避免事件交叠，局部禁用导致相位错开时采用连续优先级衰减，代替重新排队或硬切。所有常态动作保留。
- Visual correction: 原瀑布候选位置未覆盖上游两级落差；已根据原生图块坐标重描两个内部水带，落点雾与飞沫移到对应跌水下端。
- Implementation commit: `c74024bf`；29个正式实例和61项首屏资源已在修订后运行日志中确认。
- Review: 独立审阅发现2项Important（同事件广播破坏局部恢复、颜色数组引用外泄）和2项Minor（风动周期未消费、树冠与菇缘重叠），全部修复。类别最大包络只参与优先级占用；参数深复制；局部风周期生效；最终蒙版非零覆盖交叠为0。
- Runtime evidence: 教堂暗化恢复时局部时间10.1秒、权重0，窗光仍为1；暂停/恢复的暗化时间10.2→10.2→10.3，关闭的dust保持隐藏；清空调用方颜色数组后有效值与总线快照均保留三通道。正式返回按钮到菜单、SceneTransition回地图均就绪，重新进入仍为29实例。
- Validation: 已有七项检查均退出0并输出PASS。boot和toolbar的headless运行各报3条既有主菜单custom_samplers编译器错误，补做图形运行无该错误；boot图形退出见一次既有ObjectDB回收警告。最终地图录制、导航与资源导入无脚本/Shader错误；不据此宣称长期性能或用户视觉验收通过。
- Evidence: `D:/Dev/PvZ/_review/wonderland_environment_20261116/` 交付单个28秒1280×720预览、单张代表帧联络图、汇总JSON及必要日志/复现脚本。录制原帧缓冲3451×1944，输出经过缩小，不作为1440p原生清晰度验收。
- Cleanup limitation: 本轮中间截图和隔离缓存的清理被自动审批策略拒绝，改为明确单个隔离目录仍被拒绝；未改用其他方式绕过。目录保留38,130,013字节（约36.4 MiB），其中隔离缓存8,017,807字节。原始素材、其他任务文件和正式存档未触碰。
