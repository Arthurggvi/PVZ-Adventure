## 冒险版土豆地雷技能实例：绑定一株真实地雷，使用原版 BombComponent 触雷入口。
## 耦合弹体与植物生命周期分离；所有命中及击杀收益走 AdventurePotatoExplosion。
extends Node
class_name AdventurePotatoPromotionEffects

var _mine: Plant005PotatoMine
var _bomb: BombComponentNorm
var _game: MainGameManager
var _rules: Dictionary = {}
var _visual_template: BombEffectBase
var _charged_time: float = 0.0
var _armed: bool = false
var _latest_blast: Dictionary = {}

## 战斗快照中的事件技能，影响种植生命周期的标志需在入树前设置。
func configure(mine: Plant005PotatoMine, events: Array[Dictionary]) -> void:
	_mine = mine
	for effect: Dictionary in events:
		var kind: String = str(effect.get("kind", ""))
		if kind.begins_with("potato_"):
			_rules[kind] = effect.duplicate(true)
	mine.battle_instant_arm = _rules.has("potato_instant")
	mine.battle_rearm = _rules.has("potato_regrow")

func _ready() -> void:
	_bomb = _mine.get_node_or_null("BombComponent") as BombComponentNorm
	_game = Global.main_game
	if _bomb == null or not is_instance_valid(_game):
		push_error("土豆地雷转职缺少原版爆炸组件或战斗场景")
		set_process(false)
		return
	_visual_template = _bomb.bomb_effect.duplicate() as BombEffectBase
	_bomb.damage_resolver = Callable(self, "_resolve_primary_blast")
	_bomb.signal_bomb_once.connect(_on_bomb_finished)
	_mine.signal_potato_armed.connect(_on_armed)
	set_process(false)

func _on_armed() -> void:
	_charged_time = 0.0
	_armed = true
	set_process(_rules.has("potato_charge"))

## 蓄势按有效出土时间计数，休眠期间及重复埋伏期间均不计时。
func _process(delta: float) -> void:
	if _armed and is_instance_valid(_mine) and not _mine.is_death:
		_charged_time += maxf(0.0, delta)

## 主雷爆炸的生命与命中结算延迟到物理 flush 结束，避免空间查询失败。
func _resolve_primary_blast() -> void:
	if not is_instance_valid(_mine) or not is_instance_valid(_game):
		return
	_latest_blast = _blast_context()
	if _latest_blast.is_empty():
		return
	var area: CollisionShape2D = _bomb.get_node("Area2DBomb/CollisionShape2D") as CollisionShape2D
	AdventurePotatoExplosion.detonate.call_deferred(
		_game, area.global_position, _mine.lane, _latest_blast)

## 原版 bomb_once 负责音乐与爆炸表现，随后按技能派发独立的耦合子弹。
func _on_bomb_finished() -> void:
	_armed = false
	set_process(false)
	if _rules.has("potato_coupling") and not _latest_blast.is_empty():
		_launch_potatoes(int(_rules["potato_coupling"].get("projectiles", 3)))
	# 重复引爆的地雷需要新的爆炸 FX，不能复用已被原版特效回收的节点。
	if _mine.battle_rearm and is_instance_valid(_visual_template):
		var next_visual: BombEffectBase = _visual_template.duplicate() as BombEffectBase
		_bomb.add_child(next_visual)
		_bomb.bomb_effect = next_visual

## 本次爆炸的快照固定蓄势倍率，子弹落地即使母雷已死亡也能继承全部伤害词条。
func _blast_context() -> Dictionary:
	var native_shape: CollisionShape2D = _bomb.get_node_or_null(
		"Area2DBomb/CollisionShape2D") as CollisionShape2D
	if native_shape == null or native_shape.shape == null:
		return {}
	var lane_radius: int = maxi(0, int(_rules.get("potato_spread", {}).get("range", 0)))
	var hit_shape: Shape2D = native_shape.shape
	if lane_radius > 0:
		var spread_shape := RectangleShape2D.new()
		var cell_size: Vector2 = _mine.plant_cell.size
		spread_shape.size = cell_size * float(2 * lane_radius + 1)
		hit_shape = spread_shape
	var damage: int = _bomb.resolved_damage()
	if _rules.has("potato_charge"):
		var growth: Dictionary = _rules["potato_charge"]
		var bonus: float = minf(float(growth.get("cap", 3.0)),
			floorf(_charged_time) * float(growth.get("step", 0.05)))
		damage = maxi(0, roundi(float(damage) * (1.0 + bonus)))
	if _rules.has("potato_frenzy"):
		damage = maxi(0, roundi(float(damage) *
			float(_rules["potato_frenzy"].get("damage", 2.0))))
	var snapshot: Dictionary = _mine.plant_spawn_profile.snapshot()
	return {
		"shape": hit_shape,
		"offset": Vector2.ZERO,
		"damage": damage,
		"lane_radius": lane_radius,
		"statuses": _bomb.can_attack_zombie_status,
		"card_uid": str(snapshot.get("uid", "")),
		"cooldown_per_kill": float(_rules.get("potato_frenzy", {}).get("cooldown_per_kill", 0.0)),
		"sun_per_kill": int(_rules.get("potato_energy", {}).get("sun_per_kill", 0)),
	}

## 每次耦合随机选取周围格子；发射3枚独立土豆子弹，不实例化植物或重新种植。
func _launch_potatoes(count: int) -> void:
	if count <= 0 or not is_instance_valid(_game) or not is_instance_valid(_game.bullets):
		return
	var destinations: Array[Dictionary] = [] # 即时地块坐标，不把稀疏数组下标当成列号。
	for cell: PlantCell in _game.board.neighbors(_mine.plant_cell): # 同平台拓扑邻接。
		destinations.append({"point": cell.get_global_rect().get_center(), "lane": cell.row_col.x})
	if destinations.is_empty():
		return
	destinations.shuffle()
	for index: int in range(count):
		var target: Dictionary = destinations[index % destinations.size()]
		var visual: BombEffectBase = _visual_template.duplicate() as BombEffectBase
		var bullet := AdventurePotatoProjectile.new()
		bullet.launch(_game, _mine.global_position,
			target["point"], int(target["lane"]), _latest_blast, visual)

## 离场回收独立爆炸模板；手套换格继续沿用本株模板和引信。
func _exit_tree() -> void:
	if is_instance_valid(_visual_template) and not _mine.is_being_relocated:
		_visual_template.free()
