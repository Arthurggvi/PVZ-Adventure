extends Plant000Base
class_name Plant024TallNut

## 同一株不灭高坚果拥有独立的一秒战斗计时。
const ARMOR_TICK_SECONDS: float = 1.0
## 不灭护甲上限相对最终生命上限的倍率。
const ARMOR_CAP_FACTOR: int = 3
## 当前本体生命每十点换一点护甲。
const ARMOR_LIFE_DIVISOR: float = 10.0
## 碾压交叠期间的身体色调和透明度。
const CRUSH_TINT := Color(0.78, 0.96, 1.0, 0.38)
## 接触通知后维持虚化的秒数，持续重叠会不断刷新这一时间。
const CRUSH_HOLD: float = 0.23
## 虚化渐入及恢复时长，单位为战斗秒。
const CRUSH_FADE_IN: float = 0.09
## 交叠分离后的淡回时长，单位为战斗秒。
const CRUSH_FADE_OUT: float = 0.24

## 高坚果原生生命裂纹组件。
@onready var hp_stage_change_component: HpStageChangeComponent = $HpStageChangeComponent
## 不灭入树前的冻结资格。
var _armor_growth: bool = false
## 最近一次碾压接触留下的表现保持时间。
var _crush_hold_left: float = 0.0
## 0 为原有外观，1 为完全虚化。
var _crush_blend: float = 0.0

## 只有正在过渡或交叠的实例需要处理表现。
func _ready() -> void:
	super()
	set_process(false)

## 按 [param rule] 安装本株的被动技能，生命组件须在出战前已经存在。
func configure_defense(rule: Dictionary) -> void:
	var health := get_node(^"HpComponent") as HpComponentPlant # 原生生命节点在入树前尚未绑定 onready。
	match String(rule.kind):
		"tallnut_armor_growth":
			_armor_growth = true
		"tallnut_guard_rear":
			health.guards_rear_cell = true
		"tallnut_thorns":
			health.reflects_damage = true
		"tallnut_crush_cap":
			health.crush_health_fraction = float(rule.fraction)
			health.max_single_hit_fraction = health.crush_health_fraction
		"tallnut_absorb_blasts":
			health.intercepts_explosions = true

## 保留裂纹显示，只有不灭分支启动一秒回调。
func ready_norm_signal_connect():
	super()
	hp_component.signal_hp_loss.connect(hp_stage_change_component.judge_body_change)
	if _armor_growth:
		var timer := Timer.new() # 沿用植株的暂停与离场生命周期。
		timer.wait_time = ARMOR_TICK_SECONDS
		timer.autostart = true
		timer.timeout.connect(_gain_armor)
		add_child(timer)

## 生命读数在这一秒到期时采样，护甲沿用正式共享池和显示。
func _gain_armor() -> void:
	if is_death or is_queued_for_deletion():
		return
	var health := hp_component as HpComponentPlant # 仅使用未计护甲的本体生命。
	health.grant_bonus_armor(floori(health.curr_hp / ARMOR_LIFE_DIVISOR), health.max_hp * ARMOR_CAP_FACTOR)

## 重叠只刷新表现保持时间；碾压次数与护甲结算独立。
func show_crush_contact() -> void:
	if is_death or is_queued_for_deletion() or not is_node_ready():
		return
	_crush_hold_left = CRUSH_HOLD
	if not is_processing():
		set_process(true)

## 按 [param delta] 淡入或恢复身体，脚点、碰撞和血条保持原样。
func _process(delta: float) -> void:
	_crush_hold_left = maxf(0.0, _crush_hold_left - delta)
	var touching: bool = _crush_hold_left > 0.0 and not is_death # 死亡或离开时沿同一通道淡回。
	var length: float = CRUSH_FADE_IN if touching else CRUSH_FADE_OUT # 渐入更快，分离后留出完整淡回。
	var next: float = move_toward(_crush_blend, float(touching), delta / length) # 稳定重叠期不用重复写入身体。
	if next != _crush_blend:
		_crush_blend = next
		body.set_other_color(BodyCharacter.E_ChangeColors.CrushContact, Color.WHITE.lerp(CRUSH_TINT, smoothstep(0.0, 1.0, next)))
	if not touching and _crush_blend == 0.0:
		set_process(false)

## [param area] 进入阻跳范围的区域；仅普通僵尸具有跳跃阻挡属性，僵王和非角色区域直接跳过。
func _on_area_2d_stop_jump_area_entered(area: Area2D) -> void:
	# 安全转换，避免僵王受击框进入范围时被强制赋给普通僵尸类型。
	var zombie := area.owner as Zombie000Base
	if not is_instance_valid(zombie) or zombie.is_death or zombie.is_queued_for_deletion():
		return
	if zombie.lane == lane and zombie.is_trigger_tall_nut_stop_jump:
		zombie.jump_be_stop(self)

