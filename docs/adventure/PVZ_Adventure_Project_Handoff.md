# PVZ-Adventure 项目交接

从 `project.godot`、场景、脚本与配置资源核对仓库现状。

## 启动/加载权威协议

`scenes/main/00Bootstrap.tscn` 经统一的 `SceneTransition.change_scene()` 进入正式海滨菜单。地图、战斗与返图沿用同一接口，战斗状态只在目标场景被接受后提交。卡牌、角色、音效及工具栏沿用既有惰性门面。各入口的依赖所有权、失败恢复与图形验收见 [启动与场景加载](startup_loading.md)。

## 开发入口

- [DEVELOPMENT](../../DEVELOPMENT.md) 记录引擎版本、素材还原、测试和 Windows 导出。
- [ARCHITECTURE](../../ARCHITECTURE.md) 记录关卡、续战、棋盘、水路、天气、Boss、卡牌和存档。
- [ASSET_PIPELINE](../../ASSET_PIPELINE.md) 记录素材拆分、动画和预览。
- [棋盘配置](board_authoring.md)、[海滨菜单](main_menu_runtime_pipeline.md)、[效果接口](main_menu_effects_api.md) 与 [戴夫对话](native_dave_conversation.md) 记录系统特有的维护流程。

修改后以本次导入日志、测试、导出及独立目录实机结果为证据。测试使用隔离档案。
