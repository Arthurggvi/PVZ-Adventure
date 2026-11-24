## 猎人僵尸：普通生命、移动和啃食沿用原组件，雪球投掷由独立行为组件负责。
extends Zombie000Base
class_name Zombie032Hunter

## 未受速度倍率影响时，走过当前实际种植格所需的秒数。
const WALK_SECONDS_PER_CELL: float = 8.0
## 仅随本物种加载的两条原版死亡声音；统一交给既有音效池处理音量与禁音。
const DEATH_SOUNDS: Array[AudioStream] = [
	preload("res://assets/adventure/zombies/hunter/audio/Hunterded1.ogg"),
	preload("res://assets/adventure/zombies/hunter/audio/Hunterded2.ogg"),
]
## 倒地声的播放增益（dB），多人同波死亡时给其他战斗声音留出余量。
const DEATH_GAIN_DB: float = -11.0
## 投掷动作与取消逻辑的唯一拥有者；展示实例不执行配置。
@onready var throw_component: HunterThrow = $HunterThrow
## 防止伤害、退场与重复死亡通知再次结算声音和死亡信号。
var _death_processed: bool = false

## 先保留原生生命和阵营初始化，再配置正式战斗的移动速度与投掷行为。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/HeadAnchor")])
	super()
	if character_init_type != E_CharacterInitType.IsNorm:
		return
	var game: MainGameManager = Global.main_game # 只使用本实例所属战场的真实格宽。
	if is_instance_valid(game) and game.board != null and game.is_ancestor_of(self):
		var width: float = game.board.cell_width_at(global_position, lane) # 格宽为世界横向像素；空行返回零。
		if width > 0.0:
			move_component.ori_speed = width / WALK_SECONDS_PER_CELL
			move_component.owner_update_speed(speed_factor_product())
	throw_component.configure(self)

## 返回完全冻结的物种资格；原寒冷入口会将冻结与后续减速合并为半速，不影响其他控制。
func can_cold_freeze() -> bool:
	return false

## 已有对应物种的完整倒地帧，致死爆炸继续使用该原动画及既有淡出回收。
func _preserves_blast_death_animation() -> bool:
	return true

## 先锁住死亡行动并取消投掷，再由父类发布原生死亡、计数、掉落和倒地动画。
func character_death() -> void:
	if _death_processed:
		return
	_death_processed = true
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	throw_component.finish_life()
	if character_init_type == E_CharacterInitType.IsNorm and not retiring_from_battle:
		var sound_index: int = randi_range(0, DEATH_SOUNDS.size() - 1) # 每次真实死亡只随机播放一个现成片段。
		SoundManager.play_sfx_with_pool(DEATH_SOUNDS[sound_index], DEATH_GAIN_DB)
	super()

## 真正离树时释放行为；大蒜换行的同步重挂保留投掷组件，避免恢复后永久失效。
func _exit_tree() -> void:
	if not is_changing_lane and is_instance_valid(throw_component):
		throw_component.finish_life()
