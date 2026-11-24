## 仲裁者：单体三行载具，拥有后方减伤光场和低血量坠毁演出。
extends Zombie000Base
class_name Zombie038ArbiterX

## 本体生命严格低于此值时进入坠毁，单位为生命点。
const CRASH_HP_THRESHOLD: int = 100

## 复用原生敌方死亡与登记者，避免多行导致三次波次减员。
@onready var arbiter_attack: AttackComponentZombieArbiterX = $AttackComponent
## 巡航、双尾焰与光束的表现控制器。
@onready var arbiter_presentation: ArbiterXPresentation = $ArbiterPresentation
## 仅为后方僵尸提供具名伤害减免，不移除其受击资格。
@onready var arbiter_field: ArbiterXField = $ArbiterField

## 清场期间不触发击毁爆炸、撞家失败或第二次吹飞。
var _wind_exit: bool = false
## 生命周期只允许向死亡流程提交一次。
var _death_completed: bool = false

## 先保留原生角色初始化，再启用有效战斗中的三项独立能力。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/HeadAnchor")])
	super()
	hp_component.set_death_hp(CRASH_HP_THRESHOLD - 1)
	hp_component.scale_death_hp_on_promotion = false
	arbiter_presentation.configure(self)
	if character_init_type == E_CharacterInitType.IsNorm:
		arbiter_field.activate(self)
		arbiter_attack.activate(self)

## [param row] 所在攻击行的邻行亦可以真正命中本体；不再限定中心行。
func covers_attack_lane(row: int) -> bool:
	return absi(row - lane) <= 1

## 巨大机体属于低空载具而不是不可由普通植物命中的气球。
func is_blover_flying_target() -> bool:
	return not _wind_exit and not is_death

## 只在吹离表现阶段进入临时原生空中态，保护房屋失败区。
func is_native_airborne() -> bool:
	return _wind_exit

## 完全冻结转成相同总时长的寒冷减速。
func can_cold_freeze() -> bool:
	return false

## [param _cells] 是共享风场距离，本物种不创建第二个强制位移。
## [param flying] 只由三叶草分类接口提供，免疫普通击退混入。
func handle_blover_wind(_cells: int, flying: bool) -> bool:
	if _wind_exit or is_death or not flying:
		return false
	_wind_exit = true
	arbiter_field.clear()
	arbiter_attack.finish_life()
	arbiter_presentation.finish_life()
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	var blow: Tween = create_tween()
	blow.set_parallel(true)
	blow.tween_property(self, ^"position", position + Vector2(250.0, -135.0), 0.55)
	blow.tween_property(self, ^"modulate:a", 0.0, 0.55)
	blow.tween_property(body, ^"rotation_degrees", -16.0, 0.55)
	blow.chain().tween_callback(retire_from_battle)
	return true

## 爆炸致死也继续播放本物种的俯冲坠毁。
func _preserves_blast_death_animation() -> bool:
	return true

## 低血量立即退出战斗登记，同步停止保护和碾压，正常击毁随后播放坠毁。
func character_death() -> void:
	if _death_completed:
		return
	_death_completed = true
	if is_instance_valid(arbiter_field):
		arbiter_field.clear()
	if is_instance_valid(arbiter_attack):
		arbiter_attack.finish_life()
	if is_instance_valid(arbiter_presentation):
		if not _wind_exit and not retiring_from_battle:
			arbiter_presentation.play_crash()
		arbiter_presentation.finish_life()
	super()
	queue_free()
