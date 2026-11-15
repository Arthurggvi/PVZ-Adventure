# 双发射手四种转职弹 Implementation Plan

**Goal:** 重做地狱、晨星、辉夜与冥弹的完整视觉反馈，使弹体、尾迹和命中形成四种鲜明且可辨认的效果。

**Architecture:** 在现有纯视觉入口内替换对应弹种分支。生命周期、场景池及预算继续由已有代码管理。

**Tech Stack:** Godot 4、GDScript、CanvasItem shader。

**Spec:** ../specs/2026-11-13-repeater-hell-morning-design.md

## 约束与关注点

- 不新增或运行测试；采用隔离美术渲染与代码审查。
- 新增变量与函数按 AGENTS.md 使用中文注释。
- 同场多次触发不能产生无限粒子、残留节点或大面积不透明遮挡。
- 对象池复用必须重置特效类型、材质、年龄与方向。
- 游戏暂停时动画必须跟随可暂停的战斗时间。

## 实施

1. `repeater_abyss_visual.gd` 和 `repeater_abyss_vortex.gdshader`：替换地狱场的轮廓、流动与进退，保持 `configure(pitch, lifetime)` 和 `set_age(seconds)`。
2. `repeater_projectile_visual.gd`、`repeater_hades_trail.gd` 和 `repeater_visual_palette.gd`：四种弹体的有限带状尾迹、微光与配色，保持世界坐标采样与离场衰退，显式三角形避免短尾迹的多边形三角化错误。
3. `repeater_impact_visual.gd` 与 `repeater_celestial_impact.gdshader`：晨星、地狱、辉夜专用爆发，保持 `spawn`、`chain` 和对象池契约；火弹与分裂星传入正确绘制深度。
4. `repeater_galaxy_visual.gd`、`repeater_galaxy_cloud.gdshader`：辉夜体积旋臂与星核；保持物理接口、随机序列与 `_position` 几何不变。
5. `repeater_hades_impact.gd`、`repeater_hades_rift.gdshader`、`repeater_execution_visual.gd`、`repeater_silhouette.gdshader`：冥弹斩痕与有界处决副本的外观，保留真实死亡入口和身体遮罩。
6. 仓外 `_review/repeater_hell_morning_20261113`：双页原生渲染预览及实际文件快照；根据明亮草地上的画面修正过曝、遮挡与时序。
7. 审查最终差异及所有权，创建仅包含本任务文件的本地提交。

## 完成记录

四种效果已接入正式视觉入口。隔离美术工程使用 Godot 4.7.2 Compatibility 渲染，双页各输出192帧、6.4秒；最终两份渲染日志均完成且无运行或着色器错误。人工查看飞行、爆发、持续场、密集叠加与原生僵尸处决关键帧，修复了初版短尾迹的多边形三角化错误。独立代码审查未发现可操作缺陷，辉夜伤害几何与随机参数生成保持不变。

按仓库约定未新增、未运行自动测试，未执行完整战斗回归或性能基准。预览与来源记录位于仓外 `D:/Dev/PvZ/_review/repeater_hell_morning_20261113`。
