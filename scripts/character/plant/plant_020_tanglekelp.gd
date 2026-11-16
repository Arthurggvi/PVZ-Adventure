extends Plant000Base
class_name Plant020Tanglekelp

## 从抓取开始到植物格冒水花的初代时点，单位秒。
const PLANT_SPLASH_AT: float = 0.8

## 仅普通僵尸使用的拖拽表现与处决组件。
@onready var grap_component: GrapComponent = $GrapComponent
## 查找当前仍处于受击范围内的目标。
@onready var detect_component: DetectComponent = $DetectComponent
## 僵王不会被拖入水中，改为一次穿透伤害；命中后海草仍消耗自身。
@export_range(0, 10000, 1, "or_greater") var boss_attack_value: int = 1800
## 海草是一次性攻击，防止等待动画期间重复响应索敌信号。
var _is_attacking: bool = false

## 拖拽开始后要在原水域完成下沉动作。
func can_relocate() -> bool:
	return not _is_attacking


func ready_norm_signal_connect():
	super()
	detect_component.signal_can_attack.connect(start_grap_zombie)

## 开始攻击
func start_grap_zombie():
	if _is_attacking or is_death:
		return
	# 同步检查范围和受击窗口，避免对已抬头的僵王开始攻击。
	var enemy: Character000Base = detect_component.update_first_enemy()
	if not (enemy is Zombie000Base or enemy is ZB000Base or enemy is EnemyStructureBase):
		return
	_is_attacking = true
	detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Attack)
	blink_component.disable_component(ComponentNormBase.E_IsEnableFactor.Attack)
	grap_in_pool(enemy)

## 消耗自身以攻击 [param target_zombie]。普通目标进入初代抓取演出，僵王和构筑物承受穿透伤害。
func grap_in_pool(target_zombie: Character000Base) -> void:
	if target_zombie is Zombie000Base:
		grap_component.grab_zombie(target_zombie)
		await get_tree().create_timer(PLANT_SPLASH_AT, false).timeout
		if is_death or is_queued_for_deletion() or not is_instance_valid(plant_cell):
			return
		Splash.spawn(plant_cell, global_position + Vector2(0, 10), 1.3)
		await get_tree().create_timer(GrapComponent.HOLD_SECONDS + GrapComponent.SINK_SECONDS - PLANT_SPLASH_AT, false).timeout
	else:
		target_zombie.be_attacked_bullet(battle_damage(boss_attack_value), BulletRegistry.AttackMode.Penetration, false, false)
		await _sink_after_boss_hit()
	if not is_death and not is_queued_for_deletion():
		character_death()

## 僵王与构筑物的扩展分支沿用植物自己的下沉表现。
func _sink_after_boss_hit() -> void:
	await get_tree().create_timer(0.3, false).timeout
	if is_death or is_queued_for_deletion() or not is_instance_valid(plant_cell):
		return
	Splash.spawn(plant_cell, global_position + Vector2(0, 10))
	var tween: Tween = create_tween() # 只补间水草的退场位置。
	tween.tween_property(self, ^"position:y", 10.0, 0.5).as_relative()
	await tween.finished

