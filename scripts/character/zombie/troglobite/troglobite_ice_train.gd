## 安排整队从右侧入场；冰块各自向管理器登记，未入场时由推手负责护送。
extends Node
class_name TroglobiteIceTrain

## 原版每只穴居僵尸携带的冰封雪人小鬼数量。
const BLOCK_COUNT: int = 3
## 冰块之间留给轮廓边缘的间隙，单位为角色缩放前的像素。
const SHELL_GAP: float = 2.0
## 最前方冰壳左缘距离视口右侧的出生余量，单位为世界像素。
const ENTRY_PADDING: float = 12.0
## 作为穴居僵尸场景依赖提前准备，首次推冰不在战斗中同步导入小鬼整套动画。
@export var frozen_imp_scene: PackedScene
## 提供出生位置、等阶与护送的推手；已入场冰块的生命独立于推手。
var _source: Zombie000Base
## 本次战场身份，防止延迟生成串入下一局。
var _game: MainGameManager
## 配置时的棋盘；同一场景重装棋盘后也不执行旧出生请求。
var _board: BoardRuntime
## 本次续战轮次。
var _round: int = -1
## 本次冒险阶段；切换阶段后取消尚未执行的出生请求。
var _phase: StagePhaseDefinition
## 配置时的攻击行；延迟生成过程中换行会取消旧入场请求。
var _lane: int = -1
## 预排的冰块数，已扣除即将登记的穴居僵尸所占名额。
var _count: int = 0
## 冰链最后一块离推手脚点最近，其初始世界横坐标。
var _rear_x: float = 0.0
## 相邻冰块的世界中心距，跟随迷你模式的角色缩放。
var _spacing: float = 0.0
## 冰壳轮廓进入可见区时对应的世界中心 X，同时受波次清理线限制。
var _ice_entry_end_x: float = INF
## 本次实际登记的冰块，只在推手失去护送资格时通知它们。
var _escorted: Array[Zombie031YetiImp] = []
## 护送一经结束不再补生；已开始的滑行先完成再处理未入场的冰壳。
var _escort_ended: bool = false

## [param source] 已入树且尚未校正坡面。先将推手放到队列后方，登记后再创建冰块。
func configure(source: Zombie000Base) -> void:
	_source = source
	_game = Global.main_game
	if not is_instance_valid(_game) or _game.board == null or not _game.is_ancestor_of(source):
		return
	var manager: ZombieManager = _game.zombie_manager # 出生规划使用与登记相同的名额与行资格。
	_lane = source.lane
	if not manager.is_game_running() or not manager.can_spawn_zombie_in_lane(
			CharacterRegistry.ZombieType.Z031YetiImp, _lane):
		return
	_count = manager.available_zombie_slots(BLOCK_COUNT + 1) - 1
	if _count <= 0:
		return
	_board = _game.board
	_round = _game.curr_game_round
	_phase = AdventureSession.get_active_phase(_game.game_para)
	var scale_x: float = absf(source.global_scale.x) # 同行小鬼继承推手的迷你模式和画布缩放。
	var half_width: float = FrozenImpVisual.ICE_HALF_WIDTH * scale_x # 冰壳世界半宽。
	_spacing = half_width * 2.0 + SHELL_GAP * scale_x
	var hand_gap: float = absf(source.body.to_global(Vector2(-TroglobitePush.HAND_REACH, 0.0)).x
		- source.global_position.x) + half_width # 推手脚点到第一处手与冰壳接触的距离。
	var view: Rect2 = source.get_canvas_transform().affine_inverse() * source.get_viewport_rect() # 当前镜头下的世界可见范围。
	var front_x: float = view.end.x + half_width + ENTRY_PADDING # 最前一块也要完整处在画面外。
	for other: Zombie000Base in manager.all_zombies_2d[_lane]: # 已登记的离屏队列优先，避免同路同时出怪时重叠。
		if not is_instance_valid(other) or other.is_death or other.is_queued_for_deletion():
			continue
		if other.global_position.x >= view.end.x and (other.zombie_type == CharacterRegistry.ZombieType.Z030Troglobite \
				or (other is Zombie031YetiImp and other.is_frozen_block())):
			front_x = maxf(front_x, other.global_position.x + _spacing)
	var row: ZombieRow = manager.all_zombie_rows[_lane] # 用出怪点基线，避免把调用方旧格子的坡面高度带到场外。
	source.global_position = Vector2(maxf(source.global_position.x, front_x + _spacing * (_count - 1) + hand_gap),
		row.zombie_create_position.global_position.y)
	var cull_x: float = manager.zombie_range_pos_x.y # 入场期间登记豁免，完成后的出界仍由清理线负责。
	source.begin_right_entry(minf(view.end.x, cull_x))
	_ice_entry_end_x = minf(view.end.x + half_width, cull_x)
	_rear_x = source.global_position.x - hand_gap
	source.signal_lane_update.connect(end_escort)
	_spawn.call_deferred()

## 单次消费出生；全场数量上限仍由原管理器决定，不能用新物种绕开限额。
func _spawn() -> void:
	if not _is_current_battle():
		return
	var manager: ZombieManager = _game.zombie_manager # 每个冰块必须登记、计数并参与真实清场。
	var row: ZombieRow = manager.all_zombie_rows[_lane] # 同一攻击行，保持坡面与绘制层级。
	var parameters: Dictionary = { # 出生冰链是技能援军，不重复计入自然波的提前刷新数。
		Zombie000Base.E_ZInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
		Zombie000Base.E_ZInitAttr.Lane: _lane,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType: row.zombie_row_type,
		Zombie000Base.E_ZInitAttr.CurrWave: -1,
		Zombie000Base.E_ZInitAttr.IsMiniZombie: _source.is_mini_zombie,
		Zombie000Base.E_ZInitAttr.IsZombieMode: _source.is_zombie_mode,
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
	}
	for index: int in range(_count): # 先创建贴近手部的冰块，名额临时减少时仍能推行短队列。
		if not _is_current_battle() or manager.available_zombie_slots(1) == 0:
			break
		var point: Vector2 = Vector2(_rear_x - _spacing * index,
			row.zombie_create_position.global_position.y) # 小鬼ready按X自行补坡度一次。
		var modifier: ZombieSpawnModifier = AdventureZombieTierBinding.new(_source.adventure_tier_id) \
			if not _source.adventure_tier_id.is_empty() else null # 小鬼继承相同等阶，不继承母体的已损生命。
		var block: Zombie031YetiImp = manager.create_norm_zombie(CharacterRegistry.ZombieType.Z031YetiImp, row,
			parameters, point, _seal_before_ready, modifier, frozen_imp_scene) as Zombie031YetiImp # 完整登记后才持有护送关系。
		if not is_instance_valid(block):
			continue
		if _escort_ended:
			block.abandon_entry_escort()
			break
		_escorted.append(block)

## [param zombie] 尚未入树且已完成等阶数值绑定；冰壳由小鬼自己维护。
func _seal_before_ready(zombie: Zombie000Base) -> void:
	(zombie as Zombie031YetiImp).configure_frozen_spawn(_ice_entry_end_x)

## 断臂、死亡、魅惑或离开原攻击行结束护送；露出画面的冰块继续独立驻留。
func end_escort() -> void:
	if _escort_ended:
		return
	_escort_ended = true
	for block: Zombie031YetiImp in _escorted: # 关系由本队登记，别的推手或旧波的冰块不受影响。
		if is_instance_valid(block):
			block.abandon_entry_escort()
	_escorted.clear()

## 直接释放本体的路径也解绑护送；冰块自行决定完成滑行或退场。
func _exit_tree() -> void:
	end_escort()

## 当前母体必须仍属于原局、原轮次和原阶段，死亡/清场禁止补生冰块。
func _is_current_battle() -> bool:
	return not _escort_ended and is_instance_valid(_source) and not _source.is_death and not _source.retiring_from_battle \
		and not _source.is_queued_for_deletion() and _source.lane == _lane and is_instance_valid(_game) \
		and _game == Global.main_game and _game.is_inside_tree() and _game.is_ancestor_of(_source) \
		and _game.board == _board and _game.curr_game_round == _round \
		and AdventureSession.get_active_phase(_game.game_para) == _phase \
		and is_instance_valid(_game.zombie_manager) and _game.zombie_manager.is_game_running()
