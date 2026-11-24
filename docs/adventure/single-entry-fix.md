# 冒险单一入口修复记录

2026-11-02；起始 HEAD：38f958a。开始时仅有未追踪的 test_map_assets.gd.uid，本次一并收录该既有测试的 Godot 元数据。

## 行为与集成

原生档案 UI 的链路保持为：User 的玩家按钮选择 → 好按钮 → SaveService.save_now() 保存当前玩家 → UserManager.set_current_user() → Global.reload_session_for_current_user() 读取对应全局状态和配置。

主菜单原冒险按钮现在直接调用 AdventureSession.open_adventure()，先验证当前用户名属于 UserManager 玩家列表且既有用户目录存在，再加载 user://<用户名>/adventure/zombie_island_v1.json。身份变化的原生 signal_users_update 会释放旧 progress 引用；每次从菜单进入均重新读取当前档案。

文件不存在时，island_progress.initialize_if_missing() 才初始化并保存默认状态；失败恢复未开始状态，不发布 progress，也不进入地图。已有文件只读，不备份、不重置、不因导航重写。损坏、版本不兼容、无效状态、写入失败明确提示且留在菜单。没有有效玩家时提示使用左上角档案 UI，旧游客档不会被读取、删除或迁移。

首次引导仍完全由持久化 intro_completed 决定；未完成可从头重播，两张初始卡沿用幂等逻辑。格式版本、文件目录、卡牌结构、对白、地图与战斗保持兼容。删除 island_menu.gd 及 UID，移除 session 中旧新游戏/继续/游客路径。start_new() 仅保留为状态层测试/未来专用管理 API，生产入口没有调用路径。

原 SaveService 自动存档隔离实现未修改；地图到战斗、返回地图期间仍隔离，回原菜单后仍恢复。

## 修改文件

- scripts/ui/start_menu/start_menu_root.gd：直接导航与单个错误提示。
- scripts/adventure/adventure_session.gd：唯一入口、原生身份校验与旧进度引用失效。
- scripts/adventure/island_progress.gd：只初始化缺失文件、首次保存失败原子性、移除诱导重开的错误文案。
- scripts/adventure/zombie_island.gd：编辑器直启地图不得绕过档案入口。
- 删除 scripts/adventure/island_menu.gd 及 .uid。
- tests/adventure/test_island_flow.gd：通过实际主菜单按钮与原生创建/选择 UI 驱动，取消旧新游戏/继续替代流程。
- tests/adventure/test_adventure_entry.gd、.gd.uid、.tscn：入口、身份、故障与重启验收。
- tests/adventure/test_map_assets.gd.uid：补收录原测试生成的 UID。
- 本记录。

## 实际验收

使用本机 Godot 4.7.2。所有测试 APPDATA 隔离在 .godot/entry-test-user 或 .godot/entry-test-user-boundaries，未修改真实玩家存档。不同套件使用不同目录，重启探针与其前序用例顺序执行。

- A/B：原生创建玩家、选择并点击实际冒险按钮，直接创建地图并显示七句；完成后重进不显示引导。已有存档字节保持不变。
- C/H：图形运行 test_island_flow 场景，通过实际种植、自然十波及真实奖杯结算开放第二关；菜单重进解锁保留；0.1 秒自动存档隔离及恢复验证通过。胜利清怪使用原项目调试入口。
- D：第四句发卡后退出地图，重进仍有未完成引导，已有文件不被导航重写；完成/跳过后仍各一张。
- E/I：原生玩家按钮 A/B/A、同帧双击同一冒险按钮、原生重命名面板、原生删除确认处理、第二个 Godot 进程读取当前玩家档案均通过。
- F：测试档中损坏 JSON 和 version=999 都被拒绝，明确错误，原文件字节不变。
- G：在测试文件 .tmp 位置创建目录使真实写入失败，入口拒绝且不发布进度；移除该测试障碍后同一入口安全重试成功。
- J：未选择玩家时留在原菜单显示错误，人工构造的旧游客哨兵文件保持原样。
- H 的其他模式：迷你、解密、生存原按钮仍进入原选关场景。
- Godot 编辑器导入、状态验收、git diff --check 均执行。最终日志不包含 SCRIPT ERROR、Assertion 或 FAIL。

日志：.godot/entry-import-final.log、entry-progress.log、entry-visual.log、entry-boundaries-final.log（图形边界）、entry-boundaries-isolated.log（含其他模式）、entry-restart-final.log。截图仍在忽略的 .godot 中，不提交。

图形验收由实际 Godot 窗口和场景自动驱动，并检查运行截图；未声称纯手动无辅助完整通关。原有四张僵王贴图缺失及相关资源报错、退出时对象/资源残留仍存在，未扩展本次范围处理。

人工复查：F5 → 左上角创建/选择 A → 冒险 → 完成/跳过戴夫 → 返回菜单 → 冒险应直接地图；再切换 B/A 核对独立进度。退出程序重启，选择原玩家后点击冒险应保留原进度。无有效玩家时只能得到选择档案提示。此前交付记录中的“新游戏/继续”说明已由本文替代。
