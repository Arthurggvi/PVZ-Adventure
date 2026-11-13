## 单株咖啡临时增益；同族续时，独立攻击来源到期只撤销自己。
extends Node
class_name CoffeePlantBoost

## 每株至多一个控制器，同类咖啡不能新建来源无限叠加。
const NODE_NAME: StringName = &"CoffeePlantBoost"
## 实际受益植物，承托层同步重挂时仍沿用原实例。
var _plant: Plant000Base
## 受益时的战场，离开原战场后不得继续授予来源。
var _game: MainGameManager
## 咖啡因剩余战斗秒数，不受植物成长或生产速度影响。
var _haste_seconds: float = 0.0
## 绿原酸剩余战斗秒数，与咖啡因分别续时。
var _damage_seconds: float = 0.0
## 当前咖啡因基础攻速加值。
var _haste_bonus: float = 0.0
## 当前绿原酸基础伤害加值。
var _damage_bonus: float = 0.0
## 最近已输出的攻速，避免每帧重设原生攻击时钟。
var _applied_haste: float = -1.0
## 最近已输出的伤害，避免无变化时重复重算。
var _applied_damage: float = -1.0
## 本控制器独有的伤害来源，旧节点退出不能误删后来新建的来源。
var _damage_source: StringName

## 向 [param plant] 授予 [param kind] 的 [param bonus] 加成并续时 [param seconds] 战斗秒。
## 已死或无效参数返回 false；同族只更新一份来源，不累计倍率或时间。
static func grant(plant: Plant000Base, kind: String, bonus: float, seconds: float) -> bool:
	if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion() \
			or not plant.is_inside_tree() or not is_finite(bonus) or not is_finite(seconds) \
			or bonus <= 0.0 or seconds <= 0.0 or kind not in ["coffee_haste", "coffee_damage"]:
		return false
	var boost: CoffeePlantBoost = plant.get_node_or_null(NodePath(NODE_NAME)) as CoffeePlantBoost # 同株所有咖啡共用一份租约。
	if boost == null:
		boost = CoffeePlantBoost.new()
		boost.name = NODE_NAME
		boost._plant = plant
		boost._game = Global.main_game
		boost._damage_source = StringName("coffee_damage_%d" % boost.get_instance_id())
		plant.add_child(boost)
	if boost.is_queued_for_deletion():
		return false
	if kind == "coffee_haste":
		boost._haste_bonus = bonus
		boost._haste_seconds = seconds
	else:
		boost._damage_bonus = bonus
		boost._damage_seconds = seconds
	boost.set_process(true)
	boost._sync()
	return true

## 受益者已就绪时才安装，死亡立即撤销输出；暂停沿用战场时间。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_plant.signal_character_death.connect(_clear, CONNECT_ONE_SHOT)
	set_process(false)

## [param delta] 是本帧战斗秒数；来源失效时可撤销，但支撑层重挂不会重置租约。
func _process(delta: float) -> void:
	if not is_instance_valid(_plant) or not is_instance_valid(_game) \
			or _plant.is_death or not _game.is_inside_tree() or _game.is_queued_for_deletion() \
			or _game != Global.main_game or _game.get_tree().current_scene != _game:
		_clear()
		return
	if _game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return
	_haste_seconds = maxf(0.0, _haste_seconds - delta)
	_damage_seconds = maxf(0.0, _damage_seconds - delta)
	_sync()
	if _haste_seconds <= 0.0 and _damage_seconds <= 0.0:
		set_process(false)

## 输出当前仍然有效的增益；无效化期间不借咖啡重新启用植物能力。
func _sync() -> void:
	if not is_instance_valid(_plant):
		return
	var active: bool = MushroomPlantQuery.is_active(_plant, _game) # 普通生产植物也使用相同的存活与场景校验。
	var haste: float = _haste_bonus if active and _haste_seconds > 0.0 else 0.0 # 到期只撤销当前控制器的攻击来源。
	var damage: float = _damage_bonus if active and _damage_seconds > 0.0 else 0.0 # 其他光环加成继续保留。
	if not is_equal_approx(haste, _applied_haste):
		_set_attack_source(_plant, get_instance_id(), haste)
		_applied_haste = haste
	if not is_equal_approx(damage, _applied_damage):
		_plant.set_battle_aura_damage_source(_damage_source, damage)
		_applied_damage = damage

## 清空本株两项剩余租约并同步撤销，不修改卡片或其他效果来源。
func _clear() -> void:
	_haste_seconds = 0.0
	_damage_seconds = 0.0
	_sync()
	set_process(false)

## [param plant] 的攻击来源 [param source] 仅影响攻击计时和攻击动画。
## [param bonus] 为零时移除；不改变产光、长大或植物整体速度。
static func _set_attack_source(plant: Plant000Base, source: int, bonus: float) -> void:
	if not is_instance_valid(plant):
		return
	var attack: AttackComponentBulletBase = plant.get_node_or_null(^"AttackComponent") as AttackComponentBulletBase # 原生射击和喷射共用攻击时钟。
	var magnet: MagnetComponent = plant.get_node_or_null(^"MagnetComponent") as MagnetComponent # 磁力攻击使用自己的时钟。
	if attack != null:
		attack.set_attack_rate_source(source, bonus)
	if magnet != null:
		magnet.set_attack_rate_source(source, bonus)

## 延后区分同帧承托重挂与真正离场，保留前者的原始剩余时间和攻击周期。
func _exit_tree() -> void:
	if is_instance_valid(_plant):
		CoffeePlantBoost._finish_exit.call_deferred(weakref(self), weakref(_plant),
			get_instance_id(), _damage_source)

## [param reference]、[param target_ref] 可已释放；只撤销 [param source] 与 [param damage_source]。
static func _finish_exit(reference: WeakRef, target_ref: WeakRef, source: int, damage_source: StringName) -> void:
	var boost: CoffeePlantBoost = reference.get_ref() as CoffeePlantBoost # 同步重挂结束后仍在原株内，继续计时。
	var plant: Plant000Base = target_ref.get_ref() as Plant000Base # 控制器单独删除时植物可能仍然存活。
	if is_instance_valid(boost) and boost.is_inside_tree() and is_instance_valid(plant) \
			and plant.is_ancestor_of(boost) and MushroomPlantQuery.is_active(plant, boost._game):
		return
	_set_attack_source(plant, source, 0.0)
	if is_instance_valid(plant):
		plant.set_battle_aura_damage_source(damage_source, 0.0)
	if is_instance_valid(boost):
		boost._haste_seconds = 0.0
		boost._damage_seconds = 0.0
		boost._applied_haste = 0.0
		boost._applied_damage = 0.0
		boost.set_process(false)
