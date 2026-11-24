## 妇人一阶段的登场及抽取时钟，所有植物效果在真实杖尖触地后提交。
extends Node

## 登场由传送收雾触发，普通动作从有效项中随机抽取。
enum Action { NONE, ENTRANCE, SLEEP, AURORA, REST, HOWL }
## 登场杖击收杖后启动时钟，后续抽取按基础动作秒推进。
const INTERVAL: float = 7.0
## 一阶段独立落星数。
const AURORA_COUNT: int = 5
## 一阶段每发极光加深的悲寒层数。
const AURORA_GRIEF: int = 2
## 两阶段共用冰封、落星和雪暴结算。
const SkillEffects = preload("res://scripts/character/zombie_boss/cailleach/cailleach_skill_effects.gd")

## 当前战局及行动阶段独占的技能结算源。
var _effects: SkillEffects
## 启动角色已有的杖击播放器。
var _play_staff: Callable
## 杖尖尚未触地的技能。
var _pending: Action = Action.NONE
## 普通抽取的私有随机流。
var _rng := RandomNumberGenerator.new()
## 第一次收杖后启动的循环动作计时器，随本体行动倍率变化。
var _clock: SpeedTimer

## 保存 [param game] 的正式战斗身份，[param play_staff] 启动杖击，[param caster] 提供伤害归属。
func _init(game: MainGameManager, play_staff: Callable, caster: ZB000Base = null) -> void:
	_effects = SkillEffects.new(game, caster)
	_play_staff = play_staff

## 白雾传送收尾后，从登场杖击开始。
func _ready() -> void:
	add_child(_effects)
	_rng.randomize()
	_clock = SpeedTimer.new()
	_clock.base_wait_time = INTERVAL
	_clock.timeout.connect(_draw_action)
	add_child(_clock)
	_cast(Action.ENTRANCE)

## [param rate] 为本体行动倍率，换速时保留已有抽取进度。
func set_action_rate(rate: float) -> void:
	_clock.set_speed_scale(rate)

## 在动作完成并回到待机时启动周期，之后的收杖保留下一次抽取时刻。
func finish_staff() -> void:
	if _effects.is_active() and _clock.is_stopped():
		_clock.start_scaled()

## 消费本次触地预定的技能，预览杖击没有待结算技能。
func resolve_impact() -> void:
	var action: Action = _pending # 先消费，避免死亡回调重入同一次结算。
	_pending = Action.NONE
	if not _effects.is_active():
		return
	match action:
		Action.ENTRANCE: _effects.entrance()
		Action.SLEEP: _effects.sleep()
		Action.AURORA: _effects.aurora(AURORA_COUNT, AURORA_GRIEF)
		Action.REST: _effects.rest()
		Action.HOWL: _effects.howl()

## 每轮按当前植物状态抽取可用的一阶段行动。
func _draw_action() -> void:
	if not _effects.is_active():
		return
	var choices: Array[Action] = [Action.SLEEP, Action.AURORA, Action.HOWL] # 三个普通技能始终入池。
	if _effects.can_rest():
		choices.append(Action.REST)
	_cast(choices[_rng.randi_range(0, choices.size() - 1)])

## [param action] 在原画播放器接受后进入待命中状态。
func _cast(action: Action) -> void:
	if _effects.is_active() and _pending == Action.NONE and _play_staff.call():
		_pending = action
