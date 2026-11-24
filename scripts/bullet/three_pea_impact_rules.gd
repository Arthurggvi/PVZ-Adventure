## 每株共享的三线射手命中规则。弹体保留出膛配置，催折的状态上限为战斗行数。
extends RefCounted

## 陷阵使用目标上的单一计时节点，后续命中只续时。
const AssaultSlow = preload("res://scripts/bullet/three_pea_assault_slow.gd")


## 陷阵的减速持续秒数。
var _slow_seconds: float = 0.0
## 陷阵减速期间保留的原移动速率比例。
var _move_rate: float = 1.0
## 鏖战的劣化比例。
var _degradation: float = 0.0
## 封锁的眩晕秒数。
var _stun: float = 0.0
## 催折达到一格需要的连续首中次数；零表示没有催折。
var _sunder_hits: int = 0

## 每条实际攻击行上一次首次命中的目标实例 ID。
var _last_targets: Dictionary[int, int] = {}
## 每条实际攻击行对当前目标的连续首中次数。
var _streaks: Dictionary[int, int] = {}
## 当前连击所属的战斗轮次。
var _round: int = -1
## 当前连击所属的棋盘实例 ID。
var _board_id: int = 0
## 当前连击所属的冒险阶段实例 ID；普通关卡使用零。
var _phase_id: int = 0

## 入树前冻结 [param rule]。技能书数值不在每次命中时重复解析。
func configure(rule: Dictionary) -> void:
	match str(rule.kind):
		"threepeater_assault":
			_slow_seconds = float(rule.slow_seconds)
			_move_rate = float(rule.slow_ratio)
		"threepeater_siege":
			_degradation = float(rule.degradation)
		"threepeater_sunder":
			_sunder_hits = int(rule.hits)
		"threepeater_lockdown":
			_stun = float(rule.stun)

## 只有选了催折的贯穿攻击需要先定位第一名敌人。
func requires_forward_order() -> bool:
	return _sunder_hits > 0

## 对直接命中的 [param target] 附加状态。[param first_impact] 和 [param had_armor2] 在扣血前冻结。
## [param shot] 负责战局有效性并提供实际格宽，[param facing] 为出射横向。
func apply(target: Character000Base, first_impact: bool, had_armor2: bool,
		shot: RepeaterShotContext, facing: float) -> void:
	if not shot.is_active() or not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion():
		return
	if _slow_seconds > 0.0:
		AssaultSlow.apply(target, _slow_seconds, _move_rate)
	if _degradation > 0.0:
		AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.DEGRADATION, shot.source_id, _degradation)
	if _stun > 0.0:
		AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.STUN, shot.source_id, _stun)
	if first_impact and _sunder_hits > 0 and target is Zombie000Base:
		_sunder(target, had_armor2, shot, facing)

## [param zombie] 是本弹首先命中的普通僵尸。不同目标打断同一实际行的连击。
## 命中前有二类防具时 [param had_armor2] 为真，破甲的本击也不会击退。
## [param shot] 和 [param facing] 提供世界格宽及屏幕限制所需的来源。
func _sunder(zombie: Zombie000Base, had_armor2: bool, shot: RepeaterShotContext, facing: float) -> void:
	if zombie.is_hypno or not is_instance_valid(zombie.move_component):
		return
	var board_id: int = shot.board.get_instance_id() # 同一场景切换棋盘也不延续连击。
	var phase_id: int = shot.phase.get_instance_id() if shot.phase != null else 0 # 原版关卡无阶段资源。
	if _round != shot.round_index or _board_id != board_id or _phase_id != phase_id:
		_round = shot.round_index
		_board_id = board_id
		_phase_id = phase_id
		_last_targets.clear()
		_streaks.clear()
	var row: int = zombie.lane # 区分三条有效支路，同时允许边路补发累计到本行。
	var identity: int = zombie.get_instance_id() # 只保存实例编号，不持有已退场敌人。
	if had_armor2 or not zombie.move_component.can_receive_forced_displacement():
		_last_targets.erase(row)
		_streaks.erase(row)
		return
	var count: int = 1 # 首中或本行换目标后从最轻的一级开始。
	if _last_targets.get(row, 0) == identity:
		count = mini(_sunder_hits, _streaks[row] + 1)
	_last_targets[row] = identity
	_streaks[row] = count
	var desired: float = shot.cell_pitch.x * count / _sunder_hits # 六次达到发射地块的一格。
	var available: float = _screen_room(zombie, shot.game, facing) # 不把实际受击轮廓推出可见边界。
	if available > 0.0:
		zombie.move_component.apply_forced_displacement(Vector2(minf(desired, available) * facing, 0.0))

## 返回 [param zombie] 沿 [param facing] 到 [param game] 可见边界及清场线的安全剩余横距。
static func _screen_room(zombie: Zombie000Base, game: MainGameManager, facing: float) -> float:
	var screen: Rect2 = BloomerangFlightQuery.screen_rect(zombie) # 世界坐标下的相机裁切，随缩放和滚动改变。
	var clear: Vector2 = game.zombie_manager.zombie_range_pos_x # 保留机械清场线更靠内的一侧。
	var edge: float = minf(screen.end.x, clear.y) if facing > 0.0 else maxf(screen.position.x, clear.x) # 当前方向的有效端点。
	var front: float = zombie.global_position.x # 非标准或失效受击框仍保护真实实体脚点。
	var area: Area2D = zombie.hurt_box_component.hurt_box_real \
		if is_instance_valid(zombie.hurt_box_component) else null # 受击框失效时退回脚点。
	if is_instance_valid(area):
		for owner_id: int in area.get_shape_owners(): # 多形状独立取世界边界。
			if area.is_shape_owner_disabled(owner_id):
				continue
			var at: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 角色可能镜像或在斜坡上。
			for index: int in range(area.shape_owner_get_shape_count(owner_id)): # 仅阅读已有碰撞资源。
				var shape: Shape2D = area.shape_owner_get_shape(owner_id, index) # 原生受击形状。
				if shape == null:
					continue
				var bounds: Rect2 = at * shape.get_rect() # 世界包围盒保护整个受击宽度。
				front = maxf(front, bounds.end.x) if facing > 0.0 else minf(front, bounds.position.x)
	return maxf(0.0, (edge - front) * facing - 0.01)
