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
