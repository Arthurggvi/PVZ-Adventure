## 复用原生豌豆碰撞与扣血；冥弹仅在真实处决成功时继续穿透。
extends BulletLinear000Base
class_name RepeaterPeaProjectile

## 本颗弹体的冻结战斗来源，母株死亡后仍可完成已经发出的攻击。
var shot: RepeaterShotContext
## 唯一弹体变种，不把多个词条叠在一颗豌豆上。
var kind: StringName = &""
## 本次直击前仍有二类防具时，震撼弹不能击退。
var _block_knockback: bool = false
## 本次命中是否实际完成处决；仅供本次同步命中结果使用。
var _executed: bool = false

## 原生身体就绪后安装纯视觉；特殊颜色命中使用对应碎光，避免绿色碎屑覆盖。
func _ready() -> void:
	super()
	if shot == null or not shot.is_active():
		queue_free()
		return
	is_can_up = false
	unique_target_hits = true
	bullet_effect.is_bullet_effect = false
	if kind == &"hades":
		max_attack_num = -1
	impact_resolved.connect(_on_impact)
	RepeaterProjectileVisual.attach(self, kind)

## [param enemy] 为本次实体或空的坡面命中；每次尝试先清除处决标记，不能继承上一击。
func attack_once(enemy: Character000Base) -> void:
	_executed = false
	super(enemy)

## [param enemy] 本次直击目标；命中前冻结防具资格，破甲不能让同一击随后获得击退。
func _attack_enemy(enemy: Character000Base) -> void:
	_block_knockback = is_instance_valid(enemy) and enemy.hp_component is HpComponentZombie \
		and (enemy.hp_component as HpComponentZombie).curr_hp_armor2 > 0
	super(enemy)

## [param zombie] 已通过原生碰撞资格；低于三成有效战斗生命的非魅惑普通僵尸可被冥弹处决。
## Boss 不进入该类型分支；处决通过既有最终死亡入口，保留掉落与死亡通知。
func _attack_zombie(zombie: Zombie000Base) -> void:
	if kind == &"hades" and not zombie.is_hypno and zombie.hp_component.max_hp > 0 \
			and zombie.hp_component.living_health_fraction() < 0.3:
		var execution: Node2D = RepeaterExecutionVisual.capture(shot.game.bullets, zombie.body) # 冻结当前姿态，后续不引用将死角色。
		# 使用原生最终生命调整和死亡通知，关闭残肢表现但保留独立的正常掉落信号。
		zombie.hp_component.apply_unblocked_loss(zombie.hp_component.get_all_hp(),
			BulletRegistry.AttackMode.Norm, false, false)
		if is_instance_valid(zombie) and zombie.is_death:
			last_impact_casualty = zombie
			_executed = true
			if is_instance_valid(zombie.body):
				zombie.body.hide()
			return
		if is_instance_valid(execution):
			execution.queue_free()
	super(zombie)

## [param target] 为已完成直击的实体；[param position] 是原生世界命中位置。
func _on_impact(target: Character000Base, position: Vector2) -> void:
	if kind == &"hades" and not _executed:
		queue_free()
	if shot == null or not shot.is_same_battle():
		return
	if kind == &"hades":
		RepeaterHadesImpact.spawn(shot.game.bullets, position, direction, _executed, z_index) # 独立冥界裂隙，处决与普通命中采用不同压力。
	else:
		RepeaterImpactVisual.spawn(shot.game.bullets, kind, position, direction, z_index)
	if not shot.is_active():
		return
	if kind == &"morning" and is_instance_valid(target):
		RepeaterStarFork.split(self, target, shot, 0)
	elif not _executed:
		RepeaterProjectileEffects.impact(kind, target, position, shot, _block_knockback)
