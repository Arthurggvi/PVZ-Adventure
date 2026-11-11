# 白爵士二阶段 — 白炎与聚光灯
权威效果场景：res://scenes/fx/white_flame_spotlight_effect.tscn
配置脚本：res://scripts/fx/white_flame_spotlight_effect.gd
角色开关：WhiteDukeVisual.set_phase2()，仅二阶段开启。

来源与处理：
- 白炎火舌：复用项目原版 assets/reanim/fire1.png 至 fire8.png 及 fire4b.png、fire5.png，保留手绘火舌轮廓，改成白/银蓝调。
- 细长上升火舌：复用原版 assets/reanim/FirePea_flame1/2/3.png 并朝上重采样；Godot CPUParticles2D 驱动漂浮、淡出。
- 连续白炎：8 帧火舌底层通过 Godot AnimatedSprite2D 循环，位于原版舞王身体后侧。
- 聚光灯：锥形光束与脚下椭圆光池为轻量透明 PNG 光照遮罩，供 Godot 2D 直接渲染。
- MUGEN/其他外部备选未导入：火球、像素能量光环或写实烟雾均不能直接替代 PVZ 风格周身白炎。
- 本特效不依赖独立动画骨架，主体待机仍复用 Zombie_Jackson_moonwalk.tres。

## 召唤与传送动作资源
- 召唤角色动作直接复用原版舞王 AnimationPlayer 的 point，不重做关键帧；白爵士视觉入口为 WhiteDukeVisual.play_summon()。
- 聚光灯仍由本场景控制，原有白色光束加深；召唤时一阶段临时聚光，二阶段在不连续重复的五色调色盘中随机切换并触发附加光束闪亮。
- 传送漩涡沿用黑将军 BlackGeneral_TeleportBlink.tres 的 arrive/depart 帧与原有 teleport_in/out.tres 的特效时间轨道。适配器为 BossTeleportAnimationFactory，只投影可复用轨道，不重做人物骨架。
- 遮挡烟雾由黑将军原有 BlackSmoke_Back_5x6_RGBA.png 裁片改色而成，复用 Godot CPUParticles2D，覆盖人体后才切换角色可见性。
- 传送效果权威场景：res://scenes/fx/boss_teleport_effect.tscn，控制器 res://scripts/fx/boss_teleport_effect.gd。
- 本轮只完成召唤、传送入场、传送离场的视觉动作入口，不包含未策划的召唤援军种类、战斗行为树或攻击逻辑。
