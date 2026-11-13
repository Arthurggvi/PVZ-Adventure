## 植物原生睡眠入口；环境、永久唤醒与临时来源共同决定同一组睡眠信号。
extends ComponentNormBase
class_name SleepComponent

## 原场景的睡眠气泡动画播放器。
@onready var anim_sleep: AnimationPlayer = $AnimSleep
## 最近一次已应用的睡眠状态，与植物本体的动画标志同步。
var is_sleeping: bool = false
## 咖啡豆等永久唤醒结果；临时光环不会写入此字段。
var is_permanently_awake: bool = false
## 每个临时唤醒来源独立占一个条目；重复授予不会重复计数。
var _awake_sources: Dictionary[int, bool] = {}
## 首次环境判断仍须发信号初始化原生组件，之后只在状态变化时发送。
var _sleep_state_known: bool = false

## 进入睡眠，由植物本体统一转发给动画及各组件的 Sleep 因子。
signal signal_is_sleep
## 离开睡眠；不清除任何非睡眠原因造成的组件禁用。
signal signal_not_is_sleep

## 由植物本体连接到睡眠信号的原生组件，不建立额外活动管道。
@export var sleep_influence_components: Array[ComponentNormBase]

## 重新合成当前环境与唤醒原因；死亡、离树或尚未就绪时不触发行为。
func judge_is_sleeping() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	var plant: Plant000Base = get_parent() as Plant000Base # 本组件所属的真实植株。
	if plant == null or plant.is_death:
		return
	# 出生即常醒的植物未进入过睡眠，不为加入光环额外重启其原生攻击或生产。
	if not plant.is_sleep_in_day and not _sleep_state_known and not plant.is_sleeping:
		return
	if plant.is_sleep_in_day and is_sleep_environment() \
			and not is_permanently_awake and not has_awake_sources():
		start_sleep()
	else:
		end_sleep()

## 返回原生环境是否要求日眠；黄昏按关卡的 is_day 配置判断，不猜测背景颜色。
## 夜晚和非温室花园返回 false，未知场景同样不强制睡眠。
func is_sleep_environment() -> bool:
	if not is_inside_tree():
		return false
	var current_root: Node = get_tree().current_scene # 当前实际战斗或花园，避免借用旧关卡。
	if current_root is MainGameManager:
		return (current_root as MainGameManager).game_para.is_day
	if current_root is GardenManager:
		return (current_root as GardenManager).curr_bg_type == GardenManager.E_GardenBgType.GreenHouse
	return false

## [param source_id] 为有效来源实例 ID；[param enabled] 为授予或撤销该来源。
## 重复调用幂等；撤销最后一个来源后重新检查环境，保留咖啡豆及其他来源。
func set_awake_source(source_id: int, enabled: bool) -> void:
	if source_id <= 0 or _awake_sources.has(source_id) == enabled:
		return
	if enabled:
		_awake_sources[source_id] = true
	else:
		_awake_sources.erase(source_id)
	judge_is_sleeping()

## 返回是否仍存在临时唤醒来源；不把永久咖啡豆状态算作临时来源。
func has_awake_sources() -> bool:
	return not _awake_sources.is_empty()

## 咖啡豆完成原有延迟动画后调用；即使期间已被光环唤醒，也保留永久效果。
func wake_permanently() -> void:
	is_permanently_awake = true
	judge_is_sleeping()

## 从存档恢复 [param value] 的永久唤醒事实；场上临时来源由光环另行重建。
func restore_permanent_awake(value: bool) -> void:
	if is_permanently_awake == value:
		return
	is_permanently_awake = value
	judge_is_sleeping()

## 只在实际进入睡眠时通知组件；临时或永久唤醒期间拒绝强制日眠。
func start_sleep() -> void:
	if is_permanently_awake or has_awake_sources() or (_sleep_state_known and is_sleeping):
		return
	_sleep_state_known = true
	is_sleeping = true
	visible = true
	anim_sleep.play("zzz")
	signal_is_sleep.emit()

## 只结束本次睡眠，不授予永久豁免；重复刷新不会重启生产或攻击计时器。
func end_sleep() -> void:
	if _sleep_state_known and not is_sleeping:
		return
	_sleep_state_known = true
	is_sleeping = false
	visible = false
	anim_sleep.stop()
	signal_not_is_sleep.emit()

## [param speed_product] 为角色速度因子乘积，仅调整原有气泡动画。
func owner_update_speed(speed_product: float) -> void:
	anim_sleep.speed_scale = speed_product

## 仅隐藏睡眠气泡，保留原有表现入口，不修改任何唤醒原因。
func no_sleep() -> void:
	visible = false
	anim_sleep.stop()
