## 根弹、暴雪加射与冰雕棱锥共享冻结的寒冰发射来源及书目。
extends RefCounted
class_name SnowPeaShot

## 与双发共用的战场、棋盘、轮次、阶段及攻击上下文。
var battle: RepeaterShotContext
## 本株已选书目。
var loadout: SnowPeaLoadout
## 原生寒冰弹减速时长，单位为秒。
var slow_seconds: float
## 原生发射的行、命中状态与伤害参数。
var _params: Dictionary[Bullet000NormBase.E_InitParasAttr, Variant]
## 未缩放的原生弹体伤害，派生弹仅应用一次出战倍率。
var _base_damage: int

## [param identity] 为战场快照；[param rules] 为冻结书目。
## [param bullet] 提供原生弹体未缩放的基础伤害及减速时长。
func _init(identity: RepeaterShotContext, rules: SnowPeaLoadout, bullet: Bullet002PeaSnow) -> void:
	battle = identity
	loadout = rules
	slow_seconds = bullet.time_be_decelerated
	_base_damage = bullet.attack_value

## 根弹从 [param params] 冻结实际初始化参数。仅首次冻结返回 true，派生弹复用同一快照。
func freeze_native_parameters(params: Dictionary) -> bool:
	if not _params.is_empty():
		return false
	_params.assign(params)
	return true

## 返回原生发射点在世界中的位置，独立于派生弹自己的出生位置。
func native_origin() -> Vector2:
	return battle.game.bullets.to_global(_params[Bullet000NormBase.E_InitParasAttr.Position])

## 返回该发的原生命中状态位；冰痕与溅射保留此资格。
func zombie_statuses() -> int:
	return int(_params[Bullet000NormBase.E_InitParasAttr.CanAttackZombieState])

## [param bullet] 是刚实例化的寒冰弹；初始化前安装技能与场景门禁。
func arm_native(bullet: Bullet002PeaSnow) -> void:
	bullet.promotion_shot = self
	bullet.attack_validity = battle.is_active

## [param position]、[param direction]、[param lane] 为派生弹发射位置、方向和行。
## [param prism] 选择跨行棱锥；普通加射仍继承原生行限制。
func emit_projectile(position: Vector2, direction: Vector2, lane: int, prism: bool = false) -> void:
	if not battle.is_active() or _params.is_empty():
		return
	var scene: PackedScene = load("res://scenes/bullet/bullet_snow_pea_prism.tscn") if prism \
		else Global.bullet_registry.get_bullet_scenes(BulletRegistry.BulletType.Bullet002PeaSnow) # 加射保留原生弹体。
	var bullet := scene.instantiate() as Bullet002PeaSnow # 共用命中规则，只替换棱锥的几何和表现。
	var params: Dictionary[Bullet000NormBase.E_InitParasAttr, Variant] = _params.duplicate() # 每发独立定位。
	params[Bullet000NormBase.E_InitParasAttr.Position] = battle.game.bullets.to_local(position)
	params[Bullet000NormBase.E_InitParasAttr.Direction] = direction
	params[Bullet000NormBase.E_InitParasAttr.BulletLane] = lane
	if prism:
		params[Bullet000NormBase.E_InitParasAttr.IsActivateLane] = false
	bullet.attack_value = _base_damage
	bullet.is_prism = prism
	arm_native(bullet)
	bullet.init_bullet(params)
	battle.game.bullets.add_child(bullet)
