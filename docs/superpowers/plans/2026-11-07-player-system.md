# 玩家角色系统 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. 按任务顺序原地实现，保留用户现有改动。

**Goal:** 工具栏玩家窗口、独立装备库存、装备效果和经验升级完整接入。
**Architecture:** 定义、持有状态、服务、事务、战斗快照、UI 分离；统一档案保存。
**Tech Stack:** Godot 4.7.2 / GDScript / Resource。
**Spec:** docs/superpowers/specs/2026-11-07-player-system-design.md

## Global Constraints
- 中文文档注释与局部变量用途注释；不新增/运行测试。
- 不覆盖用户原有未提交改动，不创建第二存档或全局装备单例。

## Review Focus
- 装备/领奖保存失败完整回滚；换档后的窗口与动画不能写新档。
- 缺失旧档字段可迁移，损坏现有字段拒绝；经验溢出/跨多级有界。
- 重复结算不重新抽奖或叠加倍率；普通接噩梦和原版不泄漏效果。
- 装备背包不混入道具；空库存可用且不自动赠送。
- 工具栏互斥、切场清理、任务教学、关闭回调身份正确。

## Task 1: 数据与成长
- [x] 新建 scripts/adventure/player/ 内 definition/catalog/state/service/effects/progression/transaction。
- [x] 新建 resources/adventure/equipment/*.tres 静态定义；AdventureState 序列化装备、归一化等级。
- [x] QuestService 领奖用 PlayerProgression.grant(state, amount)，同期回滚等级；Global 等级设置委托成长规则。

## Task 2: 战斗效果
- [x] AdventureSession 冻结 PlayerEffects，提供当前战斗有效快照查询，重置时清除。
- [x] DropPool/RewardService 接受显式效果参数；金币生成冻结金额；收集策略按模式隔离。
- [x] 拾取绑定原档案和战斗，拒绝动画跨档入账；保留单次收集。

## Task 3: 窗口与入口
- [x] 新建 player_window/player_panel_view/player_portrait 表现层；装备网格与六槽、详情、成长进度。
- [x] ToolbarController 统一模态引用，注册 player，保留任务教学查询与输入控制。
- [x] 接入全局玩家变更通知；窗口成功事务后刷新。

## Task 4: 验证与复核
- [x] Godot --headless --editor --quit 解析和资源导入，不运行测试场景。
- [x] git diff --check；审查所有新增代码、资源及与基线的差异。
- [x] 一名独立 reviewer 只读复核本次范围；修复重要问题，记录实际验证范围。

## 进度与决策
- Ruling: 用户已授权开始实现，计划落盘后继续执行，不再请求相同授权。
- Ruling: 复用当前 develop 工作区，因为接入点包含大量用户未提交实现；不自动提交。
- Ruling: 仓库明确不测试覆盖技能 TDD 默认要求；只做解析、资源与静态检查。

## 完成记录
- 数据/成长、战斗效果、角色面板、统一模态、开发控制台的正式事务入口已完成。
- 经验通知由任务窗口提交成功后发出，QuestService 保持注入式业务边界，不调用全局 UI 信号。
- 用户补充要求已落实：原样复用美食大战老鼠 1–80 级角标，超过范围显示真实等级文字。
- Ruling: 原素材含数字，直接显示对应完整角标；不拆底图或重复叠字。
- Ruling: assets 默认忽略，增加仅针对 assets/adventure/ui/player 的白名单，确保素材与脚本可以一起交付，不修改其他资源的忽略范围。
- 独立只读复核完成，无 Critical/Important 发现；未进行故障注入或真实档案交互测试。
- 完整项目 Godot 4.7.2 headless editor 导入退出 0，未见 ERROR/WARNING。隔离 user:// 的真实 UI 渲染退出 0、无错误，产物 C:/Dev/PvZ/_review/player-panel-preview.png。
- 单脚本 --check-only 不能提供本项目 Autoload 上下文，报连带依赖错误，不作为本项目解析结论；改用完整编辑器加载与隔离渲染确认。
- 隔离预览发现并修复不受支持的 %g 格式符、SVG text 图标，调整长装备名、文字对比度和经验条。未新增或运行测试；仅更新已有测试失效的模态引用。
- 已有用户工作区改动保留，未提交或推送。
