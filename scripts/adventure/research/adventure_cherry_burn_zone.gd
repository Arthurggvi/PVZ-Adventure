## 爆燃的地面灼伤和零碎火焰，独立于已经消耗的炸弹实例。
extends Node2D
class_name AdventureCherryBurnZone

## 原版火焰场景只负责表现，由地火节点统一控制生存时间。
const FLAME_SCALE: float = 0.33
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


## 在 [param game] 的 [param origin] 和 [param lane] 生成地火。
## [param profile] 描述本次爆炸范围，[param damage] 为每跳伤害。
## [param interval] 与 [param duration] 为战斗秒数，[param flame_points] 为紧贴地面的表现坐标。
func ignite(game: MainGameManager, origin: Vector2, lane: int, profile: CombatExplosionProfile,
		damage: int, interval: float, duration: float, flame_points: PackedVector2Array) -> void:
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
	# 只摆少量小火焰。保留原火焰贴图与动画，由本区域统一移除。
	for point: Vector2 in flame_points: # 单处残火的世界位置。
		var flame := SceneRegistry.FIRE.instantiate() as BombEffectFire # 每处地火的独立表现。
		add_child(flame)
		flame.global_position = point
		flame.scale *= FLAME_SCALE
		flame.animation_player.play(&"fire_flame")


## 同一株子母雷的第二爆刷新地火持续时间，继续沿用原有伤害节拍。
func refresh() -> void:
	_remaining = _duration


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
			target.be_attacked_bullet(_damage, BulletRegistry.AttackMode.Norm, true, false)
