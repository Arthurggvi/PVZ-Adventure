# Boss 图鉴实现计划

> **For agentic workers:** 使用 superpowers:executing-plans 在当前会话逐项实现。

**Goal:** 在图鉴中新增 Boss 分类，为黑将军、白爵士提供属性、技能动画、效果说明及一二阶段切换。

**Architecture:** 复用图鉴木框布局和两位 Boss 的纯视觉场景。独立目录读取注册场景的属性及 config；独立 SubViewport 承载动作与特效，技能列表下方显示当前阶段的作用，人物描述保留用户原文。冒险图鉴新增 Boss 标签，旧图鉴索引增加同一页面的入口。

**Tech Stack:** Godot 4 / GDScript / 现有 AnimationPlayer 资源。

**Spec:** 本次用户消息；本文件记录具体界面和实现选择。

## Global Constraints

- 遵守 AGENTS.md：不新增或运行测试，中文注释，完成后仅提交本任务，不 push。
- 已有未提交改动保持原样；两位 Boss 直接可查，不修改发现记录。
- 不实例化战斗执行器进预览树，不生成实际援军、伤害、奖励。
- 用户提供的人物描述原样保存；技能数值读取场景配置。

## Review Focus

- 连续点击同一技能应从头重播；换技能取消上一段演示。
- 切阶段同时刷新外观、属性、技能说明；回一阶段恢复原样。
- 关闭、换分类、换 Boss 时释放预览及待播动作。
- 长技能说明和人物描述可滚动，不能挤出窗口。
- 白爵士的屏幕特效限制在预览视口内。

## 实现步骤

- [x] 新建 boss_almanac_data.gd：目录、描述、场景属性和分阶段技能说明。
- [x] 新建 boss_almanac_preview.gd：独立视觉场景与可中断动作序列。
- [x] 新建 boss_almanac_detail.gd：阶段选择、属性、技能按钮、下方效果和人物介绍。
- [x] 接入 almanac_window.gd 的 Boss 分类及旧 main_almanac.gd 入口。
- [x] 静态核对资源路径、动画名和改动差异，按仓库约定不运行测试；仅提交任务文件。

## 实施记录

- 根据用户后续纠正，将黑将军介绍中的“饼干”改为“罐头”。
- 单次动作通过 AnimationPlayer.animation_finished 推进，循环动作限制演示时长；中断传送时恢复身体缩放与可见性。
- 预览背景置于 -1000 图层，保留角色负图层部件和聚光灯；白爵士屏幕特效限制在 SubViewport 内。
- 独立静态审阅指出的动作结束时序和背景遮挡已修正；未发现其他明确阻塞问题。
- Godot 4.7.2 `--headless --editor --quit` 脚本解析退出码 0、标准错误为空；`git diff --check` 无空白错误。
- 按 AGENTS.md 未新增或运行测试，未进行运行时交互验收。
