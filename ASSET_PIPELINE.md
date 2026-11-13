# 素材与动画

新增素材在 `assets/adventure/`，场景在 `scenes/`，角色动画在 `animation/`。本地原版和字体按 [开发说明](DEVELOPMENT.md#首次检出) 补齐。保留用于导入的源贴图、音频、旁置 `.import` 和脚本或材质的 `.uid`。海滨使用的原生 `.res` 属于运行素材。导入缓存由 Godot 重建。

## 拆件与动画

1. 确认可复用部件、画布尺寸、透明通道、层级和定位点。跨帧保留稳定部件 ID，保持原点和命名。
2. 通过 `addons/R2Ga_PVZ/` 的编辑器工具选择本地 `.reanim` 输入，输出后核对轨道目标、首末帧和方法事件。原版拆件库的 `assets/all_reanim/` 是开发输入。
3. PAM 动画转换可参照 `scenes/character/zombie/all_star_original_animations.tres` 和全明星场景。连续帧继承增量字段，原 ref ID 维持分件身份。验证原生播放、攻击和受击时同时核对卡面与图鉴。
4. 审稿图、GIF、录屏、工作稿与源素材备份放项目外。任何移除都要检查动态路径、资源 UID、JSON 映射、动画方法轨道和导出。归档应保留原路径及 SHA256。

## 海滨与天气

运行纹理由 `assets/adventure/main_menu/coastal/texture_catalog.json` 映射到原生 `.res`。用 `tools/art_bake/main_menu/menu.py` 的 `publish-runtime` 发布已审核的制作资产，`runtime-preview` 从正式场景录制，`effects-preview` 验证效果替换。制作工作目录和 ArtControl 配置通过参数传入。见 [运行管线](docs/adventure/main_menu_runtime_pipeline.md) 和 [效果接口](docs/adventure/main_menu_effects_api.md)。

图形模式运行 `res://tools/weather_preview/battle_preview.tscn`，从第四关资源初始化实际战斗并把天气采样写到 `%TEMP%/pvz_weather_battle_preview`。给预览进程单独设置 TEMP 和 APPDATA。纯效果预览是同目录的 `weather_preview.tscn`。
