## 猎人三连投的唯一状态机；出手绑定原帧事件，停止、减速和换行均不遗留延迟发射。
extends Node
class_name HunterThrow

## 原投掷动画首次空手的零基帧号，对应原素材第26帧。
const RELEASE_FRAME: int = 25
## 原图出手时的手心相对脚点，已经包含素材的二分之一缩放。
const HAND_OFFSET: Vector2 = Vector2(-84.25, -51.0)
## 开始一轮投掷的最大范围，按当前实际格宽换算。
const REACH_CELLS: float = 4.0
## 每轮完整原投掷动作数量，每个动作只创建一颗雪球。
const BURST_SIZE: int = 3
## 三连投或中断后恢复步行的标准动作秒数，寒冷和时钟技能共同减慢。
const RECOVERY_SECONDS: float = 6.0
## 每次动作开始复用一条原版用力声。
const EFFORT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/adventure/zombies/hunter/audio/Throwingsnowball1.ogg"),
	preload("res://assets/adventure/zombies/hunter/audio/Throwingsnowball2.ogg"),
	preload("res://assets/adventure/zombies/hunter/audio/Throwingsnowball3.ogg"),
]
## 仅真正生成雪球时播放的原版出手声。
const RELEASE_SOUNDS: Array[AudioStream] = [
	preload("res://assets/adventure/zombies/hunter/audio/Snowballthrown1.ogg"),
	preload("res://assets/adventure/zombies/hunter/audio/Snowballthrown2.ogg"),
]
## 三连投时反复播放的用力声增益（dB），保持在人声与雪球反馈的背景层。
const EFFORT_GAIN_DB: float = -10.0
## 出手挥声的播放增益（dB），为随后的雪球命中留出动态余量。
const RELEASE_GAIN_DB: float = -9.0
## 雪球由猎人场景准备，避免脚本解析期间再请求带脚本的场景。
@export var snowball_scene: PackedScene
## 步行等待、正在投掷和永久结束互斥。
enum ThrowState { WALK, THROW, DISABLED }
## 当前阶段只由本组件修改。
var _state: ThrowState = ThrowState.WALK
## 行为依赖通用僵尸接口，避免与物种根类相互引用。
var _source: Zombie000Base
## 配置时所属战场，换场后不能借全局指针攻击新战局。
var _game: MainGameManager
## 配置时的空间身份，重建棋盘后作废。
var _board: BoardRuntime
## 配置时的冒险阶段；普通非冒险关为 null。
var _phase: StagePhaseDefinition
## 配置时的轮数，旧轮实体不能在下一轮继续投掷。
var _round: int = 0
## 原帧播放门面只接受动作指令。
var _animator: ImportedZombieAnimator
## 原精灵提供实际出手帧和动作结束信号。
var _sprite: AnimatedSprite2D
## 本轮已经完整播放的投掷动作数量。
var _completed: int = 0
## 当前单次动作是否已经出手，长帧和重复帧信号均只生成一次。
var _released: bool = false
## 本轮开始时的攻击行，换行立即取消尚未出手的动作。
var _burst_lane: int = -1
## 剩余恢复动作秒数；不另建计时器。
var _cooldown: float = 0.0
## 仅释放本组件实际取得的移动锁。
var _owns_move_lock: bool = false
## 仅释放本组件实际取得的普通啃咬锁。
var _owns_attack_lock: bool = false

## 展示实例不启用索敌；正式实例由根类显式配置。
func _ready() -> void:
	set_physics_process(false)

## [param source] 已完成原生初始化；只绑定本实例的帧信号和战场身份。
func configure(source: Zombie000Base) -> void:
	_source = source
	_game = Global.main_game
	_board = _game.board
	_phase = AdventureSession.get_active_phase(_game.game_para)
	_round = _game.curr_game_round
	_animator = source.anim_component as ImportedZombieAnimator
	_sprite = source.get_node(^"Body/SourceSprite") as AnimatedSprite2D
	_sprite.frame_changed.connect(_on_frame_changed)
	_sprite.animation_finished.connect(_on_animation_finished)
	set_physics_process(true)

## [param delta] 为战斗秒；恢复时间消费一次合成速率，投掷时间完全由原动画推进。
func _physics_process(delta: float) -> void:
	if not _same_battle():
		finish_life()
		return
	if not _can_act() or (_state == ThrowState.THROW and _source.lane != _burst_lane):
		_cancel_burst()
		return
	if _state != ThrowState.WALK:
		return
	_cooldown = maxf(0.0, _cooldown - delta * _source.speed_factor_product())
	if _cooldown > 0.0 or _source.is_attack or _source.move_component.move_factors.get(MoveComponent.E_MoveFactor.IsCharacter, false):
		return
	var target: Plant000Base = HunterThrowTarget.nearest(_source, _game, REACH_CELLS) # 不缓存会被铲除或移走的目标。
	if target == null or target.has_ice_shell() or target.global_position.x >= _source.body.to_global(HAND_OFFSET).x - 12.0:
		return # 已冻结前排和伸手范围内目标由原啃食通路接管。
	_state = ThrowState.THROW
	_completed = 0
	_burst_lane = _source.lane
	_owns_move_lock = true
	_source.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsCharacter)
	_owns_attack_lock = _source.attack_component.is_attack_factors.get(AttackComponentBase.E_IsAttackFactors.Character, true)
	if _owns_attack_lock:
		_source.attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.Character)
	_start_throw_clip()

## 同名非循环动作也从首帧重新开始，不沿用上一次终帧或播放进度。
func _start_throw_clip() -> void:
	_released = false
	_animator.set_override(&"throw")
	_sprite.set_frame_and_progress(0, 0.0)
	_sprite.play(&"throw")
	SoundManager.play_sfx_with_pool(EFFORT_SOUNDS[randi_range(0, EFFORT_SOUNDS.size() - 1)], EFFORT_GAIN_DB)

## 只在实际出手帧以后提交一颗雪球；被控制、换行和清场时不能补发。
func _on_frame_changed() -> void:
	if _state != ThrowState.THROW or _sprite.animation != &"throw" or _released or _sprite.frame < RELEASE_FRAME:
		return
	if not _same_battle() or not _can_act() or _source.lane != _burst_lane:
		_cancel_burst()
		return
	var target: Plant000Base = HunterThrowTarget.nearest(_source, _game, REACH_CELLS) # 每次出手重查，已冻前排仍拦截本轮余球。
	var origin_world: Vector2 = _source.body.to_global(HAND_OFFSET) # 实际手心包含当前坡高，不使用拉平的检测框。
	if target == null or target.global_position.x >= origin_world.x - 12.0:
		_cancel_burst()
		return
	_released = true
	var ball: HunterSnowball = snowball_scene.instantiate() as HunterSnowball # 出手后生命周期属于战场弹体容器。
	if not ball.configure(_game, _burst_lane, origin_world, target):
		ball.free()
		_cancel_burst()
		return
	_game.bullets.add_child(ball)
	SoundManager.play_sfx_with_pool(RELEASE_SOUNDS[randi_range(0, RELEASE_SOUNDS.size() - 1)], RELEASE_GAIN_DB)

## 每轮顺序播放三次完整原动画；只在同一路且仍可行动时开始下一次。
func _on_animation_finished() -> void:
	if _state != ThrowState.THROW or _sprite.animation != &"throw":
		return
	_completed += 1
	if _completed >= BURST_SIZE or not _same_battle() or not _can_act() or _source.lane != _burst_lane:
		_cancel_burst()
	else:
		_start_throw_clip()

## 结束当前轮并恢复普通行走；不改写其他控制、啃食、死亡的禁用因素。
func _cancel_burst() -> void:
	if _state != ThrowState.THROW:
		return
	_state = ThrowState.WALK
	_cooldown = RECOVERY_SECONDS
	_release_locks()
	_animator.clear_override()

## 死亡或真正离场后永久停用，不影响已经出手并由战场持有的雪球。
func finish_life() -> void:
	_cancel_burst()
	_state = ThrowState.DISABLED
	set_physics_process(false)

## 只撤销本次投掷取得的专属因素；离树或死亡仍由原生组件保持禁用。
func _release_locks() -> void:
	if _owns_move_lock and is_instance_valid(_source):
		_owns_move_lock = false
		_source.move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsCharacter)
	if _owns_attack_lock and is_instance_valid(_source):
		_owns_attack_lock = false
		_source.attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Character)

## 检查配置时的战场、空间、阶段与轮数；不把菜单或下一场的全局引用误当原战局。
func _same_battle() -> bool:
	return _state != ThrowState.DISABLED and is_instance_valid(_source) and is_instance_valid(_game) \
		and not _source.is_death and not _source.is_queued_for_deletion() and _game == Global.main_game \
		and _game.is_ancestor_of(_source) and _game.board == _board and _game.curr_game_round == _round \
		and AdventureSession.get_active_phase(_game.game_para) == _phase

## 只在正式战斗且原生行动资格允许时投掷；魅惑后仍保留原啃食，不向植物误射。
func _can_act() -> bool:
	return _game.zombie_manager.is_game_running() and _source.attack_component.is_enabling \
		and not _source.is_hypno and _source.direction_x_root == 1 and not _source.is_changing_lane \
		and not _source.is_action_suspended() and not _source.move_component.is_forced_moving() \
		and _source.speed_factor_product() > 0.0
