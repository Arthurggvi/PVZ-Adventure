## 爆燃的地面灼伤与整片余火，独立于已经消耗的炸弹实例。
extends Node2D
class_name AdventureCherryBurnZone

## 单格地火只负责绘制，由本节点统一同步时限和复燃。
const GroundFireVisual = preload("res://scripts/fx/cherry_ground_fire.gd")
## 时限比较容差，确保整 2 秒的最后一次伤害不会被浮点余数跳过。
const TIME_EPSILON: float = 0.00001

## 当前火焰所属战场。
var _game: MainGameManager
## 创建地火的轮次，换轮后清除。
var _round: int
## 爆炸的原始地面范围。
var _profile: CombatExplosionProfile
## 范围中心所在的行。
var _lane: int
## 已包含星级修正的每跳灼伤伤害。
var _damage: int
## 一次点燃后可存在的战斗秒数。
var _duration: float
## 本次地火剩余的战斗秒数。
var _remaining: float
## 两次灼伤之间的战斗秒数。
var _interval: float
## 距下一跳伤害的战斗秒数。
var _until_tick: float
## 点燃后的表现时间，刷新持续时间时保持相位连续。
var _visual_age: float = 0.0
## 最近一次主爆后的秒数，用于子母雷短暂提亮现有地火。
var _since_flare: float = 0.0
## 该片地火的轻量表现节点，随控制器一起释放。
var _flames: Array[GroundFireVisual] = []


## 在 [param game] 的 [param origin] 和 [param lane] 生成地火。
## [param profile] 描述本次爆炸范围，[param damage] 为每跳伤害。
## [param interval] 与 [param duration] 为战斗秒数，[param cells] 为完整覆盖的地块快照。
func ignite(game: MainGameManager, origin: Vector2, lane: int, profile: CombatExplosionProfile,
		damage: int, interval: float, duration: float, cells: Array[PlantCell]) -> void:
	if interval <= TIME_EPSILON or duration <= 0.0:
		queue_free()
		return
	_game = game
	_round = game.curr_game_round
	_profile = profile
	_lane = lane
	_damage = damage
	_interval = interval
	_until_tick = interval
	_duration = duration
	_remaining = duration
	game.bombs.add_child(self)
	global_position = origin
	# 每个波及格都布置表现，聚变的 5×5 四角与边缘不再缺火。
	for cell: PlantCell in cells: # 冻结世界位置，与本次不移动的伤害范围保持相同生命周期。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		var flame := GroundFireVisual.new() # 每格只创建一个绘制节点，不复制整套火焰动画树。
		flame.cell_size = cell.get_global_rect().size
		flame.variation = float(cell.row_col.x * 17 + cell.row_col.y * 7)
		flame.z_as_relative = false
		flame.z_index = cell.row_col.x * 50 + 10
		add_child(flame)
		flame.global_position = cell.get_slot_anchor_global_position(CharacterRegistry.PlacePlantInCell.Norm)
		if profile.shape is CircleShape2D:
			# 与爆炸的检测平面一致，屋顶只影响火焰的绘制高度，不让斜角格冒出范围外的火。
			flame.clip_radius = (profile.shape as CircleShape2D).radius
			flame.clip_center = origin - (flame.global_position - Vector2(0.0, cell.get_ground_height()))
		_flames.append(flame)


## 同一株子母雷的第二爆刷新地火持续时间，继续沿用原有伤害节拍。
func refresh() -> void:
	_remaining = _duration
	_since_flare = 0.0


## [param delta] 为表现秒数；火舌使用连续时钟，淡出仍严格服从伤害控制器的剩余时间。
func _process(delta: float) -> void:
	_visual_age += delta
	_since_flare += delta
	for flame: GroundFireVisual in _flames: # 同步同一片地火，子母雷不叠加新节点或额外伤害跳。
		flame.update_visual(_visual_age, _remaining, 1.0 - smoothstep(0.0, 0.3, _since_flare))


## [param delta] 为游戏秒数。战斗暂停时由场景树暂停，结束或换轮后停止伤害。
func _physics_process(delta: float) -> void:
	if not _battle_active():
		queue_free()
		return
	# 本帧只有处于火焰有效期内的时间可以触发伤害。
	var active_delta: float = minf(_remaining, delta)
	_remaining -= active_delta
	_until_tick -= active_delta
	while _until_tick <= TIME_EPSILON and _battle_active():
		_burn_tick()
		_until_tick += _interval
	if _remaining <= TIME_EPSILON:
		queue_free()


## 确认本轮仍接受地火伤害，僵王死亡回调可在伤害跳中同步结束战斗。
func _battle_active() -> bool:
	return is_instance_valid(_game) and not _game.is_queued_for_deletion() \
		and _game.curr_game_round == _round \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME


## 灼伤只作用于地面僵尸。伤害仍经过普通受击、护甲和减伤管线。
func _burn_tick() -> void:
	if _damage <= 0:
		return
	# 每次伤害重新查询，走出范围或升空的僵尸不再受伤。
	var areas: Array[Area2D] = CombatExplosion.query_areas( # 仍与地火范围重叠的受击区。
		_game.get_world_2d().direct_space_state, _profile, global_position)
	var targets: Array[Character000Base] = CombatExplosion.plant_blast_targets( # 地面命中的去重目标。
		areas, _lane, _profile.lane_radius, Zombie000Base.E_BeAttackStatusZombie.IsNorm)
	for target: Variant in targets: # 前一个受击回调可能已移除或魅惑后续对象。
		if not _battle_active():
			return
		if is_instance_valid(target) and not target.is_death and not target.is_queued_for_deletion() \
				and not target.is_hypno and (target is Zombie000Base or target is ZB000Base):
			if target is Zombie000Base and is_instance_valid(target.move_component) and target.move_component.is_forced_airborne():
				continue
			target.be_attacked_bullet(_damage, BulletRegistry.AttackMode.Norm, true, false, 0, -1, null,
				CombatHitScope.for_cause(CombatHitScope.DeathCause.FIRE))
