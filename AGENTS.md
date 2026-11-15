# 提交约定

- 每次修改完成后，主动创建本地 Git commit，无需再次询问。
- 仅提交本次任务的改动，保留其他尚未提交的修改；不要自动 push。

# 测试约定

- 默认不新增测试、不运行测试，除非用户明确要求。
- 修改代码时，同步更新已有测试中的失效引用，但不主动扩展测试范围。
- 完成后如未运行测试，应明确说明，不得声称测试通过。

# 代码注释要求

- 注释默认使用中文，并遵循 Godot 的 GDScript 注释格式。
- 所有变量和常量都必须注明用途，包括成员变量、导出变量、局部变量和循环变量。
- 类说明、成员变量、常量、信号、枚举及函数说明使用 `## ` 文档注释；成员文档紧贴声明或其注解之前，类说明放在脚本头部。
- 函数内部的局部变量、循环变量及实现逻辑使用 `# ` 普通注释；简短说明可写在行尾。
- 函数参数在函数文档中使用 `[param 参数名]` 说明；同时说明有意义的返回值、副作用和边界条件。
- 文档引用使用 Godot 支持的格式，例如 `[member 名称]`、`[method 名称]` 和 `[code]代码[/code]`；需要强制换行时使用 `[br]`。
- 注释应说明用途、含义和设计意图；涉及单位、取值范围、特殊值或生命周期时，应一并说明，避免仅重复名称或代码。
- 修改代码时同步更新相关注释，确保注释与实现一致。

# 启动、资源加载与场景切换

- 权威设计与验收规范：`docs/adventure/startup_loading.md`，交接入口：`docs/adventure/PVZ_Adventure_Project_Handoff.md` 的「启动/加载权威协议」。
- `project.godot` 的冷启动入口只能是 `scenes/main/00Bootstrap.tscn`；正式菜单仍是 `01StartMenuCoastal.tscn`。不要把大量 UI、角色、音效、战斗模板加入 Bootstrap 的静态依赖。
- 所有正式场景转换必须复用 `SceneTransition.change_scene(path, after_switch)`；禁止为新区域、新模式或 Boss 再造 Loader、同步黑幕切场、独立全局缓存。回调只在场景被接纳后提交战斗态，失败保留原场景并恢复输入。
- `AllCards`、`CharacterRegistry`、`SceneRegistry`、`SoundManager`、`AdventureToolbar` 已有统一的惰性资源入口。扩展时只维护权威资源注册和门面，不得让 Autoload 随物种增加而重新预加载所有资源。
- 相关改动必须在隔离 `user://` 下运行 `tests/adventure/test_lazy_startup.tscn`、`test_lazy_audio.tscn`、`test_threaded_scene_loading.tscn`、`test_boot_to_menu.tscn`、`test_threaded_battle_route.tscn`、`test_lazy_toolbar_modal.tscn`；同时核对导航验收及图形过渡帧测试。测速要区分引擎 Autoload、Bootstrap 到就绪、图形首帧与实际发行包，不能混算。

# 本地运行日志与临时产物

- Godot 验证使用隔离的 `user://` 和单次运行目录，日志与临时输出放在项目所在数据盘。运行前设置超时，并同时限制终端输出和 Godot 自己写的日志。普通诊断每次运行默认最多保留 8 MiB 日志。遇到同一脚本错误连续刷屏时，停止本次验证进程，留首个堆栈及必要的日志尾部。
- `_review` 只留有明确用途的最小验收证据及必要源件。预览先用少量代表帧。验收后清理本次生成的临时工程、隔离测试档、逐帧图、重复解包和可重建缓存。优先复用现有工程与资源，保留正式存档和原始素材。
