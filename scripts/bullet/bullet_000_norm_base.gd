extends Bullet000Base
class_name Bullet000NormBase

@onready var area_2d_attack: Area2D = $Area2DAttack

## 子弹击中特效
@onready var bullet_effect: BulletEffect000Base = $BulletEffect
## 子弹基类
@export_group("子弹基础属性")
## 子弹是否旋转
@export var is_rotate := false
## 最大攻击次数(-1表示可以无限攻击)
@export var max_attack_num:=1
## 当前攻击次数
var curr_attack_num:=0
## 一颗子弹对同一僵王只结算一次，避免多个受击区域或追踪补判重复命中。
var _hit_boss_ids: Dictionary[int, bool] = {}
## 穿透弹各次命中的伤害系数，空数组保持原版单次攻击逻辑。
var promotion_hit_factors: PackedFloat32Array = PackedFloat32Array()
## 穿透弹已命中的目标实例，避免同一目标多个受击框反复扣血。
var _promotion_hit_ids: Dictionary[int, bool] = {}
## 最近一次真实命中的伤害数值，供命中事件的额外效果按比例计算。
var last_impact_damage: int = 0
## 本次攻击的来源快照，可在弹体变换后继续使用；空值保持原生伤害。
var attack_context: PlantAttackContext
## 当前命中实际杀死的角色；保护者代伤时可以与直接命中目标不同。
var last_impact_casualty: Character000Base
## One post-impact hook for projectile perks, after normal hit/umbrella routing.
signal impact_resolved(target: Character000Base, impact_position: Vector2)
## 子弹伤害
@export var attack_value := 20
## Immutable attack origin passed across projectile transformations (e.g. Torchwood).
var source_damage_multiplier: float = 1.0
## 子弹默认移动速度
@export var speed: float = 300.0
## 子弹默认移动方向
@export var direction: Vector2 = Vector2.RIGHT
## 子弹伤害模式：普通，穿透，真实
@export var bullet_mode : BulletRegistry.AttackMode
## 子弹移动离出生点最大距离，超过自动销毁
@export var max_distance := 2000.0
## 子弹初始位置
var start_pos: Vector2
## 默认是否激活行属性，激活后只能攻击本行的僵尸
@export var default_is_activate_lane:=true
var is_activate_lane:bool
## 子弹行属性
var lane :int = -1
@export_subgroup("子弹音效相关")
## 是否触发受击音效(火焰豌豆就不触发)
@export var trigger_be_attack_sfx := true
## 子弹本身音效
@export var type_bullet_SFX :SoundManagerClass.TypeBulletSFX =  SoundManagerClass.TypeBulletSFX.Pea


@export_group("子弹攻击相关")
## 可以攻击的敌人状态
@export_flags("1 正常", "2 悬浮", "4 地刺", "8 低矮植物") var can_attack_plant_status:int = 1
@export_flags("1 正常", "2 跳跃", "4 水下", "8 空中", "16 地下") var can_attack_zombie_status:int = 1

@export_group("子弹升级相关")
## 是否可以升级子弹
@export var is_can_up:=false


func _ready() -> void:
	body.rotation = direction.angle()

	if is_rotate:
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(body, "rotation", TAU, 1.0).as_relative()

## 子弹初始化参数种类
enum E_InitParasAttr{
	IsActivateLane,		## 是否激活行属性
	BulletLane, 		## 子弹所在行
	Position,			## 子弹起始位置
	Direction,			## 子弹起始方向
	CanAttackPlantState,	## 子弹可以攻击的敌人(植物)状态
	CanAttackZombieState,	## 子弹可以攻击的敌人(僵尸)状态
	DamageMultiplier,	## Frozen adventure card's attack multiplier; default 1.0

	## 抛物线子弹\追踪子弹额外属性
	Enemy,				## 子弹选中的敌人
	EnemyGloPos,		## 敌人位置(发射子弹时敌人若已经消失,抛物线依旧可以攻击)
	AttackContext,		## 可选植物攻击上下文；追加枚举值以保留既有参数序号。

}

## 初始化子弹属性
func init_bullet(bullet_paras:Dictionary):
	## 子弹行
	self.is_activate_lane = bullet_paras.get(E_InitParasAttr.IsActivateLane, default_is_activate_lane)
	self.lane = bullet_paras.get(E_InitParasAttr.BulletLane, -1)
	z_index = self.lane * 50 + 45

	self.start_pos = bullet_paras.get(E_InitParasAttr.Position, Vector2.ZERO)
	position = self.start_pos

	self.direction = bullet_paras.get(E_InitParasAttr.Direction, Vector2.RIGHT)
	self.can_attack_plant_status = bullet_paras.get(E_InitParasAttr.CanAttackPlantState, can_attack_plant_status)
	self.can_attack_zombie_status = bullet_paras.get(E_InitParasAttr.CanAttackZombieState, can_attack_zombie_status)
	attack_context = bullet_paras.get(E_InitParasAttr.AttackContext) as PlantAttackContext
	source_damage_multiplier = float(bullet_paras.get(E_InitParasAttr.DamageMultiplier, 1.0))
	attack_value = maxi(0, roundi(float(attack_value) * source_damage_multiplier))
	var splash: SpatterComponent = get_node_or_null("SpatterComponent") as SpatterComponent
	if splash != null:
		splash.apply_damage_multiplier(source_damage_multiplier)


## 获取子弹属性
func get_bullet_paras()->Dictionary[E_InitParasAttr,Variant]:
	return {
		E_InitParasAttr.IsActivateLane : self.is_activate_lane,
		E_InitParasAttr.BulletLane : self.lane,
		E_InitParasAttr.Position : position,
		E_InitParasAttr.Direction : self.direction,
		E_InitParasAttr.CanAttackPlantState : self.can_attack_plant_status,
		E_InitParasAttr.CanAttackZombieState : self.can_attack_zombie_status,
		E_InitParasAttr.DamageMultiplier : self.source_damage_multiplier,
		E_InitParasAttr.AttackContext : self.attack_context,
	}

## 子弹与敌人碰撞
func _on_area_2d_attack_area_entered(area: Area2D) -> void:
	# 梯子分支不调用 attack_once，因此碰撞入口也拒绝已经跨轮的来源。
	if attack_context != null and not attack_context.is_active():
		queue_free()
		return
	var ladder_entity: Ladder = area.owner as Ladder
	if is_instance_valid(ladder_entity):
		if bullet_camp == CharacterRegistry.CharacterType.Plant \
				and not ladder_entity.is_queued_for_deletion() \
				and (not is_activate_lane or lane == ladder_entity.lane) \
				and (max_attack_num < 0 or curr_attack_num < max_attack_num):
			ladder_entity.take_damage(attack_value)
			curr_attack_num += 1
			if max_attack_num >= 0 and curr_attack_num >= max_attack_num:
				queue_free()
		return
	var enemy := area.owner as Character000Base
	if not _can_attack_character(enemy):
		return
	if max_attack_num != -1 and curr_attack_num >= max_attack_num:
		return
	attack_once(enemy)


## 碰撞和追踪补判共用目标检查；追踪子弹可跳过普通角色行号，僵王始终由空间碰撞决定。
func _can_attack_character(enemy: Character000Base, check_lane: bool = true) -> bool:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.is_death:
		return false
	if not is_instance_valid(enemy.hurt_box_component) or not enemy.hurt_box_component.is_enabling:
		return false
	if enemy is ZB000Base:
		return bullet_camp == CharacterRegistry.CharacterType.Plant \
			and enemy.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
			and (can_attack_zombie_status & Zombie000Base.E_BeAttackStatusZombie.IsNorm) != 0
	## TODO:攻击植物子弹
	if enemy is Plant000Base:
		## 子弹阵营为植物
		if bullet_camp == CharacterRegistry.CharacterType.Plant:
			return false
		if not enemy.curr_be_attack_status & can_attack_plant_status:
			return false
	elif enemy is Zombie000Base:
		## 子弹阵营为植物
		if bullet_camp == CharacterRegistry.CharacterType.Zombie:
			return false
		## 如果不是可攻击状态敌人
		if not enemy.curr_be_attack_status & can_attack_zombie_status:
			#print("敌人状态：", enemy.curr_be_attack_status, "可以攻击敌人状态：", can_attack_zombie_status)
			return false
	elif enemy is EnemyStructureBase:
		if bullet_camp != CharacterRegistry.CharacterType.Plant \
			or (can_attack_zombie_status & Zombie000Base.E_BeAttackStatusZombie.IsNorm) == 0:
			return false
	else:
		return false
	return not check_lane or not is_activate_lane or lane == enemy.lane


## 对敌人造成伤害
func _attack_enemy(enemy:Character000Base):
	if enemy is ZB000Base or enemy is EnemyStructureBase:
		# 僵王直接使用角色伤害入口，不转换成普通僵尸或套用其防具规则。
		var was_alive: bool = not enemy.is_death # 只回报本次实际从存活变为死亡的僵王。
		enemy.be_attacked_bullet(attack_value, bullet_mode, true, trigger_be_attack_sfx)
		if was_alive and is_instance_valid(enemy) and enemy is ZB000Base and enemy.is_death:
			last_impact_casualty = enemy
	elif enemy is Zombie000Base:
		_attack_zombie(enemy)
	elif enemy is Plant000Base:
		_attack_plant(enemy)

## 对 [param zombie] 使用当前模式；直线子类仍可选择背击模式。
func _attack_zombie(zombie: Zombie000Base):
	_hit_zombie(zombie, bullet_mode)

## 将 [param zombie] 与 [param mode] 交给既有生命路由，返回本次实际死亡者。
## 防具倍率仅作为伤害参数传递，保留格挡、转伤、穿透和受击闪白。
func _hit_zombie(zombie: Zombie000Base, mode: BulletRegistry.AttackMode) -> Zombie000Base:
	var armor: float = attack_context.armor_multiplier if attack_context != null else 1.0 # 默认攻击完全沿用一倍防具消耗。
	last_impact_casualty = (zombie.hp_component as HpComponentZombie).apply_hit(
		attack_value, mode, true, trigger_be_attack_sfx, true, armor)
	if is_instance_valid(zombie) and is_instance_valid(zombie.body):
		zombie.body.body_light()
	return last_impact_casualty as Zombie000Base


## 对 [param plant] 所在格的有效目标造成伤害；同帧被移除的目标不再调用受击接口。
func _attack_plant(plant:Plant000Base):
	plant = get_first_be_hit_plant_in_cell(plant)
	if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion():
		return
	## 攻击敌人
	plant.be_attacked_bullet(attack_value, bullet_mode, true, trigger_be_attack_sfx)


## 直线子弹先对壳类进行攻击
## 抛物线子弹先对Norm进行攻击
func get_first_be_hit_plant_in_cell(plant:Plant000Base)->Plant000Base:
	return plant

## [param enemy] 本次命中目标，可为空表示撞地或落空。[br]
## 先确认僵王命中次数与受击状态，再进入 [method _attack_enemy] 结算伤害及子类附加效果。
## 命中类型在扣血前保存，致死攻击的命中特效同样显示在机甲前方。
## 僵王命中特效保留命中时的位置；普通目标的特效继续对齐受击组件的全局 X。
func attack_once(enemy:Character000Base):
	if is_queued_for_deletion():
		return
	# 有来源的旧弹跨轮后直接退出，不能以零伤害继续消耗命中或触发受击。
	if attack_context != null and not attack_context.is_active():
		queue_free()
		return
	if enemy != null and not promotion_hit_factors.is_empty():
		if _promotion_hit_ids.has(enemy.get_instance_id()):
			return
		_promotion_hit_ids[enemy.get_instance_id()] = true
	if enemy is ZB000Base:
		if not _can_attack_character(enemy) or _hit_boss_ids.has(enemy.get_instance_id()):
			return
		if max_attack_num != -1 and curr_attack_num >= max_attack_num:
			return
		# 在发出伤害前登记，抵御伤害信号引发的重入；不持有已经释放的僵王引用。
		_hit_boss_ids[enemy.get_instance_id()] = true
	curr_attack_num += 1
	if max_attack_num != -1 and curr_attack_num > max_attack_num:
		return
	# 扣血可能触发目标死亡或释放，提前记录命中类型，供特效位置与层级处理使用。
	var is_boss_hit: bool = is_instance_valid(enemy) and enemy is ZB000Base
	# 穿透衰减只作用于当前命中；恢复基础伤害，后续命中按自身阶数单独计算。
	var original_damage: int = attack_value
	if not promotion_hit_factors.is_empty():
		var factor_index: int = mini(curr_attack_num - 1, promotion_hit_factors.size() - 1)
		attack_value = maxi(0, roundi(float(original_damage) * promotion_hit_factors[factor_index]))
	if attack_context != null and is_instance_valid(enemy):
		attack_value = attack_context.modify_damage(attack_value, enemy)
	last_impact_damage = attack_value
	last_impact_casualty = null
	## 对敌人造成伤害
	_attack_enemy(enemy)
	attack_value = original_damage
	if attack_context != null:
		attack_context.resolve_kill(last_impact_casualty) # 同步消费命中资格，最后一击已经切到结算也可奖励。
	## 是否有音效
	if type_bullet_SFX != SoundManagerClass.TypeBulletSFX.Null:
		SoundManager.play_bullet_attack_SFX(type_bullet_SFX)
	## 如果有子弹特效
	if bullet_effect.is_bullet_effect:
		# 穿透弹会继续飞行；中途命中特效复制后脱离，原始特效留给最后一次命中。
		var effect: BulletEffect000Base = bullet_effect
		if not promotion_hit_factors.is_empty() and curr_attack_num < max_attack_num:
			effect = bullet_effect.duplicate() as BulletEffect000Base
			add_child(effect)
			effect.owner = self
		# 僵王受击框较大，保留命中处的位置；普通目标按受击组件 X 对齐。
		if not is_boss_hit and is_instance_valid(enemy) and enemy is Character000Base:
			effect.global_position.x = enemy.hurt_box_component.global_position.x
		effect.activate_bullet_effect(is_boss_hit)

	## 判断是否进入删除队列
	impact_resolved.emit(enemy, global_position)
	if max_attack_num != -1 and curr_attack_num >= max_attack_num:
		queue_free()
