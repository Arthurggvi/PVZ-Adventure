## 中毒、灼烧与缠怨共用的持续伤害节拍；状态独立，重复施加只续时或保留永久标记。
extends Node
class_name AdventurePeriodicDamageEffect

## 每次基础伤害之间的战斗秒数，不受目标动作速度影响。
const TICK_SECONDS: float = 0.5
## 每跳按本体最大生命计算的基础比例，装备防具不进入分母。
const MAX_HEALTH_FRACTION: float = 0.02
## 保证整秒到期仍结算最后一跳的浮点容差。
const TIME_EPSILON: float = 0.00001
## 当前承受状态的角色，死亡、魅惑与真正离树时清除。
var _target: Character000Base
## 状态所属战场，不能跨场景沿用。
var _game: MainGameManager
## 状态所属轮次，跨轮时不结算旧伤害。
var _round: int = -1
## 冒险普通与噩梦可复用轮次，需额外冻结阶段身份。
var _phase: StagePhaseDefinition
## 限时状态的剩余战斗秒数；零且没有永久标记时表示休眠节点。
var _remaining: float = 0.0
## 永久状态显式登记，不用无限大秒数冒充；死亡、魅惑、跨战局仍会结束。
var _permanent: bool = false
## 距下一跳的战斗秒数，活跃状态刷新时保留其相位。
var _until_tick: float = TICK_SECONDS
## 最新来源的真实击杀回调，不绑定即将销毁的弹体或母株。
var _on_kill: Callable = Callable()
## 当前来源对原生整数跳伤的最终倍率。
var _final_multiplier: float = 1.0
## 在伤害路由确认实际承伤者时捕获死亡位置。
var _before_death: Callable
## 某些来源需要比公共灼烧更细的战局边界；空值使用原有判断。
var _source_active: Callable

## 为 [param target] 授予 [param duration] 秒状态；[param on_kill] 接收真实死亡者。
## [param effect_name] 区分独立状态；[param effect_script] 是本类的具体子类。
## [param permanent] 为 true 时持续到目标或本战局结束，duration 可为零，重施不会增加跳伤。
## [param source] 可为最新来源设置末乘、致死观察与战局门禁；缺省沿用原版规则。
## 同种状态复用节点，跨阶段首次重施先清旧状态；失效目标或战斗返回false。
static func grant(target: Character000Base, duration: float, on_kill: Callable,
		effect_name: StringName, effect_script: GDScript, permanent: bool = false, source: Dictionary = {}) -> bool:
	if not is_instance_valid(target) or not target.can_receive_negative_effects() \
			or target.is_death or target.is_hypno \
			or target.is_queued_for_deletion() or not target.is_inside_tree() \
			or target.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not is_finite(duration) or duration < 0.0 or (not permanent and duration <= 0.0) \
			or not is_instance_valid(target.hp_component) or target.hp_component.max_hp <= 0:
		return false
	var game: MainGameManager = Global.main_game # 来源只能落在当前正式战斗的真实角色上。
	if not is_instance_valid(game) or not game.is_inside_tree() or game.is_queued_for_deletion() \
			or game.get_tree().current_scene != game or not game.is_ancestor_of(target) \
			or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false):
		return false
	var effect: AdventurePeriodicDamageEffect = target.get_node_or_null(NodePath(effect_name)) as AdventurePeriodicDamageEffect # 同一状态独享一个节拍。
	if effect == null:
		effect = effect_script.new() as AdventurePeriodicDamageEffect
		effect.name = effect_name
		effect._target = target
		target.add_child(effect)
	elif effect._game != game or effect._round != game.curr_game_round \
			or effect._phase != AdventureSession.get_active_phase(game.game_para):
		effect.clear()
	effect._game = game
	effect._round = game.curr_game_round
	effect._phase = AdventureSession.get_active_phase(game.game_para)
	effect._final_multiplier = source.get("final_multiplier", 1.0)
	effect._before_death = source.get("before_death", Callable())
	effect._source_active = source.get("source_active", Callable())
	effect.refresh(duration, on_kill, permanent)
	return true

## 节拍继承场景暂停；死亡和魅惑同步结束，子类只补充视觉钩子。
func _ready() -> void:
	set_physics_process(false)
	_target.signal_character_death.connect(clear)
	_target.signal_character_be_hypno.connect(clear)

## [param duration] 与剩余时长取较大值；[param on_kill] 接管未来跳伤归属。
## [param permanent] 只升级永久标记；不叠加伤害、不推迟下一跳，休眠后才重新起始节拍。
func refresh(duration: float, on_kill: Callable, permanent: bool = false) -> void:
	var was_inactive: bool = not is_effect_active() # 新激活才启动表现，重施保留当前节拍和视觉相位。
	if was_inactive:
		_until_tick = _tick_seconds()
	_permanent = _permanent or permanent
	_remaining = maxf(_remaining, duration)
	_on_kill = on_kill
	set_physics_process(true)
	if was_inactive:
		_on_effect_started()

## [param delta] 为随场景暂停的战斗秒数；到期帧只消费真实活跃时间。
func _physics_process(delta: float) -> void:
	if not _battle_active():
		clear()
		return
	var active_delta: float = delta if _permanent else minf(_remaining, delta) # 限时状态不消费到期后的余量。
	if not _permanent:
		_remaining -= active_delta
	_until_tick -= active_delta
	while _until_tick <= TIME_EPSILON and _battle_active():
		_until_tick += _tick_seconds()
		_deal_tick()
	if not _permanent and _remaining <= TIME_EPSILON:
		clear()

## 当前目标、场景、轮次和冒险阶段都必须保持；结束或续战界面不结算迟到伤害。
func _battle_active() -> bool:
	return is_instance_valid(_target) and not _target.is_death and not _target.is_hypno \
		and not _target.is_queued_for_deletion() and _target.is_inside_tree() \
		and _target.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
		and _battle_context_active() \
		and (_source_active.is_null() or (_source_active.is_valid() and _source_active.call()))

## 死亡回调可能同步切换阶段；此门禁不要求死者存活，供真实击杀归属最终复核。
func _battle_context_active() -> bool:
	return is_instance_valid(_target) and _target.is_inside_tree() \
		and is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.get_tree().current_scene == _game \
		and _game.is_ancestor_of(_target) and _game.curr_game_round == _round \
		and AdventureSession.get_active_phase(_game.game_para) == _phase \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 伤害沿既有格挡、减伤、防具和保护者转移路径，僵王保留自己的受击窗口。
func _deal_tick() -> void:
	var hp: HpComponent = _target.hp_component # 分母只取本体最大生命。
	if not is_instance_valid(hp) or hp.is_death:
		return
	var damage: int = roundi(float(roundi(float(hp.max_hp) * _max_health_fraction())) * _final_multiplier) # 原生整数跳伤结算完毕后才乘来源倍率。
	if damage <= 0:
		return
	var callback: Callable = _on_kill # 扣血可同步清除状态，先保存本次来源。
	var tracks_boundary: bool = not _source_active.is_null() # 明确接管边界的来源自行核对最后一击。
	var casualty: Character000Base = null # 实际死者可能是保护者而非直接受击目标。
	if _target is Zombie000Base and hp is HpComponentZombie:
		var scope: CombatHitScope = CombatHitScope.new() if _before_death.is_valid() else null # 默认沿用旧跳伤路径。
		if scope != null:
			scope.before_death = _before_death
		casualty = (hp as HpComponentZombie).apply_hit(damage, BulletRegistry.AttackMode.Norm, true, false, true, 1.0, 0, -1, null, scope)
	else:
		if _before_death.is_valid():
			_before_death.call(_target)
		_target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Norm, true, false)
		if is_instance_valid(_target) and _target.is_death:
			casualty = _target
	if is_instance_valid(casualty) and callback.is_valid() and (tracks_boundary or _battle_context_active()):
		callback.call(casualty)

## 结束状态并释放延迟来源；保留休眠节点供该角色后续复用。
func clear() -> void:
	_remaining = 0.0
	_permanent = false
	_until_tick = _tick_seconds()
	_on_kill = Callable()
	_before_death = Callable()
	_source_active = Callable()
	_final_multiplier = 1.0
	set_physics_process(false)
	_on_effect_cleared()

## 子类仅补充开始表现，不改变统一伤害周期。
func _on_effect_started() -> void:
	pass

## 子类对称回收表现，不更改其他负面状态。
func _on_effect_cleared() -> void:
	pass

## 大蒜换行的短暂离树保留时限和下一跳相位；真正离场才清除状态。
func _exit_tree() -> void:
	if is_instance_valid(_target) and _target is Zombie000Base \
			and (_target as Zombie000Base).is_changing_lane:
		return
	clear()

## 返回是否仍有时限或永久标记，供纯视觉子类判断自身生命周期。
func is_effect_active() -> bool:
	return _permanent or _remaining > 0.0

## 子类可替换伤害间隔；默认严格保留中毒、灼烧的半秒节拍。
func _tick_seconds() -> float:
	return TICK_SECONDS

## 子类可替换最大生命比例；默认两种旧状态均为每跳 2%。
func _max_health_fraction() -> float:
	return MAX_HEALTH_FRACTION
