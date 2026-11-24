extends Node
## 地图特效唯一调度器：所有区域实例共享显式动画秒数。
## 当前承载主体、水域以及局部风、孔口、光雾和解析粒子。
## 未来Codex只追加实现接口的效果节点，不在地图根节点堆11组if分支。
## 所有参数在提交前验证，失败时旧效果配置保持完整不变。
## 每个效果节点必须有validate_profile、apply_profile、set_animation_seconds、set_effect_enabled方法。
## 注册表是当前场景生命周期局部数据，不引入第二个Autoload。
## 已注册的具体效果组件。
var _entries: Dictionary = {}
## 每个组件最后一次成功提交的参数快照。
var _profiles: Dictionary = {}
## 本地图动画时钟，由宿主唯一推进。
var _seconds := 0.0
## 全局运动暂停不覆盖各区域自己的显示开关。
var _motion_paused := false

## [param effect_id] 与fx_regions.json条目关联；[param instance] 必须满足接口契约。
func register_effect(effect_id: String, instance: Node) -> bool:
    if effect_id.is_empty() or _entries.has(effect_id) or instance == null:
        return false
    for method: String in ["validate_profile","apply_profile","set_animation_seconds","set_effect_enabled"]:
        if not instance.has_method(method):
            push_error("Wonderland effect missing method: " + method)
            return false
    _entries[effect_id] = instance
    _profiles[effect_id] = {}
    instance.call("set_animation_seconds",_seconds)
    if instance.has_method("set_motion_paused"):
        instance.call("set_motion_paused",_motion_paused)
    return true

## [param updates] 只允许已实例化的效果ID；所有节点先验后提交。
func apply_profiles(updates: Dictionary) -> Dictionary:
    for id: String in updates:
        if not _entries.has(id) or not updates[id] is Dictionary:
            return {"ok":false,"error":"Unknown or invalid effect: " + id}
        var reason: String = str(_entries[id].call("validate_profile",updates[id]))
        if not reason.is_empty():
            return {"ok":false,"error":reason}
    for id: String in updates:
        _entries[id].call("apply_profile",updates[id])
        _profiles[id] = updates[id].duplicate(true)
    return {"ok":true,"profile":snapshot()}

## 返回所有已注册效果的有效配置，禁止外部修改内部字典。
func snapshot() -> Dictionary:
    return _profiles.duplicate(true)

## [param effect_id] 为现有实例；[param enabled] 禁用时仅关闭显示，不重置相位。
func set_enabled(effect_id: String, enabled: bool) -> bool:
    if not _entries.has(effect_id):
        return false
    _entries[effect_id].call("set_effect_enabled",enabled)
    return true

## [param seconds] 是宿主已计算的游戏显示秒数，暂停时保持不变。
func set_animation_seconds(seconds: float) -> void:
    if not is_finite(seconds):
        return
    _seconds = seconds
    for id: String in _entries:
        if is_instance_valid(_entries[id]):
            _entries[id].call("set_animation_seconds",seconds)
    _apply_event_priority()

## [param paused] 只冻结动作；主体保留既有冻结语义，其他组件使用独立暂停接口。
func set_motion_paused(paused: bool) -> void:
    _motion_paused = paused
    for id: String in _entries: # 区域显示状态不会被全局恢复意外改写。
        var effect: Node = _entries[id] # 已注册的当前场景局部实例。
        if effect.has_method("set_motion_paused"):
            effect.call("set_motion_paused",paused)
        elif id == "subjects":
            effect.call("set_effect_enabled",not paused)

## 同类别最大包络仅参与优先级占用，各层仍保留自己的连续动作进度。
func _apply_event_priority() -> void:
    if _motion_paused:
        return
    var candidates: Dictionary = {"church":0.0,"portal":0.0,"furnace":0.0} # 优先级顺序固定，不依赖地区遍历顺序。
    for id: String in _entries: # 原始包络由组件有效动作秒数给出，关闭节点返回零。
        var effect: Node = _entries[id] # 只有新组件实现局部事件接口。
        if effect.has_method("get_event_envelope"):
            var kind: String = str(effect.get("event_kind")) # 同类别取最大值估计占用，不覆盖各层相位。
            if candidates.has(kind):
                candidates[kind] = maxf(float(candidates[kind]),float(effect.call("get_event_envelope")))
    var transmission := 1.0 # 高优先级已占用的事件能量，包络连续所以不会硬切。
    for kind: String in ["church","portal","furnace"]:
        var raw: float = float(candidates[kind]) # 仲裁前的连续包络。
        candidates[kind] = transmission
        transmission *= 1.0-raw
    for id: String in _entries: # 只有增强被压制，风、雪、常态炉光继续运行。
        var effect: Node = _entries[id] # 当前场景的可选事件接收者。
        if effect.has_method("set_event_weight") and effect.has_method("get_event_envelope"):
            var local_weight: float = float(effect.call("get_event_envelope")) # 单区恢复继续自身相位。
            effect.call("set_event_weight",local_weight*float(candidates.get(str(effect.get("event_kind")),0.0)))

## 返回可用的真实入口，不宣称所有未来Shader已经存在。
func describe() -> Dictionary:
    return {"clock":"explicit_animation_seconds","active_effects":_entries.keys(),"methods":["register_effect","apply_profiles","set_enabled","snapshot","set_animation_seconds"]}
