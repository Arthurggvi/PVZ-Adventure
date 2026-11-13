# 海滨菜单制作工具

`menu.py` 是离线入口。运行结构见 [海滨菜单](../../../docs/adventure/main_menu_runtime_pipeline.md)，操作见 [素材管线](../../../ASSET_PIPELINE.md#海滨与天气)。

`build` 重建技术贴图，`render` 由 ArtControl 调用 Godot 录制，`workfile` 生成 GIMP 工作文件，`publish-runtime` 更新游戏用的原生纹理。参数见 `python menu.py --help`。制作环境从 `--tools-config` 读取本机路径。
