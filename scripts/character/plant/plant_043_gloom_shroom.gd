extends Plant000Base
class_name Plant043GloomShroom

@onready var attack_component: AttackComponentBulletBase = $AttackComponent
@onready var all_bullet_fx: Array[Node2D] = [%Bullet_FX, %Bullet_FX2, %Bullet_FX3, %Bullet_FX4]
var all_bullet_fx_particles :Array[Array]
var num_attack :int = 0
## Direct-area attack damage, shared with the adventure damage binding.
@export var attack_value: int = 20

func ready_norm():
	super()
	for bullet_fx in all_bullet_fx:
		var bullet_fx_particles :Array[GPUParticles2D] = []
		for p in bullet_fx.get_children():
			bullet_fx_particles.append(p)
		all_bullet_fx_particles.append(bullet_fx_particles)

## 初始化正常出战角色信号连接
func ready_norm_signal_connect():
	super()
	signal_update_speed.connect(attack_component.owner_update_speed)


func attack_once():
	var bullet_fx_particles :Array[GPUParticles2D] = all_bullet_fx_particles[num_attack]
	for p:GPUParticles2D in bullet_fx_particles:
		p.amount_ratio = [0.6, 0.8, 1.0].pick_random()
		p.emitting = true
	num_attack = wrapi(num_attack+1, 0, all_bullet_fx_particles.size())

	var all_enemy:Array[Character000Base] = attack_component.detect_component.get_all_enemy_can_be_attacked()
	var context: PlantAttackContext = capture_attack_context() # 同一轮范围攻击共享来源位置快照。
	for enemy in all_enemy: # 每个实际检测目标仍分别经过原生穿透伤害路由。
		if context != null and not context.is_active():
			break
		if not is_instance_valid(enemy) or enemy.is_death or enemy.is_queued_for_deletion():
			continue
		var damage: int = battle_damage(attack_value) # 原出战卡、光环和劣化后的基础攻击。
		if context != null:
			damage = context.modify_damage(damage, enemy)
		var casualty: Character000Base = null # 只收集本次伤害实际杀死的角色。
		if context != null and enemy is Zombie000Base:
			casualty = (enemy.hp_component as HpComponentZombie).apply_hit(
				damage, BulletRegistry.AttackMode.Penetration, true, true, true, context.armor_multiplier)
			if is_instance_valid(enemy) and is_instance_valid(enemy.body):
				enemy.body.body_light()
		else:
			enemy.be_attacked_bullet(damage, BulletRegistry.AttackMode.Penetration)
			if is_instance_valid(enemy) and enemy is ZB000Base and enemy.is_death:
				casualty = enemy
		if context != null:
			context.resolve_kill(casualty)
