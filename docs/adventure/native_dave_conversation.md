# 原版戴夫顺序对话封装

入口：`scripts/ui/native_dave_conversation.gd`。

它实例化现有 `SceneRegistry.CRAZY_DAVE`，调用 `init_dave(CrazyDaveDialogResource)`；
进场结束后仍由原版 `start_dialog()` 循环、原生点击面板、`AnimationTree` 和语音长度规则驱动。
自然结束等待 `signal_dave_leave_end`。没有直接调用AnimationPlayer，也没有替代气泡或继续按钮。

使用前在入树前调用 `configure(resource, completion_guard, line_holds)`：

- `resource` 是原生 `CrazyDaveDialogResource`，用于一次性、无选项的顺序对话。
- `completion_guard` 可为空；否则须返回bool。拒绝时留在最后一句，不离场，下一次点击可重试。
- `line_holds` 是零基句索引到最短停顿秒数的字典，例如 `{2: 0.85}`。
- 监听 `line_started(index)` 执行业务事件，监听 `finished` 清理业务覆盖层。
- 原生面板点击和 `request_advance()` 经过同一输入校验；`skip()` 也经过完成校验。
- 原生商店常驻对话和选项分支保留原接口，不经过本封装。

冒险引导现在只负责配置、遮罩、赠卡结果和官方跳过按钮。七句原文逐字迁至
`resources/adventure/dave_intro.tres`，删除旧JSON，避免双重文案来源。
第四句和完成/跳过仍调用既有幂等存档接口；最后一句先持久化，再由原版离场。

停顿使用组件拥有的Timer，释放时停止；不保留跨场景Timer await。
组件卸载时停止仍属于本次对话的戴夫语音，不改变BGM或音量设置。

本轮验证：Godot导入/解析退出0；隔离APPDATA中的图形运行检查退出0，覆盖未封装的
原版顺序循环、气泡真实鼠标输入、七句推进、第四句赠卡、完成校验拒绝后重试、原版离场、
进场/第三句停顿中跳过，以及停顿中切场景后的清理。新资源七句文字与原JSON逐字一致。
没有执行完整战斗/商店回归；仍有原工程资源失效UID警告。
