## 原生恐惧组件；附近敌人与临时免恐惧来源共同决定同一组恐惧信号。
extends ComponentNormBase
class_name ScaredyComponent

## 实际进入恐惧时发出，由植物本体同步动画及攻击组件的 Scaredy 因子。
signal signal_scaredy_start
## 实际离开恐惧时发出，不解除睡眠、死亡等其他禁用原因。
signal signal_scaredy_end
## 原场景的近身检测组件；免恐惧期间继续检测，以便撤销后立即恢复状态。
@onready var detect_component: DetectComponent = $DetectComponent
## 恐惧时受影响的原生组件，由植物本体连接信号。
@export var scaredy_influence_components: Array[ComponentNormBase]
## 每个临时免恐惧来源独立占一个条目，重复授予不会叠加或提前解除。
var _fearless_sources: Dictionary[int, bool] = {}
## 最近一次原生检测结果；免恐惧只覆盖表现，不丢弃附近敌人的事实。
var _has_nearby_enemy: bool = false
## 已通知植物本体的恐惧状态，避免重复刷新重启攻击计时器。
var _is_scared: bool = false

## 保留原生检测信号，将敌人存在与来源豁免合成为一次状态变化。
func _ready() -> void:
	super()
	detect_component.signal_can_attack.connect(_update_nearby_enemy.bind(true))
	detect_component.signal_not_can_attack.connect(_update_nearby_enemy.bind(false))

## [param source_id] 是有效来源实例 ID；[param enabled] 为授予或撤销该来源。
## 最后一个来源撤销后立即使用当前检测结果，保留其他来源及组件禁用原因。
func set_fearless_source(source_id: int, enabled: bool) -> void:
	if source_id <= 0 or _fearless_sources.has(source_id) == enabled:
		return
	if enabled:
		_fearless_sources[source_id] = true
	else:
		_fearless_sources.erase(source_id)
	_refresh_scared_state()

## [param present] 是原生检测得到的附近敌人事实，免恐惧期间同样记录。
func _update_nearby_enemy(present: bool) -> void:
	_has_nearby_enemy = present
	_refresh_scared_state()

## 仅在最终状态改变时发信号；禁用组件或存在任意豁免来源时不会恐惧。
func _refresh_scared_state() -> void:
	var next_scared: bool = is_enabling and _has_nearby_enemy and _fearless_sources.is_empty() # 合成原生状态与临时豁免。
	if next_scared == _is_scared:
		return
	_is_scared = next_scared
	if _is_scared:
		signal_scaredy_start.emit()
	else:
		signal_scaredy_end.emit()

## [param is_enable_factor] 为本次解除的禁用原因；全部原因允许时才恢复近身检测。
func enable_component(is_enable_factor: E_IsEnableFactor) -> void:
	super(is_enable_factor)
	if is_enabling and is_instance_valid(detect_component):
		detect_component.enable_component(E_IsEnableFactor.Scaredy)
	_refresh_scared_state()

## [param is_enable_factor] 为本次禁用原因；清除本次检测状态并结束恐惧，保留免恐惧来源。
func disable_component(is_enable_factor: E_IsEnableFactor) -> void:
	super(is_enable_factor)
	_has_nearby_enemy = false
	if is_instance_valid(detect_component):
		detect_component.disable_component(E_IsEnableFactor.Scaredy)
	_refresh_scared_state()
