# 黑将军 Implementation Plan

> 执行方式：当前会话按 executing-plans 实现；仓库 AGENTS.md 的不新增/不运行测试要求优先。

**Goal:** 在没落营地噩梦末波后实装黑将军及共用效果。
**Architecture:** 角色负责生命周期，行为树负责选择，冲锋负责路径结算，设施负责令旗光环；生命与身体组件提供通用效果。
**Tech Stack:** Godot 4 / GDScript / 现有动画资源。
**Spec:** docs/superpowers/specs/2026-11-08-black-general-design.md

## 约束与复核重点

中文变量及函数注释；无新依赖；不覆盖现有工作区改动；不运行测试。复核：转阶段中断、低帧率冲锋、叠层植物与第二列、光环清理、末波退场结算。

- [x] 通用格挡（生命分流前一次扣减、来源移除）与 Boss 闪黑（独立颜色通道）。
- [x] 敌方设施受击接口、1500 HP 令旗及事件驱动光环。
- [x] 黑将军配置、行为树、冲锋组件、角色动画状态及生命周期。
- [x] 噩梦 50 波遭遇资源、无额外周期援军配置、退场完成边界。
- [x] 编辑器导入/资源引用检查、独立代码审查及最终差异复核。

接口约定：HpComponent.damage_block 接受来源与数值；ZombieManager.signal_zombie_created 广播登记完成的新僵尸；Boss 的 signal_trophy_requested 表示死亡演出完成；BlackGeneralBehaviorTree 只返回动作，不执行场景副作用。

## 实施记录

- 使用当前工作区，不提交或移动用户已有菜单/UI修改。
- 非战斗扣血通过 `HpComponent.apply_unblocked_loss` 明确旁路；大坚果处决、磁铁卸甲、梯子放置、自动破球与存档恢复保留原语义。
- 独立审查发现并修正：寒冰伤害触发阶段后迟到控制、冲锋伤害回调覆盖阶段状态、换行 reparent 导致光环误移除、卸甲/处决被格挡抵消。保龄球对设施沿用无护甲固定伤害。
- 未新增或运行测试/游戏。编辑器模式导入与黑将军/令旗场景载入、资源引用扫描以及 `git diff --check` 用于静态核对。
- 单脚本 `--check-only` 缺少本项目 autoload 上下文，引发 Global/GlobalUtils/SoundManager 未定义连锁错误；此命令不作为有效编译证据，改用完整项目编辑器导入。
- 检查日志位于工作区外 `D:/Dev/PvZ/_review/black_general_final_import_0.log` 和 `black_general_final_import_1.log`。实际战斗节奏、动画视觉与音效体感仍需游戏内验收。
