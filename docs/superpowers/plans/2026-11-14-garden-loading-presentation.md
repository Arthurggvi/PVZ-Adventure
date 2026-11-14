# 花园加载界面实施计划

**Goal:** 将 Bootstrap、场景切换和功能窗口加载统一为温和、连续、与游戏美术一致的表现；不增加人为等待。

**Architecture:** 继续使用现有 SceneTransition/ResourceBatch。新增只负责绘制的 LoadingPresentation；场景通过目标 metadata 交接表现快照，功能窗口复用紧凑版并平滑退出。无新增 Autoload、后台管理器或资源缓存。

**Tech Stack:** Godot 4.7.2，原生 Control/CanvasItem、轻量纹理和 Tween。插画由内建 imagegen 生成；Godot 导入限制最长边 512px。

## 视觉与交互决定

- 采用暖墨绿、蜂蜜金、米色字，中心是向日葵与豌豆射手的小花园；进度沿用原版泥土/草皮纹理。
- 全屏版本留白、柔和光晕、低幅呼吸动效；窗口版本保留原场景，用小幅遮罩和暖纸色卡片。
- 短请求延迟展开内容，不强制最短停留；完成时立即交接，以淡出收尾。
- 不显示会归零或提前达到100%的数字；进度只单调平滑推进，构造阶段继续保留轻微活动感。
- 加载中取消立即撤销业务请求，视觉可短暂淡出但不能阻挡后续输入。失败提供明确可关闭/重试动作。
- 保留原状态提交、失败回滚、档案身份校验与两帧揭幕协议。

## 公共表现接口

`scripts/ui/transitions/loading_presentation.gd` extends Control:

- `configure(heading: String, detail: String = "", compact: bool = false)`
- `set_progress(amount: float)`：单调显示，正常加载最多0.94；`finish()`允许到1，但不等待动画完成。
- `set_detail(text: String)`、`show_error(message: String)`
- `set_content_visible(value: bool, instant: bool = false)`：只控制内容淡入，宿主仍拥有输入锁。
- `set_action(text: String, callback: Callable)`、`disable_action()`、`focus_action()`
- `snapshot() -> Dictionary`、`restore(state: Dictionary)`：标题、说明、已显示进度、动画时间与显隐；不保存业务对象。

## Tasks

- [x] 1. 生成/导入单张透明插画，制作共享全屏与紧凑表现，检查尺寸和原生缩放。
- [x] 2. 场景与 Bootstrap 接入，快照保持源/目标连续，进度分阶段映射且构造期间不变回空黑幕。
- [x] 3. 模态和地图选择器接入；按入口显示文案，短加载克制展开，发布/取消平滑退出且不阻挡输入。
- [x] 4. 按 AGENTS.md 专项运行已有隔离验收，图形观察交接、紧凑/失败、不同窗口尺寸；完成独立审查，随本计划创建本地提交。

验收记录见 `docs/adventure/startup_loading.md` 第七节。短请求不增加停留由接入逻辑及正式窗口验收确认；截图驱动的观察等待仅用于采样。独立审查发现的淡出按钮焦点和被忽略资源未跟踪问题均在提交前处理；既有 ObjectDB 退出告警仍保留为未解决边界。

## Review Focus

- 短请求不能为了展示插画增加等待；暂停和倍速不能改变加载动效时间。
- 源场景释放后，目标表现不能闪回空黑、回零或重置动画相位。
- 取消反馈淡出后不能清掉新窗口、抢焦点或拦截底层输入。
- Bootstrap只增加512px单图、两张小加载条和小英文字体，不静态引用任何角色/功能场景或大型中文字体。
- 保留已有project.godot及未跟踪UID；只提交本次文件，不push。不新增测试套件。
