# 闪电芦苇美术资源

素材来自 PopCap / EA《植物大战僵尸 2》国际版 Android 5.8.1（232）的 OBB。图集从 `PlantLightningReed_1536` 提取，卡面插图从 `UI_SeedPackets_1536` 提取。两套场景的动作从 `PlantLightningReed_Common` 的 PAM 按原始 30 帧/秒转换为 Godot `AnimationPlayer` 轨道。使用基础外观，图集只保留场景使用的部件。[原版资源包存档](https://archive.org/download/pv-z-2-android/45%20Plants%20vs.%20Zombies%202%205.8.1%20%28232%29.zip)

- `res://scenes/character/plant/lightning_reed_visual.tscn` 的原点位于根部，默认循环 `idle`。还可预览 `idle2`、`idle3`、`idle4`、`water`、`attack` 和 `plant_food`。`attack` 与 `plant_food` 均为 1 秒，原 PAM 的 `use_action` 标记在片段开始后第 4 帧。
- `res://scenes/character/plant/lightning_reed_effects.tscn` 提供 `bolt`、`bolt_default`、`hit` 及其变体，以及 `plant_food_cloud_*` 和 `plant_food_bolt*`。场景初始隐藏图层，选中 `AnimationPlayer` 即可挑选片段预览。电弧原点靠近起点，命中特效原点靠近被击中的位置。
- `lightning_reed_card.png` 是原版透明卡面插图。卡牌外层控制缩略图大小，内层贴图以根部对齐手持和落点预览。
- `sfx/` 包含 `PlantLightningReedAudio` 的 9 个普通放电样本。根据 `WiseAlwaysLoaded` 中的 `Play_LightningReed_Fire` 事件恢复随机变体和音量分层。按出战卡的 0～2、3～5、6 星及以上映射原版三个音色层级。
