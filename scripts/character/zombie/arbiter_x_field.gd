## 仲裁者-X型的光场：周期性向身后六格、相邻三行的友军提供90%减伤。
## 只操作已有 HpComponent 的具名来源，绝不修改隐形、索敌层或敌方角色的注册。
extends Node
class_name ArbiterXField

## 光束每个循环开始时延迟开启，保留飞船接近和充能动画。
const FIRST_START: float = 1.0
## 每轮保护的有效动作秒数。
const ACTIVE_END: float = 4.6
## 完整光束循环时间，单位动作秒。
const CYCLE: float = 7.5
## 与现有僵尸定时能力相同量级的名单刷新间隔。
const REFRESH: float = 0.16
## 提供给目标的直接伤害减免比例。
const REDUCTION: float = 0.90
## 从原版机体光斑中提取的发光分件，保证受保护僵尸仍完全可见。
const SHIELD_GLOW: Texture2D = preload("res://assets/adventure/zombies/arbiter_x/glow_disk.png")

## 唯一施放者，不复制生命或战场登记。
var _source: Zombie000Base
## 由父节点持有的光束美术控制器，不反向引用物种脚本。
var _presentation: ArbiterXPresentation
## 读取当前战场的正式僵尸列表。
var _manager: ZombieManager
## 由本光束持有的当前目标，主战局结束立即清空。
var _affected: Dictionary[int, Zombie000Base] = {}
## 与减伤名单同寿命的独立护盾显示，不修改僵尸的贴图和索敌资格。
var _glows: Dictionary[int, Sprite2D] = {}
## 一次查询的消耗标记，避免重复目标或多次赋值。
var _seen: Dictionary[int, bool] = {}
## 当前轮光束已运行的动作秒数。
var _clock: float = 0.0
## 位置、出怪和状态变化定时复查的余数。
var _refresh_clock: float = 0.0
## 当前是否已实际写入减伤来源。
var _active: bool = false

## 避免图鉴预览和关卡退出后仍执行保护扫描。
func _ready() -> void:
	set_physics_process(false)

## [param source] 是已经进入正式战场的机体，随后从其战场读取管理器。
func activate(source: Zombie000Base) -> void:
	_source = source
	_presentation = source.get_node_or_null(^"ArbiterPresentation") as ArbiterXPresentation
	_manager = Global.main_game.zombie_manager if is_instance_valid(Global.main_game) else null
	set_physics_process(is_instance_valid(_manager))

## 每个动作帧仅推进状态，实际僵尸集合不在每帧重新枚举。
func _physics_process(delta: float) -> void:
	if not _is_valid_source():
		clear()
		set_physics_process(false)
		return
	if _source.is_action_suspended():
		_set_active(false)
		return
	_clock = fmod(_clock + delta * _source.action_rate(), CYCLE)
	var target_active: bool = _clock >= FIRST_START and _clock < ACTIVE_END
	_set_active(target_active)
	if not _active:
		return
	_refresh_clock += delta * _source.action_rate()
	if _refresh_clock >= REFRESH:
		_refresh_clock = fmod(_refresh_clock, REFRESH)
		_refresh_targets()

## 当前机体必须仍属于活跃战局；换关后不再使用已销毁全局引用。
func _is_valid_source() -> bool:
	return is_instance_valid(_source) and is_instance_valid(_manager) \
		and not _source.is_death and not _source.is_hypno and not _source.is_queued_for_deletion() \
		and is_instance_valid(_manager.main_game) and _manager.main_game.is_ancestor_of(_source) \
		and _manager.is_game_running()

## 改变效果时同步表现层，避免已结束的光束继续显示保护色。
func _set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	if is_instance_valid(_presentation):
		_presentation.set_beam_active(value)
	if value:
		_refresh_targets()
	else:
		_remove_all()

## 只给身后同阵营角色、同中心行或上下邻行的僵尸施加减伤。
func _refresh_targets() -> void:
	if not _is_valid_source() or _manager.main_game.board == null:
		_set_active(false)
		return
	var width: float = _manager.main_game.board.cell_width_at(_source.global_position, _source.lane)
	if width <= 0.0:
		_set_active(false)
		return
	_seen.clear()
	for ally: Zombie000Base in _manager.all_zombies_1d:
		if not is_instance_valid(ally) or ally == _source or ally.is_hypno \
				or ally.is_death or ally.is_queued_for_deletion():
			continue
		var behind: float = ally.global_position.x - _source.global_position.x
		if absi(ally.lane - _source.lane) > 1 or behind < 0.0 or behind > width * 6.0:
			continue
		var id: int = ally.get_instance_id()
		_seen[id] = true
		if not _affected.has(id):
			_affected[id] = ally
			ally.hp_component.damage_reduction.set_uncapped_source(get_instance_id(), REDUCTION)
			# 第一次受光束保护时才生成动画；后续扫描仅更新范围和生命周期。
			var aura: Sprite2D = Sprite2D.new()
			aura.name = "ArbiterProtectionGlow"
			aura.texture = SHIELD_GLOW
			aura.position = Vector2(0, -76)
			aura.scale = Vector2(0.95, 1.32)
			aura.modulate = Color(0.29, 0.94, 1.0, 0.29)
			aura.z_index = 2
			ally.add_child(aura)
			_glows[id] = aura
			var pulse: Tween = aura.create_tween()
			pulse.set_loops()
			pulse.tween_property(aura, ^"modulate:a", 0.13, 0.42)
			pulse.tween_property(aura, ^"modulate:a", 0.29, 0.42)
	for id: int in _affected.keys():
		if not _seen.has(id):
			_remove(id)

## 精确撤销本光场的来源，不影响其余僵尸等阶、技能的减伤。
func _remove(id: int) -> void:
	var ally: Zombie000Base = _affected.get(id)
	if is_instance_valid(ally) and is_instance_valid(ally.hp_component):
		ally.hp_component.damage_reduction.set_uncapped_source(get_instance_id(), 0.0)
	_affected.erase(id)
	var glow: Sprite2D = _glows.get(id)
	_glows.erase(id)
	if is_instance_valid(glow):
		glow.queue_free()

## 允许死亡、吹离和换关调用多次，保持幂等清理。
func _remove_all() -> void:
	for id: int in _affected.keys():
		_remove(id)
	_seen.clear()

## 清空保护来源及显示，不要求施放者还存活。
func clear() -> void:
	_remove_all()
	_active = false
	if is_instance_valid(_presentation):
		_presentation.set_beam_active(false)

## 提前解除全部来源，防止 ExitTree 后列表保留旧僵尸引用。
func _exit_tree() -> void:
	clear()
