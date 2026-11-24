## 可交互卡牌；用途决定点击路径，身份与模仿修饰统一来自卡牌引用。
extends CardBase
class_name Card

## 静态缩略图容器，复制卡牌时不创建出战角色。
@onready var character_static: Node2D = $CardBg/CharacterStatic
## 接收卡牌点击的按钮。
@onready var button: Button = $Button

## 显示用途独立于内容类型，避免图鉴被当前战斗场景接管点击。
enum CardContext {
	Catalog, ## 隐藏源目录，不处理点击。
	Selection, ## 选卡与取消选择。
	Battle, ## 交给手持管理器使用。
	Almanac, ## 打开图鉴详情。
}

## 当前实例的点击用途；入树后选择与战斗切换时同步转职标注。
var card_context: CardContext = CardContext.Catalog:
	set(value):
		if card_context == value:
			return
		card_context = value
		if is_node_ready():
			_sync_selection_promotion()
## The profile is the sole source for card UI and any spawned plant.
var _plant_spawn_profile: PlantSpawnProfile = null
## 临时派发卡的零费规则优先于永久费用及战场加减价，入树前设置。
var is_free_temporary: bool = false
var _registry_sun_cost: int = -1
var _registry_cooldown: float = 0.0
## Runtime field additions are separate from permanent star/promotion modifiers.
var _sun_surcharge: int = 0
## 持续减费按家族与来源实例独立保存；同家族取最大值，不写入永久资料。
var _battle_discount_sources: Dictionary[StringName, Dictionary] = {}
## 各减费家族最大值之和；成功用卡不消费，由实际来源退出时撤销。
var _battle_discount_total: int = 0
## Battlefield-only, per-card temporary costs; never enter persistent card data.
## 本卡下次成功种植时消费的一次性费用减免。
var _next_planting_discount: int = 0
## 本卡下次成功种植是否为减免续种；独立于普通减免，阻止续种再次发放自身奖励。
var _next_planting_followup: bool = false
## 协同按场上同种植物数量刷新，仅影响本局费用和后续冷却。
var _pea_synergy_count: int = 0
var _resonance_next_free: bool = false
var _star_badge: Control = null
const StarBadge = preload("res://scripts/adventure/ui/star_badge_view.gd")
## 选卡阶段专用的转职标注，只有实际转职的卡才创建。
const SelectionPromotion = preload("res://scripts/ui/card/card_selection_promotion.gd")
## 当前实例的转职标注，随真实卡片移入及移出出战栏。
var _selection_promotion: SelectionPromotion
## 豌豆射手的转职配件和配色。
const PeaArt = preload("res://scripts/adventure/plant_art/adventure_peashooter_promotion_art.gd")
## 向日葵转职的分层卡面资源。
const SunflowerArt = preload("res://scripts/adventure/plant_art/adventure_sunflower_promotion_art.gd")
## 闪电芦苇转职的统一配色。
const ReedArt = preload("res://scripts/adventure/plant_art/adventure_lightning_reed_promotion_art.gd")
## 电能豌豆复用闪电芦苇色表，卡面与出战特效按同一转职次数换色。
const ElectricPeaArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")

var battle_card_data: Dictionary:
	get:
		return _plant_spawn_profile.snapshot() if _plant_spawn_profile != null else {}

var plant_spawn_profile: PlantSpawnProfile:
	get:
		return _plant_spawn_profile
	set(value):
		if value != null and (not value.is_valid_profile()
				or card_reference == null
				or card_reference.card_type != ResourceCardReference.CardType.Plant
				or not value.matches_plant_type(card_reference.content_id)):
			push_error("Spawn profile must match this plant card")
			return
		_plant_spawn_profile = value
		if is_node_ready():
			_apply_profile_card_stats()
			_sync_star_badge()
			_sync_promotion_appearance()
			_sync_selection_promotion()

## 返回本卡占用的选卡名额；普通卡占1格，冻结配方可声明免占位。
func selection_slot_cost() -> int:
	return _plant_spawn_profile.selection_slot_cost() if _plant_spawn_profile != null else 1

## 返回卡面、静态缩略图和持卡预览共用的转职次数。
func promotion_tier() -> int:
	return _plant_spawn_profile.promotion_tier() if _plant_spawn_profile != null else 0

## 在 [param preview] 上应用 [param plant_type] 的 [param rank] 转卡面。其余物种直接使用原图。
static func apply_promotion_appearance(preview: Node2D, plant_type: int, rank: int) -> bool:
	match plant_type:
		PeaArt.PLANT_TYPE:
			return PeaArt.apply_to_preview(preview, rank)
		SunflowerArt.SUNFLOWER_TYPE:
			return SunflowerArt.apply_to_preview(preview, rank)
		ReedArt.PLANT_TYPE:
			return ReedArt.apply_to_preview(preview, rank)
		ElectricPeaArt.PLANT_TYPE:
			return ElectricPeaArt.apply_to_preview(preview, rank)
	return true

## 更新这张卡的独立静态图案。换回无转职快照时恢复原图。
func _sync_promotion_appearance() -> void:
	if card_reference == null or card_reference.card_type != ResourceCardReference.CardType.Plant:
		return
	if not apply_promotion_appearance(character_static, card_reference.content_id, promotion_tier()):
		push_error("无法更新植物卡的转职外观：%d" % card_reference.content_id)

## 根据本卡冻结配方显示转职刻线；进入战斗后收起。
func _sync_selection_promotion() -> void:
	var tier: int = promotion_tier() # 转职次数来自本实例，星级和物种相同也可能选择不同路线。
	if card_context != CardContext.Selection or tier == 0:
		if _selection_promotion != null:
			_selection_promotion.hide()
		return
	if _selection_promotion == null:
		_selection_promotion = SelectionPromotion.new()
		add_child(_selection_promotion)
	_selection_promotion.show()
	_selection_promotion.configure(tier)

## One UI component for inventory, research and adventure battle cards.
## The active spawn profile is the sole star-level authority.
func _sync_star_badge() -> void:
	var data: Dictionary = battle_card_data
	var rank: int = int(data.get("stars", 0))
	if rank <= 0:
		if is_instance_valid(_star_badge):
			_star_badge.queue_free()
			_star_badge = null
		return
	if not is_instance_valid(_star_badge):
		_star_badge = StarBadge.new()
		add_child(_star_badge)
	_star_badge.configure(rank)

## Resolve permanent modifiers from the registry baseline exactly once.
func _resolved_card_stats() -> Dictionary:
	if _registry_sun_cost < 0:
		return {}
	if _plant_spawn_profile == null:
		return {"sun_cost": _registry_sun_cost, "cooldown": _registry_cooldown}
	return _plant_spawn_profile.card_stats(_registry_sun_cost, _registry_cooldown)

func _apply_profile_card_stats() -> void:
	var stats: Dictionary = _resolved_card_stats()
	if stats.is_empty():
		push_error("Invalid combat card stat resolution")
		return
	_refresh_battle_sun_cost()
	_fixed_cooldown_seconds = float(stats.cooldown) if bool(stats.get("cooldown_fixed", false)) else -1.0
	var factor: float = (1.0 - 0.1 * _pea_synergy_count) * (1.0 - _battle_cooldown_reduction) # 本局常驻的后续冷却倍率。
	cool_time = _fixed_cooldown_seconds if _fixed_cooldown_seconds >= 0.0 else maxf(0.0, float(stats.cooldown) * factor)

## Dynamic board costs are added after permanent card modifiers.
func set_sun_surcharge(amount: int) -> void:
	_sun_surcharge = maxi(0, amount)
	_refresh_battle_sun_cost()

## [param family] 为独立技能家族；[param source_id] 为正来源实例 ID；[param amount] 为减免阳光数。
## 同家族只取最大来源，各家族相加；非正数撤销该来源，成功用卡不会消费此持续收益。
func set_battle_discount_source(family: StringName, source_id: int, amount: int) -> void:
	if family == &"" or source_id <= 0:
		return
	var sources: Dictionary = _battle_discount_sources.get(family, {}) # 当前家族的各个有效来源。
	var next_amount: int = maxi(0, amount) # 用正数表示减免幅度，避免负数取最大值时丢失优惠。
	if int(sources.get(source_id, 0)) == next_amount:
		return
	if next_amount > 0:
		sources[source_id] = next_amount
	else:
		sources.erase(source_id)
	if sources.is_empty():
		_battle_discount_sources.erase(family)
	else:
		_battle_discount_sources[family] = sources
	var total: int = 0 # 每个家族只贡献其中最大的减免值。
	for family_sources: Dictionary in _battle_discount_sources.values(): # 不同技能的持续减费互不覆盖。
		var highest: int = 0 # 当前技能家族的单份有效减免。
		for source_amount: int in family_sources.values(): # 同 UID 多株只维护来源，不叠加本家族金额。
			highest = maxi(highest, source_amount)
		total += highest
	if total == _battle_discount_total:
		return
	_battle_discount_total = total
	_refresh_battle_sun_cost()
	if is_node_ready() and is_instance_valid(Global.main_game) \
			and is_instance_valid(Global.main_game.card_manager):
		var slots: CardSlotBattle = Global.main_game.card_manager.card_slot_battle # 仅刷新当前槽中实际卡的可用性。
		if is_instance_valid(slots) and slots.curr_cards.has(self):
			judge_sun_enough(slots.sun_value)

## 由永久配方、动态加价、一次优惠及持续减费合成当前价格；临时免费与免费续种优先。
func _refresh_battle_sun_cost() -> void:
	var stats: Dictionary = _resolved_card_stats() # 每次从注册基础值与冻结配方重新取永久费用。
	if stats.is_empty():
		return
	sun_cost = 0 if is_free_temporary or _resonance_next_free else maxi(0,
		int(stats.sun_cost) + _sun_surcharge - _next_planting_discount - 10 * _pea_synergy_count - _battle_discount_total)

## [param count] 场上同物种存活株数；仅协同卡牌由战斗运行时调用，最多五株。
## 变动即时刷新价格；当前已经开始的冷却不追溯修改。
func set_pea_synergy_count(count: int) -> void:
	var next_count: int = clampi(count, 0, 5)
	if next_count == _pea_synergy_count:
		return
	_pea_synergy_count = next_count
	_apply_profile_card_stats()
	if is_instance_valid(Global.main_game) and is_instance_valid(Global.main_game.card_manager) \
			and is_instance_valid(Global.main_game.card_manager.card_slot_battle):
		judge_sun_enough(Global.main_game.card_manager.card_slot_battle.sun_value)

## 将花田的 [param amount] 阳光减免交给共用的下次种植费用结算。
func add_flower_field_discount(amount: int) -> void:
	add_next_planting_discount(amount)

## 累加 [param amount] 点费用减免，在成功使用本卡后清空，实际费用最低为 0。
func add_next_planting_discount(amount: int) -> void:
	if amount <= 0:
		return
	_next_planting_discount += amount
	_refresh_battle_sun_cost()

## 让本卡下次成功种植减免 [param amount] 点阳光并消费一次续种标记。[br]
## 结算费用最低为 0；非正数或已经持有续种标记时不叠加，失败放置不消费。
func arm_next_planting_discount_followup(amount: int) -> void:
	if amount <= 0 or _next_planting_followup:
		return
	_next_planting_followup = true
	add_next_planting_discount(amount)

func arm_resonance_next_free() -> void:
	_resonance_next_free = true
	_refresh_battle_sun_cost()

## 卡槽按当前费用完成成功种植扣费后调用一次，并清空本卡的一次性费用收益。[br]
## 返回本次是否消费免费或减免续种；普通花田等减免不阻止发放新的续种奖励。
func consume_adventure_cost_effects() -> bool:
	var consumed_followup: bool = _resonance_next_free or _next_planting_followup # 本次已使用的续种奖励。
	_resonance_next_free = false
	_next_planting_followup = false
	_next_planting_discount = 0
	_refresh_battle_sun_cost()
	return consumed_followup
## 是否处于冷却中。
var _is_cooling: bool = false
## 当前费用是否已被卡槽判定为足够。
var is_sun_enough: bool = true
## 由普通出战卡槽设置，开启时战斗中的本卡始终满足阳光费用。
var cheat_ignore_sun_cost := false
## 剩余冷却时间，单位为游戏秒。
var _cool_timer: float = 0.0
## 冒险事件倍率只影响新开始的冷却；固定时长技能不再乘此倍率。
var adventure_cooldown_multiplier := 1.0
## 同类共享冷却缩短按有效受益株的实例 ID 保存，允许各株独立退出。
var _battle_cooldown_sources: Dictionary[int, float] = {}
## 共生提供的最大冷却缩短比例，仅参与新开始的普通冷却。
var _battle_cooldown_reduction: float = 0.0
## 配方声明的最终固定冷却秒数；负数表示使用普通倍率结算。
var _fixed_cooldown_seconds: float = -1.0
## 仅在同步成功使用通知期间存在的额外冷却，避免残留到下一次使用。
var _placement_cooldown_bonus: float = 0.0
## 防止同次使用通知的监听器重入，再次扣费和开始冷却。
var _placement_commit_in_progress: bool = false

## 登记 [param source_id] 提供的 [param reduction]。同类只取最大值，零撤销，进行中的冷却保持原进度。
func set_battle_cooldown_reduction_source(source_id: int, reduction: float) -> void:
	if source_id <= 0 or not is_finite(reduction):
		return
	var next_amount: float = clampf(reduction, 0.0, 1.0) # 以正的比例表示缩短幅度。
	if _battle_cooldown_sources.get(source_id, 0.0) == next_amount:
		return
	if next_amount > 0.0:
		_battle_cooldown_sources[source_id] = next_amount
	else:
		_battle_cooldown_sources.erase(source_id)
	var highest: float = 0.0 # 多株共生受益者不能叠加同一个冷却词条。
	for amount: float in _battle_cooldown_sources.values(): # 其他仍在场的来源维持自己贡献的比例。
		highest = maxf(highest, amount)
	if highest != _battle_cooldown_reduction:
		_battle_cooldown_reduction = highest
		_apply_profile_card_stats()

## 结算一次成功放置，[param extra_cooldown] 由实际施效结果提供，单位为秒。
## 沿用原有单参数信号；无冷却模式跳过计时后，附加值也会立即清空。
func complete_placement(extra_cooldown: float = 0.0) -> void:
	if _placement_commit_in_progress:
		return
	_placement_commit_in_progress = true
	_placement_cooldown_bonus = maxf(0.0, extra_cooldown)
	signal_card_use_end.emit(self)
	_placement_cooldown_bonus = 0.0
	_placement_commit_in_progress = false

func adventure_adjust_remaining_cooldown(seconds: float) -> void:
	if not _is_cooling:
		return
	_cool_timer = maxf(0.0, _cool_timer + seconds)
	_cool_mask.value = _cool_timer
	if _cool_timer <= 0:
		_is_cooling = false
		judge_card_ready()

## 为当前卡牌追加 [param seconds] 秒冷却；已就绪时从零开始。基础冷却和未来的用卡倍率不变。
func add_cooldown_penalty(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0.0 or card_context != CardContext.Battle:
		return
	var remaining: float = maxf(0.0, _cool_timer) if _is_cooling else 0.0 # 已就绪时不使用上次计时的余量。
	_cool_timer = remaining + seconds
	_cool_mask.max_value = maxf(_cool_mask.max_value, _cool_timer) if _is_cooling else _cool_timer
	_cool_mask.value = _cool_timer
	_is_cooling = true
	card_not_can_click()

## 将当前剩余冷却乘以 [param factor]；负数按 0 处理，0 立即结束冷却。[br]
## 已就绪卡保持原状，不改基础冷却、遮罩最大值或后续冷却的事件倍率。
## 有在途冷却并处理时返回 true。
func adventure_multiply_remaining_cooldown(factor: float) -> bool:
	if not _is_cooling:
		return false
	adventure_adjust_remaining_cooldown(_cool_timer * (maxf(0.0, factor) - 1.0))
	return true

## 当前是否可以使用，由冷却、费用和种植条件共同决定。
var is_can_click: bool = true
## 临时卡消失前的闪烁补间；停止时释放引用。
var tween_blink: Tween
## 是否为关卡锁定的预选卡，选卡阶段不可取消。
var is_choosed_pre_card: bool = false
## 对应的候选占位容器，选中后用于恢复备选显示。
var card_candidate_container: CardCandidateContainer
## 模仿卡共用的着色材质，每个展示实例使用独立副本。
const IMITATER = preload("res://shader_material/imitater.tres")
## 选卡或图鉴点击通知，始终携带实际被点击的卡牌。
signal signal_card_click(card: Card)
## 内容成功放置后的结算通知，由所属卡槽或临时卡管理器消费一次。
@warning_ignore("unused_signal")
signal signal_card_use_end(card: Card)


## 初始化参数与模仿外观；僵王的选卡和战斗实例显示费用，目录及图鉴实例只保留外观。
func _ready() -> void:
	super()
	_registry_sun_cost = sun_cost
	_registry_cooldown = cool_time
	_apply_profile_card_stats()
	_cool_mask.value = 0
	if card_reference == null or not card_reference.is_valid():
		is_can_click = false
		return
	_sync_star_badge()
	_sync_promotion_appearance()
	_sync_selection_promotion()
	if card_reference.card_type == ResourceCardReference.CardType.ZombieBoss:
		# 源模板隐藏了费用，复制实例入树时必须按用途显式恢复可见性。
		cost.visible = card_context == CardContext.Selection or card_context == CardContext.Battle
		_cool_mask.hide()
	if card_reference.is_imitater:
		character_static.material = IMITATER.duplicate()
		# 静态图像的子节点继承模仿材质。
		for child: Node in character_static.get_children():
			if child is Node2D:
				GlobalUtils.node_use_parent_material(child as Node2D)


## 修改实例冷却时长；[param new_cool_time] 单位为秒，0 用于无冷却模式。
func card_change_cool_time(new_cool_time: float) -> void:
	cool_time = new_cool_time
	_cool_mask.value = 0


## 设置 [param new_cool_time] 秒冷却并立即开始计时。
func set_card_cool_time_start_cool(new_cool_time: float) -> void:
	cool_time = new_cool_time
	card_cool()


## 禁用当前卡牌但不运行冷却，用于模式限制和使用次数耗尽。
func set_card_disable() -> void:
	cool_time = 1
	_cool_mask.value = cool_time
	_is_cooling = false
	_cool_mask.visible = true
	is_can_click = false


## 传送带卡牌免费使用；在入树并完成角色参数初始化后调用。
func card_init_conveyor_belt() -> void:
	_cool_mask.value = 0
	sun_cost = 0


## 按 [param delta] 游戏秒推进已有冷却，树暂停时不执行。
func _process(delta: float) -> void:
	if _is_cooling:
		_cool_timer -= delta
		_cool_mask.value = _cool_timer
		if _cool_timer <= 0:
			_is_cooling = false
			judge_card_ready()


## 根据 [param curr_sun_value] 和本卡的无限阳光状态更新费用可用性，再检查其余使用条件。
func judge_sun_enough(curr_sun_value: int) -> void:
	is_sun_enough = curr_sun_value >= sun_cost or (cheat_ignore_sun_cost and card_context == CardContext.Battle)
	judge_card_ready()


## 结合类别、费用、冷却、僵王召唤资格和紫卡前置条件更新可用状态；非出战卡牌不能就绪。
func judge_card_ready() -> void:
	if not AllCards.is_battle_card(card_reference):
		is_can_click = false
		return
	if not is_sun_enough or _is_cooling:
		card_not_can_click()
		return
	if card_context == CardContext.Battle and card_reference.card_type == ResourceCardReference.CardType.ZombieBoss:
		# 选卡阶段不检查战斗状态；正式使用时以当前场景的实际召唤条件为准。
		# 通用内容编号在召唤接口处显式解释为僵王枚举。
		if not is_instance_valid(Global.main_game) or not is_instance_valid(Global.main_game.zombie_manager) \
			or not Global.main_game.zombie_manager.can_summon_boss(card_reference.content_id as CharacterRegistry.ZombieBossType):
			card_not_can_click()
			return
	if is_purple_card:
		# 紫卡只可能来自植物，通用内容编号在调用种植条件时显式转换为植物枚举。
		var plant_type: CharacterRegistry.PlantType = card_reference.content_id as CharacterRegistry.PlantType
		if not plant_condition.judge_purple_card_can_plant(Global.main_game.plant_cell_manager.all_plant_cells, plant_type):
			card_not_can_click()
			return
	card_ready()


## 清空冷却状态；可用性由卡槽接下来的费用刷新决定。
func set_card_cool_end() -> void:
	_cool_timer = 0
	_cool_mask.value = 0
	_is_cooling = false


## 标记卡牌就绪并隐藏不可用遮罩。
func card_ready() -> void:
	_cool_mask.hide()
	is_can_click = true


## 标记卡牌不可用并显示遮罩。
func card_not_can_click() -> void:
	_cool_mask.show()
	is_can_click = false


## 开始当前实例的冷却，在成功使用后的结算处调用。
func card_cool() -> void:
	_is_cooling = true
	_cool_mask.show()
	var duration: float = _fixed_cooldown_seconds if _fixed_cooldown_seconds >= 0.0 else cool_time * adventure_cooldown_multiplier # 固定技能先确定最终基础时长。
	_cool_timer = maxf(0.0, duration + _placement_cooldown_bonus)
	_cool_mask.max_value = maxf(0.001, _cool_timer)
	_cool_mask.value = _cool_timer
	is_can_click = false


## 按显式用途分发点击；战斗入口额外拒绝不支持出战的内容。
func _on_button_pressed() -> void:
	match card_context:
		CardContext.Almanac:
			signal_card_click.emit(self)
		CardContext.Selection:
			if AllCards.is_battle_card(card_reference):
				signal_card_click.emit(self)
		CardContext.Battle:
			if not is_instance_valid(Global.main_game) or Global.main_game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
				return
			# 显式禁用的卡片不能由点击时的就绪重算重新启用。
			if not is_can_click:
				SoundManager.play_other_SFX("buzzer")
				return
			if card_reference != null and card_reference.card_type == ResourceCardReference.CardType.ZombieBoss:
				# 点击前重验场景资格，不依赖上次阳光或冷却刷新留下的可用状态。
				judge_card_ready()
			if is_can_click and AllCards.is_battle_card(card_reference):
				EventBus.push_event("main_game_click_card", [self])
			else:
				SoundManager.play_other_SFX("buzzer")


## 启动循环闪烁；重复调用先停止旧补间。
func card_blink_start() -> void:
	if tween_blink and tween_blink.is_valid():
		tween_blink.kill()
	tween_blink = create_tween()
	tween_blink.set_loops()
	tween_blink.tween_property(card_bg, "modulate:a", 0.5, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween_blink.tween_property(card_bg, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 暂停当前闪烁补间。
func card_blink_pause() -> void:
	if tween_blink and tween_blink.is_running():
		tween_blink.pause()


## 恢复已暂停的闪烁补间。
func card_blink_resume() -> void:
	if tween_blink and not tween_blink.is_running():
		tween_blink.play()


## 停止并释放闪烁补间引用。
func card_blink_completely_stop() -> void:
	if tween_blink and tween_blink.is_valid():
		tween_blink.kill()
		tween_blink = null


## 恢复卡牌接收鼠标输入。
func mouse_filter_start() -> void:
	button.mouse_filter = Control.MOUSE_FILTER_PASS


## 停止卡牌接收鼠标输入，用于手持临时卡期间屏蔽其他临时卡。
func mouse_filter_stop() -> void:
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
