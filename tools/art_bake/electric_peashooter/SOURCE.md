# 电能豌豆：PvZ2 国际版 6.1.1 原始资源

本目录保存从国际原版 6.1.1（Android build 254）取得的 PAM、Wwise 音频库、逐字段动画解码记录、相关属性以及 Godot 转换器。美术没有重绘、换色、增删装饰或修改原动作；各等阶换色由运行时的电系公共材质完成。

来源包：Internet Archive 的 [PvZ2 Android 原版版本存档](https://archive.org/download/pv-z-2-android/48%20Plants%20vs.%20Zombies%202%206.1.1%20%28254%29.zip)。成员为 `PvZ 2 6.1.1 (254).apk` 与 `com.ea.game.pvz2_row/main.254.com.ea.game.pvz2_row.obb`。完整备份留在工作区外层 `_review/electric_peashooter/`，不放进游戏仓库。所有原游戏美术和声音权利属于其原权利人。

## 可重复转换

在任意目录运行：

```powershell
python D:\Dev\PvZ\PVZ-Adventure\tools\art_bake\electric_peashooter\bake.py
```

转换器只需要 Python 标准库，读取本目录 `source/` 的原 PAM 解码数据和图集区域，重建三个独立 Godot 场景以及五个不连续重复的音频随机容器。转换保留 30 fps、完整仿射矩阵、颜色乘数、保留式显示列表、原始绘制顺序及 stop 帧。所有子符号均为单帧，转换器对此有断言。`_custom` 是未装备的装扮槽，不参与基础植物显示。

战斗飞行图集通过同目录的 `bake_flight.py` 单独重建，依赖 Pillow 和 NumPy。输出 `flight_atlas.png` 将原球面裁尾、三套 30 fps 循环及两种出生电光合入一张遮罩，根点保持在球心。RGB 分别为主电色、白芯、辅色的权重，实际等阶仍由运行时色表决定。

重跑原始提取前，从同目录的 `pvz2_original_6_1_1.zip` 解出原始 OBB 为 `pvz2_main_6_1_1.obb`。原始提取过程保存在 `_review/electric_peashooter/extract.py`、`install_sources.py`、`install_hit.py` 和 `decode_audio.py`：按 OBB 资源表定位 `PlantElectricPeashooter_*`、`PlantLightningReedHit_*`、`Packages`、`WiseAlwaysLoaded` 与 `WiseInit`，解压 RSG 分段，读取其文件名表与偏移；RTON 使用已有 pyvz2rton 解码器，PAM 使用已有 `decode_grave_pam.Reader` 逐字段解码。PTX 为 ETC1 RGB 加 A8，不改像素颜色，解码后 PNG 分别是 1024×2048 与 256×256。原 PAM 和 PTX 的校验记录见 `source/sha256.json`。

音频先由 wwiser 解析 `GLOBAL_DATA.BNK` 中的事件树，再按 `PLANT_ELECTRICPEASHOOTER.BNK` 的 DIDX/DATA 导出指定 WEM，用 vgmstream 转为 PCM WAV。`source/audio_events/*.txtp` 保存完整事件层级、随机规则和相对增益，`audio_events.json` 保存 WAV 名称到原媒体 ID 的映射。原植物 BNK 一并保留，可重新解码；WAV 没有合成替换、变速或音高处理。

## 输出与坐标

| 输出 | 约定 |
| --- | --- |
| `electric_peashooter_visual.tscn` | 根 `ElectricPeashooterVisual`，直属 `Rig` 和 `AnimationPlayer`；原脚底 `(200,240)` 移到零点，Rig 为 0.7；36 个有序图层。 |
| `electric_peashooter_effects.tscn` | 根 `ElectricPeashooterEffects`；原球心 `(195,195)` 移到零点，Rig 为 0.7；48 层。 |
| `electric_peashooter_bolt.tscn` | 专属原电弧加原注册表要求的 LightningReedHit，独立打包两张图集，完全不依赖旧芦苇资产目录；12 层。 |
| `card.png` | 原 idle 首帧，140×150 透明裁切，脚底根点 `(70,140)`；无缩放、重绘和换色。 |

本体首帧原像素包围盒为 `(154,120)-(257,245)`；脚底至头顶的项目显示高度为 84 像素，总包围盒高 87.5。攻击发射帧口心约 `(264,157)`，映射项目脚底坐标约 `(45,-58)`。原属性 `SpawnOffset(35,-32)` 使用原引擎 ArtCenter 与半分辨率坐标，不能直接当项目的脚底坐标。

电球的垂直向下电光是原 PAM 的设计；普通子弹没有 `RotateToMatchVelocity`，不要把电球整体旋转为向右拖尾。只有 Plant Food 子弹设置旋转跟随速度。

## 原动作与事件

| 原 PAM | 标签 | 原帧（含两端） | 转换动画 |
| --- | --- | --- | --- |
| 本体 | idle / idle2 / idle3 | 0–39 / 40–79 / 80–87 | 同名 |
| 本体 | attack | 88–158 | attack |
| 本体 | plantfood | 159–237 | plantfood |
| 本体 | water | 238–246 | water |
| Electroball | animation / animation2 / animation3 | 40–79 / 80–119 / 0–39 | projectile / projectile2 / projectile3 |
| Electroball | animation5 / animation6 | 120–159 / 160–199 | plantfood_sub / plantfood_projectile |
| Electroball Effects | animation | 0–14 | bolt；effects 中同时保留兼容名 impact |
| Electroball Effects | animation2 / animation3 | 15–50 / 51–86 | plantfood_impact / plantfood_sub_impact |
| LightningReedHit | idle / idle2 / idle3 / idle4 | 0–22 / 23–47 / 48–58 / 59–70 | hit / hit2 / hit3 / hit4 |

`attack` 相对帧 1 播 Attack_Start，34 播 Attack_Fire，38 执行 `use_action`。`plantfood` 相对帧 1 播 Plantfood_Start，37 播 Plantfood_Fire，40 执行 `use_action`。`idle` 相对帧 2 播 Idle_01；idle2/idle3 相对帧 1 各引用 Idle_02/03，但 6.1.1 的 GLOBAL_DATA 事件表没有这两个事件（FNV IDs 650299525/650299524），应保持静音。

Idle_01 是 8 选 1 的 -10 dB 随机层加一层固定音；Attack_Start 为 3 选 1；Attack_Fire 为两个同时播放的 3 选 1 随机层（body -10 dB，zap 0 dB）；Bolt_Fire 为 3 选 1。实际随机池均 `avoidRepeat=1`，对应 Godot AudioStreamRandomizer 的 `PLAYBACK_RANDOM_NO_REPEATS`（`playback_mode=0`），枚举值依照 [Godot 4.7 官方文档](https://docs.godotengine.org/en/4.7/classes/class_audiostreamrandomizer.html)。每道弧触发原 `Play_ElectricPeashooter_Bolt_Fire`，并非只在发射时播放声音。

电弧源起点 `(195,195)`、终点约 `(325,195)`；Rig 0.7 下参考长度 91 像素。原 15 帧电弧的首尾帧透明，原引擎每次电弧可见时长为 0.15 秒，运行时据此加速播放整个片段。

## 原始属性与原生行为证据

`source/original_properties.json` 保留 PlantProperties、ProjectileTypes、PlantLevels 和 PlantTypes 中电能豌豆的全部条目。一级原参数：200 阳光、300 HP、卡冷却 5 秒、攻击冷却 2.25–2.4 秒、穿透直伤 5、放电伤害 20、频率 0.5 秒、最多 2 个目标、范围 2。ProjectileTypes 默认速度为 333，但 PlantLevels 的一级 `ActionXVelocity` 明确覆盖为 180。

原 PlantTypes 的资源组明确包含 `PlantLightningReedHit`，因此使用该原受击动画是原版自身依赖。普通穿透电球没有 ImpactPAM，不添加碰撞爆炸；Electroball Effects 的第一个 animation 实际是专属电弧，第二、三个才是 Plant Food 爆炸。

6.1.1 APK 中 `libPVZ2.so` 的本次只读反汇编记录留在 `_review/electric_peashooter/electric_native_discharge.txt`、`electric_native_init_tick.txt`、`electric_native_radius.txt`：

- `0x408284` 每轮重新收集目标；僵尸（type 2）优先，`0x4089a8` 用 Fisher–Yates 随机洗牌选最多 BoltCount 个，数量不足再从 griditem（type 4）随机补足。没有跨放电轮次的命中过滤。
- 首次放电延迟在 `0..BoltFrequency` 随机；后续按频率触发。
- 原范围为 `BoltRange × 64 = 128` 的圆形半径，查询辅助函数比较平方距离，不是两条邻行各一个目标。
- 每条弧显示 0.15 秒。`0x407074` 调用字符串位于 `0x1209b51` 的 `Play_ElectricPeashooter_Bolt_Fire`。

原生库不放进生产仓库。这里记录的是读取原版资源及二进制所得到的证据，不以社区二创参数替代原参数。

## 验证范围

已渲染并目视检查原本体 idle、attack、plantfood 关键帧，三种电球及电弧/命中图像；解码音频均为原指定 WEM 的 PCM 输出。按照项目 AGENTS.md，未新增或运行测试；Godot 导入和全局整合检查由本次任务主代理统一执行。
