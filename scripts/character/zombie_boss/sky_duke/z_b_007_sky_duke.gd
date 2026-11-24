## 苍穹公爵通过共用僵王生命与阶段机制驱动蓝、红两套形态。
extends ZB000Base

## [param action] 为已经就绪并开始播放的动作名。
signal action_started(action: StringName)
## [param action] 标识越过发令或人物消失时点的动作，供上层技能连接。
signal action_cue(action: StringName)
## [param action] 为已经播放完整时间轴的单次动作名。
signal action_finished(action: StringName)

## 图集播放器挂在身体节点下，身体受击颜色沿用既有合成。
const Visual = preload("res://scripts/character/zombie_boss/sky_duke/sky_duke_visual.gd")

## 本体的表现节点，动画位移不会改变血条、碰撞和逻辑站位。
@onready var _visual: Visual = $Body/SkyDukeVisual


## 接入共用 Boss 初始化、行动倍率和表现事件。
func _ready() -> void:
	super._ready()
	signal_update_speed.connect(_visual.set_action_rate)
	_visual.set_action_rate(speed_factor_product())
	_visual.set_phase(boss_phase)
	_visual.action_started.connect(action_started.emit)
	_visual.action_cue.connect(action_cue.emit)
	_visual.action_finished.connect(action_finished.emit)


## 请求一次 [param action]。动作名为 [code]command[/code]、[code]sky_order[/code]、[code]teleport_out[/code] 或 [code]idle[/code]。
## 接纳时返回 true。非待机动作从待机起手，显式请求待机用于离场后的出场逻辑。
func play_action(action: StringName) -> bool:
	return is_node_ready() and not is_death and not is_queued_for_deletion() and _visual.request_action(action)


## 返回本体精灵动作的有效秒数。供舞台演出只读取样，战斗技能可使用独立的结算时钟。
func action_elapsed() -> float:
	return _visual.action_elapsed()


## 将共用的 [param phase] 映射到原画。静默恢复和实战切阶段共用颜色，不追加演出。
## [param _animated] 由基类用于战斗阶段通知，此处只替换美术资源。
func _apply_boss_visual_phase(phase: int, _animated: bool) -> void:
	body.set_boss_phase_pulse(false)
	_visual.set_phase(phase)


## 沿用僵王奖励请求和通用淡出。死亡会停止动作，传送离场仍由上层显式调用。
func character_death() -> void:
	if is_death:
		return
	super.character_death()
	_visual.stop_playback()
	request_trophy()
	_fade_and_remove()
