# 原版戴夫顺序对话封装

入口：`scripts/ui/native_dave_conversation.gd`。

它实例化现有 `SceneRegistry.CRAZY_DAVE`，调用 `init_dave(CrazyDaveDialogResource)`；
进场结束后仍由原版 `start_dialog()` 循环、原生点击面板、`AnimationTree` 和语音长度规则驱动。
自然结束等待 `signal_dave_leave_end`。没有直接调用AnimationPlayer，也没有替代气泡或继续按钮。

使用前在入树前调用 `configure(resource, completion_guard, line_holds)`：

- `resource` 是原生 `CrazyDaveDialogResource`，用于一次性、无选项的顺序对话。
- `completion_guard` 可为空；否则须返回bool。拒绝时留在最后一句，不离场，下一次点击可重试。
- `line_holds` 是零基句索引到最短停顿秒数的字典，例如 `{3: 0.85}`。
- 监听 `line_started(index)` 执行业务事件，监听 `finished` 清理业务覆盖层。
- 原生面板点击和 `request_advance()` 经过同一输入校验；`skip()` 也经过完成校验。
- 原生商店常驻对话和选项分支保留原接口，不经过本封装。
- 入树前设置 `suppress_bgm = true` 可暂时暂停原BGM播放器；自然结束、跳过或切场景时
  恢复进入前的暂停状态，不停止/重启曲目，也不修改音量或总线静音。默认false保持其他调用者原行为。
- `is_crazy` 句仍走原版状态机。封装等待原版 `CrazyDave_crazy` 状态的结束通知再放行点击，
  不手动播放AnimationPlayer或按估计时长模拟帽子动作。

冒险引导使用 `resources/adventure/dave_intro.tres` 的十一句定稿台词；括号内的动作要求不作为台词显示。
第六句设置 `is_crazy=true`。第七句“拿着这个”沿用幂等发卡接口并显示两张原生卡牌，
第八句隐藏卡牌，在各自真实中心发射原生彩色星屑，播放一次礼盒 `prize` 音效。
最后一句和完成/跳过仍调用既有幂等存档接口；最后一句先持久化，再由原版离场。

卡片动画封装在 `scripts/ui/starter_card_reward.gd`：只复制AllCards的Catalog展示卡。
星屑直接复制原礼盒预制的GPUParticles2D（Star40、材质、数量及轨迹不变），按1066到1920坐标换算。
原礼盒实例从不入树，只提取粒子后立即释放，因此不触发礼盒自动收集、花园奖励或SaveService。

停顿使用组件拥有的Timer，释放时停止；不保留跨场景Timer await。
组件卸载时停止仍属于本次对话的戴夫语音，并恢复其临时接管的BGM暂停状态。

首次封装接入时（七句版本）的验证：Godot导入/解析退出0；隔离APPDATA中的图形运行检查退出0，覆盖未封装的
原版顺序循环、气泡真实鼠标输入、七句推进、第四句赠卡、完成校验拒绝后重试、原版离场、
进场/第三句停顿中跳过，以及停顿中切场景后的清理。新资源七句文字与原JSON逐字一致。
没有执行完整战斗/商店回归；仍有原工程资源失效UID警告。

十一句/赠卡补丁验证：一次Godot导入退出0，定向图形运行退出0。
核对原版应激状态及防连续跳过、两张卡入场、粒子与真实牌中心重合、一次prize、自然结束及离场期间BGM暂停、
跳过时恢复原先暂停/播放两种状态、卡片入场时切场景清理，以及原版金币/花园奖励和音频设置不变。
没有截图、录屏、GIF或完整战斗回归。
