## 一次出手的整链位移。行节点持有本次推力，所有冰块共用同一个时钟。
extends Node

## 每次扫掠的最大距离，单位为世界像素；长帧依旧检查经过的种植格。
const SWEEP_STEP: float = 16.0
## 出手时的战场，切场后不再推进。
var _game: MainGameManager
## 出手时的棋盘，战斗重建棋盘后作废。
var _board: BoardRuntime
## 本次推力所属的行容器，即使推手离场也保有此空间。
var _row: ZombieRow
## 行容器对应的零基索引，用于查询该行冰壳。
var _lane: int = -1
## 发力时的续战轮次；换轮取消未完成的位移。
var _round: int = -1
## 发力时的冒险阶段；普通战斗为 null。
var _phase: StagePhaseDefinition
## 提供实时速率的存活推手，可在推行途中离场。
var _source: Zombie000Base
## 失去推手后继续本次推力所用的最后一个正速率。
var _last_rate: float = 1.0
## 本次统一预留的冰块；破甲可单独退出，其他冰块保留本次推进进度。
var _members: Array[Zombie031YetiImp] = []
## 总计划左移距离，单位为世界像素。
var _distance: float = 0.0
## 走完计划距离所用的动作秒。
var _seconds: float = 0.0
## 当前已经推进的动作秒；暂时受控时保留进度。
var _elapsed: float = 0.0

## [param game] 与 [param source] 确定战局和行号。[param members] 为接触的冰块。
## 一次性预留全链，并从当前坐标开始推 [param distance] 像素、历时 [param seconds] 动作秒。
## 返回 false 时不改变冰块；成功后由调用方将本节点挂到推手所在行。
func prepare(game: MainGameManager, source: Zombie000Base, members: Array[Zombie031YetiImp],
		distance: float, seconds: float) -> bool:
	if members.is_empty() or not is_finite(distance) or distance <= 0.0 \
			or not is_finite(seconds) or seconds <= 0.0 or not source.get_parent() is ZombieRow:
		return false
	for block: Zombie031YetiImp in members: # 校验期间不提交任何部分位移或冰块预留。
		if not is_instance_valid(block) or not block.is_frozen_block() or block.is_ice_sliding() \
				or block.get_parent() != source.get_parent() or block.lane != source.lane:
			return false
	_game = game
	_board = game.board
	_row = source.get_parent() as ZombieRow
	_lane = source.lane
	_round = game.curr_game_round
	_phase = AdventureSession.get_active_phase(game.game_para)
	_source = source
	_last_rate = source.speed_factor_product()
	_members.assign(members)
	_distance = distance
	_seconds = seconds
	for block: Zombie031YetiImp in _members: # 所有冰块在首次物理更新前就收到相同的推行拥有者。
		block.claim_ice_motion(self)
	return true

## [param delta] 为战斗秒。同一子步按前到后移动各块，再读回实际接触边缘。
func _physics_process(delta: float) -> void:
	if not _battle_active():
		_finish()
		return
	var before: float = _elapsed / _seconds # 本帧开始前已经消费的总轨迹比例。
	_elapsed = minf(_seconds, _elapsed + delta * _motion_rate())
	var remaining: float = _distance * (_elapsed / _seconds - before) # 整链本帧共用的计划距离。
	while not is_zero_approx(remaining):
		var step: float = minf(remaining, SWEEP_STEP) # 本子步的横移上限。
		if not _advance_row(step):
			_finish()
			return
		remaining -= step
	if _elapsed >= _seconds:
		_finish()

## 推手暂时受控时停钟；失去推手仍能完成已提交的有限推力。
func _motion_rate() -> float:
	if is_instance_valid(_source) and not _source.is_death and not _source.is_queued_for_deletion() \
			and not _source.is_hypno and _source.get_parent() == _row and _source.lane == _lane:
		var rate: float = _source.speed_factor_product() # 只消费一次合成角色速率。
		if is_finite(rate):
			if rate > 0.0:
				_last_rate = rate
			return maxf(0.0, rate)
	return _last_rate

## [param distance] 为向左的世界步长。静止冰块和其他推力的冰块均按真实边缘挡住后块。
## 返回是否还有成员；即使前块没走满一步，后块仍能走到贴边。
func _advance_row(distance: float) -> bool:
	var ahead_right: float = -INF # 按当前真实位置累计已处理冰壳的最右边缘。
	var has_member: bool = false # 破甲以后没有任何成员时立即结束推力。
	for block: Zombie031YetiImp in lane_blocks(_game.zombie_manager, _lane): # 先结算前块，再裁后块位移。
		if not is_instance_valid(block) or not block.is_frozen_block():
			continue
		var half_width: float = block.ice_half_width() # 接触与移动都按冰壳的实际缩放。
		if block.belongs_to_ice_motion(self):
			has_member = true
			var available: float = maxf(0.0, block.global_position.x - half_width - ahead_right) # 到前方边缘尚能走的距离。
			var step: float = minf(available, distance) # 贴边之后不再向前块内部移动。
			if not is_zero_approx(step):
				block.advance_ice(self, step)
		if is_instance_valid(block) and block.is_frozen_block():
			ahead_right = maxf(ahead_right, block.global_position.x + half_width)
	return has_member

## 返回 [param manager] 的 [param lane] 当前仍被冻结的敌方冰块，按从前到后排列。
static func lane_blocks(manager: ZombieManager, lane: int) -> Array[Zombie031YetiImp]:
	var blocks: Array[Zombie031YetiImp] = [] # 不修改管理器的存活登记顺序。
	for zombie: Zombie000Base in manager.all_zombies_2d[lane]: # 仅采样本路，不靠节点添加顺序。
		if is_instance_valid(zombie) and zombie is Zombie031YetiImp and zombie.is_frozen_block() and not zombie.is_hypno:
			blocks.append(zombie as Zombie031YetiImp)
	blocks.sort_custom(_left_first)
	return blocks

## 按 [param left] 和 [param right] 的世界 X 确定空间前后。
static func _left_first(left: Zombie031YetiImp, right: Zombie031YetiImp) -> bool:
	return left.global_position.x < right.global_position.x

## 只在发力的原战局、原棋盘、原行及原阶段有效。
func _battle_active() -> bool:
	return is_instance_valid(_game) and _game == Global.main_game and _game.board == _board \
		and _game.curr_game_round == _round and AdventureSession.get_active_phase(_game.game_para) == _phase \
		and _game.zombie_manager.is_game_running() and is_instance_valid(_row) \
		and get_parent() == _row and _lane >= 0 and _lane < _game.zombie_manager.all_zombie_rows.size() \
		and _game.zombie_manager.all_zombie_rows[_lane] == _row

## 本次时钟结束后立即归还所有有效冰块，下次出手能取得已经贴边的整链。
func _finish() -> void:
	_release_members()
	set_physics_process(false)
	queue_free()

## 切场、清行导致节点直接离树时同样归还冰块。
func _exit_tree() -> void:
	_release_members()

## 只释放本次预留；已经破甲或转成其他状态的冰块不重新上锁。
func _release_members() -> void:
	for block: Zombie031YetiImp in _members: # 区分仍活着的冰块和已被释放的节点。
		if is_instance_valid(block):
			block.release_ice_motion(self)
	_members.clear()
