## 阳光菇的幼年、成年及基因突破成长流程；只有自然成长派发转职事件。
extends Plant000Base
class_name Plant010SunShroom

## 基因突破后每轮额外生产的阳光总值，独立于单份阳光倍率。
const GENE_BREAKTHROUGH_SUN: int = 75

## 本株产阳光组件，接收各成长阶段的单份基础价值及额外产值。
@onready var create_sun_component: CreateSunComponent = $CreateSunComponent
## 成长使用独立动作计时器，仍响应角色速度和战场暂停。
@onready var grow_timer: SpeedTimer = $GrowTimer

## 正常角色速度下的成长秒数；冻结转职可在入树前缩短。
@export var time_grow: float = 100.0
## 幼年每份阳光价值；出生修饰后持续保留，不在就绪时恢复原值。
@export var mini_sun_value: int = 15
## 成熟每份阳光价值；出生修饰后持续保留，不在成长时恢复原值。
@export var norm_sun_value: int = 25

## 冻结的基因突破转职允许成年后再走一轮成长计时。
var gene_breakthrough_enabled: bool = false
## 本株已完成第三个阶段；读档和复生可恢复，不能用计时再次叠加。
var _has_broken_through: bool = false
## 复生恢复按当次复生倍率计算上限，普通读档使用保存的最终上限。
var _reviving: bool = false

@export_group("动画状态")
## 本株是否已经成熟；读档恢复此状态不补发成熟技能。
@export var is_grow: bool = false

## 本株每次自然成长后发出；成年与突破均在更新生命和产值之后通知。
signal signal_matured()

## 初始化正常出战本株，从当前阶段继续处理成长计时与产值。
func ready_norm() -> void:
	super()
	update_grow_speed(GlobalUtils.get_dic_product(influence_speed_factors))
	_update_growth_state()
	if is_zombie_mode:
		create_sun_component.disable_component(ComponentNormBase.E_IsEnableFactor.GameMode)

## 原有角色速度分别同步成长与生产，独立缩短成长时长不加速产阳光。
func ready_norm_signal_connect() -> void:
	super()
	signal_update_speed.connect(update_grow_speed)
	signal_update_speed.connect(create_sun_component.owner_update_speed)

## 每次有效超时只推进一个阶段；未选基因突破的成年植株不再成长。
func _on_grow_timer_timeout() -> void:
	if is_death or is_queued_for_deletion() \
			or character_init_type != E_CharacterInitType.IsNorm:
		return
	if is_grow:
		if not gene_breakthrough_enabled or _has_broken_through:
			return
		_has_broken_through = true
		# 当前值与上限同步翻倍，保留突破前的受伤比例。
		hp_component.max_hp *= 2
		hp_component.curr_hp *= 2
	else:
		is_grow = true
	_update_growth_state()
	signal_matured.emit()

## 同步当前阶段的计时和生产；任何恢复入口均可调用且不补发成长事件。
func _update_growth_state() -> void:
	if not is_grow or (gene_breakthrough_enabled and not _has_broken_through):
		grow_timer.start_scaled(time_grow)
	else:
		grow_timer.stop()
	create_sun_component.change_sun_value(norm_sun_value if is_grow else mini_sun_value)
	create_sun_component.extra_sun_value_per_production = GENE_BREAKTHROUGH_SUN if _has_broken_through else 0

## [param speed_factor] 为角色速度乘积；停止或尚未开始时也保存倍率，由计时器保留进度与零速。
func update_grow_speed(speed_factor: float) -> void:
	grow_timer.set_speed_scale(production_speed_product(speed_factor))

## [param _attack_zombie] 是本次啃食者；仅我是僵尸模式沿用原版受击产阳光。
func _be_zombie_eat_once_special(_attack_zombie: Zombie000Base) -> void:
	if is_zombie_mode:
		create_sun_component._on_be_eat_once()

## 死亡前结清我是僵尸模式原版产出；转职储蓄由统一角色死亡事件结算。
func character_death() -> void:
	if is_zombie_mode:
		create_sun_component._on_character_death()
	super()

## 返回包含成长阶段的植物存档；完成突破时一并保存普通读档所需的最终生命上限。
func gat_save_game_data_plant() -> Dictionary:
	var save_game_data_plant: Dictionary = super() # 基础生命、睡眠及物种字段。
	save_game_data_plant["is_grow"] = is_grow
	if _has_broken_through:
		save_game_data_plant["breakthrough_max_hp"] = hp_component.max_hp
	return save_game_data_plant

## 从 [param origin] 区分复生和其他放置；仅保存本次离树准备状态。
func prepare_placement_action(origin: PlantCell.PlacementOrigin = PlantCell.PlacementOrigin.Player) -> bool:
	_reviving = origin == PlantCell.PlacementOrigin.Revival
	return super(origin)

## 恢复已校验的 [param save_game_data_plant]，保留突破产值与生命，且不补发成长事件。
func load_game_data_plant(save_game_data_plant: Dictionary) -> void:
	is_grow = save_game_data_plant.get("is_grow", false)
	_has_broken_through = save_game_data_plant.has("breakthrough_max_hp")
	var restored: Dictionary = save_game_data_plant # 普通读档保留存档的当前生命值。
	if _has_broken_through:
		if _reviving:
			# 复生事务已将当前生命按本次倍率重算为满值，恢复突破时再将它与上限同时翻倍。
			restored = save_game_data_plant.duplicate()
			restored["curr_hp"] = int(restored["curr_hp"]) * 2
			hp_component.max_hp = int(restored["curr_hp"])
		else:
			hp_component.max_hp = int(restored["breakthrough_max_hp"])
	super(restored)
	_update_growth_state()

## 校验 [param state] 的可选成长字段；旧档缺字段时仍按原先的成长规则恢复。
func accepts_save_state(state: Dictionary) -> bool:
	if not super(state) or (state.has("is_grow") and not state["is_grow"] is bool):
		return false
	if not state.has("breakthrough_max_hp"):
		return true
	var maximum: Variant = state["breakthrough_max_hp"] # 只有已成年植株才可能保存突破后的上限。
	return state.get("is_grow", false) and maximum is int and int(maximum) > 0 \
			and (_reviving or int(state["curr_hp"]) <= int(maximum))
