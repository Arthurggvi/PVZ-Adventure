## 感电用的本场局部索敌。每个使用它的物理步只采样一次阵营与位置。
extends RefCounted

## 横向桶宽接近一格；行号使用棋盘的实际逻辑行。
const BUCKET_WIDTH: float = 88.0
## 空中、跳跃和地面僵尸都能被电弧跳到，地下和潜水不参与。
const SHOCK_STATES: int = Zombie000Base.E_BeAttackStatusZombie.IsNorm \
	| Zombie000Base.E_BeAttackStatusZombie.IsJump | Zombie000Base.E_BeAttackStatusZombie.IsSky

## 位置分桶保存轻量身份，桶数组跨物理步复用。
var _buckets: Dictionary[Vector2i, Array] = {}
## 本步真正使用过的桶；下一步清空这些桶。
var _touched: Array[Vector2i] = []
## 上次采样的帧号。
var _frame: int = -1

## 为 [param game] 当前物理步建立局部身份表，不在每个弹体上重复扫全场。
func refresh(game: MainGameManager) -> void:
	var frame: int = Engine.get_physics_frames() # 同一时间的所有感电共享快照。
	if _frame == frame:
		return
	_frame = frame
	# 回收上一物理步已有的桶，长时间离场的僵尸不会在表里留下身份。
	for key: Vector2i in _touched: # 仅清空实际使用项。
		_buckets[key].clear()
	_touched.clear()
	for target: Zombie000Base in game.zombie_manager.all_zombies_1d: # 原生阵营索引不含图鉴实例。
		if not eligible(target):
			continue
		var key := Vector2i(floori(target.global_position.x / BUCKET_WIDTH), target.lane) # 按真实脚点横坐标分桶。
		if not _buckets.has(key):
			_buckets[key] = []
		var bucket: Array = _buckets[key] # 复用桶容器，角色由原战场持有。
		if bucket.is_empty():
			_touched.append(key)
		bucket.append(target)
	# 稀疏或移动平台经过的旧桶不会无限保留。
	if _buckets.size() > maxi(128, _touched.size() * 3):
		var current: Dictionary[Vector2i, Array] = {} # 活跃桶直接转移，不复制其候选。
		for key: Vector2i in _touched: # 删除的是废弃段，而非在用队列。
			current[key] = _buckets[key]
		_buckets = current

## 选择从 [param x] 与 [param lane] 出发的最近敌人。[param pitch] 取原地实际格距，
## [param visited] 含链起点与已命中角色。一跳只查看相邻行与一格横向范围。
func nearest(x: float, lane: int, pitch: Vector2, visited: PackedInt64Array) -> Zombie000Base:
	var nearest_target: Zombie000Base # 没有可用资格时通知整道链自然结束。
	var best: float = INF # 最近距离平方，与芦苇一致使用行差换算。
	var best_id: int = 0 # 等距时选先注册者，让路径稳定。
	var first: int = floori((x - pitch.x) / BUCKET_WIDTH) # 一格覆盖的最左分桶。
	var last: int = floori((x + pitch.x) / BUCKET_WIDTH) # 一格覆盖的最右分桶。
	for row: int in range(lane - 1, lane + 2): # 同行及上下相邻行。
		var y: float = (row - lane) * pitch.y # 空中表现不影响格距。
		for col: int in range(first, last + 1): # 只读取与本次局部搜索重叠的桶。
			var bucket: Variant = _buckets.get(Vector2i(col, row)) # 空桶不分配临时数组。
			if bucket == null:
				continue
			for candidate: Variant in bucket: # 同步伤害可能已经从战场摘除身份。
				if not is_instance_valid(candidate) or candidate.lane != row:
					continue
				var offset: float = candidate.global_position.x - x # 最终使用当前脚点。
				var score: float = offset * offset + y * y # 固定档位使用平方距离，免开方。
				if absf(offset) > pitch.x or score > best:
					continue
				var id: int = candidate.get_instance_id() # 本链不重复命中，不影响其他独立触发。
				if not visited.has(id) and eligible(candidate) and (score < best or id < best_id):
					best = score
					best_id = id
					nearest_target = candidate
	return nearest_target

## [param target] 符合感电的状态位及地形行号限制。
static func eligible(target: Zombie000Base) -> bool:
	return targetable(target) and (target.curr_be_attack_status & SHOCK_STATES) != 0 and target.lane >= 0

## [param target] 能在当前格子被直接命中；落雷对合法受击框不筛分地面、空中及水下。
static func targetable(target: Zombie000Base) -> bool:
	return is_instance_valid(target) and not target.is_death and not target.is_hypno and not target.is_queued_for_deletion() \
		and target.is_inside_tree() and is_instance_valid(target.hurt_box_component) and target.hurt_box_component.is_enabling

## 返回 [param target] 的活动受击点坐标，缺少对应部件时保留角色世界位置。
static func impact_point(target: Character000Base) -> Vector2:
	if not is_instance_valid(target.hurt_box_component) or not is_instance_valid(target.hurt_box_component.hurt_box_real):
		return target.global_position
	var area: Area2D = target.hurt_box_component.hurt_box_real # 与芦苇相同优先读取实际命中形状。
	var point := area.get_node_or_null(^"CollisionShape2D") as Node2D # 动态僵尸可替换形状。
	return point.global_position if point != null else area.global_position
