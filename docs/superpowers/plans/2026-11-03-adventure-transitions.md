# Adventure Transitions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans。沿用用户一次完成的执行要求。

**Goal:** 为 V8 地区纸图开关、进入僵尸岛与地图返回菜单加入短促连续的动效。

**Architecture:** ModalMotion 封装弹层表现和 Tween 生命周期；SceneTransition 封装每个场景的遮幕、输入锁和失败恢复。两者作为可编辑场景组件复用，不新增 Autoload，不在目录或存档中写动画。独立 MotionRoot 包裹原设计画布，避免动画与等比适配竞争。

**Tech Stack:** Godot 4.7.2、GDScript、Tween；不增加资源或依赖。

**Spec:** 用户本轮动效与架构要求；原地区选择任务的存档、锁定、BGM与视觉验收约束继续有效。

## Global Constraints

- 当前指定 checkout 施工，保留既有玩家、存档、进度、音乐和环境 FX 逻辑。
- 不修改 layout.json 坐标或 PNG；不录屏、截图、GIF或全量回归。
- 原路由仍由 AdventureSession.open_adventure() 执行；场景切换失败恢复输入并展示既有错误。
- 中文用途注释符合 AGENTS.md；动效时长与参数通过 Inspector 配置。

## Review Focus

- 快速 ESC、重复关闭/选择及场景销毁不能留锁、双路由或悬挂 Tween。
- 动画变换与窗口调整互不覆盖，完成后几何完全回到配置位置。
- 遮幕到目标场景的首帧连续，失败揭幕并恢复输入，不提前写入进度。
- 场景初次揭幕和原戴夫引导暂停可共存，Tween 不受游戏速度或暂停影响。
- 已有入口测试同步等待显式动效状态，不用任意长 sleep。

### Task 1: 封装纸图开关动效

**Files:** 新增 scripts/ui/transitions/modal_motion.gd、scenes/ui/transitions/ModalMotion.tscn；修改 Picker 场景/脚本及定向测试。

- [x] 先在现有验收中断言动效组件存在，验证缺失时失败。
- [x] 新增 MotionRoot，透明度、轻移与缩放使用独立表现层；输入锁、快速关闭与 Tween 销毁归组件生命周期。
- [x] 同步既有测试的节点路径及条件等待；保留所有旧验收范围。

### Task 2: 封装场景遮幕与最小接入

**Files:** 新增 scripts/ui/transitions/scene_transition.gd、scenes/ui/transitions/SceneTransition.tscn；最小修改 V8 与 zombie_island 场景/脚本。

- [x] 每场景单实例遮幕，约 0.18 秒揭幕、0.16 秒覆盖；Tween 绑定组件并独立于暂停/时间倍率。
- [x] V8 通过遮幕调用原冒险入口，失败恢复并显示原错误；地图返回按钮经同组件切回原 V8。
- [x] 状态等待适配旧入口测试，不改战斗、进度、音频逻辑。

### Task 3: 定向验证与交付

**Files:** 更新 tests/adventure/test_destination_picker.gd、既有入口测试、docs/adventure/destination-picker-motion.md。

- [x] 验证快速开关、重复输入、动画中调整窗口、最终坐标、场景往返与失败恢复；重跑地区选择及 V8 定向测试。
- [x] 隔离编辑器导入、diff 检查与一次独立只读代码审查。
- [x] 精确提交本次文件并报告 Hash；视觉质感由用户实机验收。

## 审查修复记录

独立只读审查发现一个 Important：旧安全入口可能返回 true 但没有实际切换，导致遮幕常驻。已先用成功但未离场的动作重现 RED，再在 SceneTransition 中验证原场景确已退出；失败信号由 V8 通过 Picker 公开恢复接口处理。原进度与文件不变。正常切换立即把旧组件移出树，SceneTree 引用在动作调用前缓存。定向测试同时覆盖正常往返和错误恢复。未保留 Minor 待办。
