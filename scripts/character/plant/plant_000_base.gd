extends Character000Base
class_name Plant000Base

@onready var sleep_component: SleepComponent = %SleepComponent
@onready var blink_component: BlinkComponent = %BlinkComponent
## 花园组件
@onready var garden_component: GardenComponent = %GardenComponent

#region 植物类基础属性

## Legacy scene export; runtime identity is set from CharacterRegistry by
## PlantSceneFactory, including for scenes inheriting another plant's artwork.
@export var plant_type:CharacterRegistry.PlantType
## 植物初始化受击状态（从1[is_norm] 开始）僵尸攻击检测时判断是否可以攻击
@export var init_be_attack_status :E_BeAttackStatusPlant = E_BeAttackStatusPlant.IsNorm
## 当前是否遵循日眠；转职可独立关闭此行为，不改变原始蘑菇身份。
@export var is_sleep_in_day:bool = false
## 初始化时冻结场景的原生日眠属性；永久或转职唤醒后仍用于蘑菇光环判定。
var native_day_sleep: bool = false
## 植物是否可以挂载梯子(Nrom位置植物使用)
@export var is_can_ladder := false
## 植物当前状态，僵尸攻击检测时判断是否可以攻击
var curr_be_attack_status:E_BeAttackStatusPlant = E_BeAttackStatusPlant.IsNorm
## 行和列
var row_col:Vector2i = Vector2i(-1, -1)
## 植物所在格子
var plant_cell:PlantCell
## Immutable source recipe for transformations into another plant instance.
var plant_spawn_profile: PlantSpawnProfile = null
## Transient attack scaling from the frozen adventure card; never saved to the card.
var battle_damage_multiplier: float = 1.0
## 当前实例的攻击词条提供者；由唯一运行时管理，空值保持原生攻击。
var battle_attack_context_provider: Callable
## 死亡信号清空动态来源前冻结的最后一份攻击上下文，仅供同步亡语使用。
var _death_attack_context: PlantAttackContext
var _battle_card_damage_multiplier: float = 1.0
var _battle_aura_damage_bonus: float = 0.0
## 各技能光环独立来源；允许向日葵圣战与豌豆协同叠加且各自撤销。
var _battle_aura_damage_sources: Dictionary[StringName, float] = {}
## 冒险转职赋予的负面效果免疫；仅在冻结出战卡生成时写入，不进入角色原版数据。
var battle_negative_effect_immune: bool = false
var spawn_attributes_applied: bool = false
## 同一次卡片点击共享的提交身份；自动生成或独立放置可以为空。
var placement_use_context: PlantPlacementUseContext
## 原生咖啡伸缩动画；重复唤醒不会重启或叠加同一株身体的动画。
var _coffee_wake_tween: Tween
## 当前伸缩所属战场的弱引用；旧阶段动画不能挡住新阶段的合法咖啡。
var _coffee_wake_game_ref: WeakRef
## 当前伸缩所属空间，平台移动不改变此身份。
var _coffee_wake_board: BoardRuntime
## 当前伸缩所属冒险阶段；普通轮间切换继续使用同一身份。
var _coffee_wake_phase: StagePhaseDefinition

## 标准放置事务的纯查询准备入口；[param _origin] 区分玩家使用、预置和转化。
## 普通植物无需额外作用计划；工具可保留非战斗阶段的原生配置语义。
func prepare_placement_action(_origin: PlantCell.PlacementOrigin = PlantCell.PlacementOrigin.Player) -> bool:
	return true

## 占位、承托与保存状态完成后执行；默认植物没有额外同步作用。
func commit_placement_action() -> void:
	pass

## 返回本次已提交作用的额外卡片冷却；未成功产生额外效果时为零。
func placement_cooldown_extension() -> float:
	return 0.0

func set_battle_card_damage_multiplier(value: float) -> void:
	_battle_card_damage_multiplier = maxf(0.0, value)
	_refresh_battle_damage_multiplier()

## 保留原向日葵圣战调用入口；内部转为具名来源，避免覆盖其他光环。
func set_battle_aura_damage_bonus(value: float) -> void:
	set_battle_aura_damage_source(&"sunflower_holy_war", value)

## [param source] 光环来源稳定 ID；[param value] 相对基础伤害加成，0 清除来源。
func set_battle_aura_damage_source(source: StringName, value: float) -> void:
	if value <= 0.0:
		_battle_aura_damage_sources.erase(source)
	else:
		_battle_aura_damage_sources[source] = value
	_battle_aura_damage_bonus = 0.0
	for amount: float in _battle_aura_damage_sources.values():
		_battle_aura_damage_bonus += amount
	_refresh_battle_damage_multiplier()

func _refresh_battle_damage_multiplier() -> void:
	battle_damage_multiplier = _battle_card_damage_multiplier * (1.0 + _battle_aura_damage_bonus)

## Single explicit attack contract for plant-owned direct damage.
## No card snapshot in vanilla means a factor of 1.0.
func battle_damage(source_damage: int) -> int:
	return hp_component.outgoing_damage(maxi(0, roundi(float(source_damage) * battle_damage_multiplier)))

## 存活时捕获本次攻击来源；死亡后只返回死亡开始前冻结的快照，不能重新查询共享词条。
func capture_attack_context() -> PlantAttackContext:
	if is_death:
		return _death_attack_context
	if not battle_attack_context_provider.is_valid():
		return null
	return battle_attack_context_provider.call() as PlantAttackContext

## The species represented by this spawn, independent of rendering/transform.
func spawn_species_id() -> int:
	return int(plant_type)
## 实际放置事务提交的完整地块声明，死亡记录不凭当前画面反推多格范围。
var battle_placement_cells: Array[PlantCell] = []
## 同步换格造成的离树仅用于重挂原节点；组件可据此保留计时和登记。
var is_being_relocated := false
## 铲除、升级替换与场景清理显式关闭尸体记录；正常消耗与战斗死亡保持开启。
var death_recording_enabled: bool = true
## 复生后的永久最大生命比例，存档单独保存，不修改来源卡牌配方。
var revival_health_scale: float = 1.0
## 植物死亡后是否直接删除
var is_death_free:= true
## 是否为模仿者材质
var is_imitater_material:=false
## 是否正在预铲；防止重复进入时再次增加层级。
var _is_shovel_look_active: bool = false
## 本次预铲实际增加的层级，取值为 0 或 10；结束时按记录撤销。
var _shovel_z_offset: int = 0
#endregion

#region 植物动画
@export_group("动画状态")
@export var is_sleeping:=false
## 是否在花园水族馆
@export var is_garden_aquarium := false

## 植物梯子状态变化信号
@warning_ignore("unused_signal")
signal signal_ladder_update

#region 角色枚举
## 检测攻击时，根据状态判断是否可以攻击
enum E_BeAttackStatusPlant{
	IsNorm = 1,		## 正常
	IsFloat = 2,	## 悬浮
	IsDown = 4, 	## 地刺
	IsShort = 8,	## 低矮

}
#endregion


#region 花园植物
## 花园初始化数据
var garden_date_init:Dictionary
#endregion


#region 初始化相关
func _ready() -> void:
	super()
	if character_init_type == E_CharacterInitType.IsNorm:
		Global.record_almanac_encounter("plant", int(plant_type))
	if is_imitater_material:
		plant_imitater_update_body()

	if plant_type == 0:
		push_error(name, "植物类型未赋值")

## 植物初始化属性
enum E_PInitAttr{
	CharacterInitType,	## 角色初始化类型（正常、展示、花园）
	PlantCell,			## 植物格子
	IsImitaterMaterial,	## 是否为模仿者材质
	GardenDate,			## 花园数据
	IsZombieMode,			## 我是僵尸模式
}
## [param plant_init_para] 提供初始化类型、格子及模式；在入树和出战修饰前调用。
## 同时冻结场景原生日眠属性，使后续常醒转职不改变蘑菇身份。
func init_plant(plant_init_para:Dictionary):
	# init_plant 先于冻结出战修饰；保留原始身份，避免一转免睡后被光环遗漏。
	native_day_sleep = is_sleep_in_day
	self.character_init_type = plant_init_para[E_PInitAttr.CharacterInitType]
	self.is_imitater_material = plant_init_para.get(E_PInitAttr.IsImitaterMaterial, false)
	self.is_zombie_mode = plant_init_para.get(E_PInitAttr.IsZombieMode, false)
	match character_init_type:
		E_CharacterInitType.IsNorm:
			self.plant_cell = plant_init_para[E_PInitAttr.PlantCell]
			self.row_col = plant_cell.row_col
			self.lane = plant_cell.row_col.x
		E_CharacterInitType.IsShow:
			### 南瓜背景-1,这里所有植物+1
			#z_index += 1
			pass
		E_CharacterInitType.IsGarden:
			### 南瓜背景-1,这里所有植物+1
			#z_index += 1
			garden_date_init = plant_init_para[E_PInitAttr.GardenDate]
			## 是否为水族馆背景，动画变化
			is_garden_aquarium = garden_date_init["curr_garden_bg_type"] == GardenManager.E_GardenBgType.Aquarium

## 初始化正常出战角色信号连接
func ready_norm_signal_connect():
	super()
	## 发射子弹攻击组件影响植物眨眼
	var attack_component :AttackComponentBulletBase = get_node_or_null(^"AttackComponent")
	if attack_component:
		attack_component.signal_change_is_attack.connect(
			## 可以攻击时禁用眨眼
			func(value):blink_component.change_is_enabling(not value, ComponentNormBase.E_IsEnableFactor.Attack)
		)

	## 植物睡眠组件
	sleep_component.signal_is_sleep.connect(update_is_sleeping.bind(true))
	sleep_component.signal_not_is_sleep.connect(update_is_sleeping.bind(false))

	## 植物睡眠影响的组件
	for sleep_influence_component in sleep_component.sleep_influence_components:
		sleep_component.signal_is_sleep.connect(sleep_influence_component.disable_component.bind(ComponentNormBase.E_IsEnableFactor.Sleep))
		sleep_component.signal_not_is_sleep.connect(sleep_influence_component.enable_component.bind(ComponentNormBase.E_IsEnableFactor.Sleep))

## 初始化正常出战角色
func ready_norm():
	super()
	garden_component.queue_free()
	curr_be_attack_status = init_be_attack_status
	## 如果白天睡觉
	if is_sleep_in_day:
		sleep_component.judge_is_sleeping()

	GlobalUtils.update_plant_cell_slope_y_array(plant_cell, node2d_detect_in_slope)

## 默认允许换格；正在执行依赖原格位置的动作时由具体植物拒绝。
func can_relocate() -> bool:
	return true

## 更新本株到 [param destination] 的格子和攻击行，按高度差修正检测节点，保留战斗状态。
func update_battle_cell(destination: PlantCell) -> void:
	var height_delta: float = plant_cell.get_ground_height() - destination.get_ground_height() # 撤回旧坡面偏移后再应用新高度。
	plant_cell = destination
	row_col = destination.row_col
	lane = row_col.x
	if not is_zero_approx(height_delta):
		for detector: Node2D in node2d_detect_in_slope: # 只移动仍存活的检测节点，身体随父容器换位。
			if is_instance_valid(detector):
				detector.position.y += height_delta

## 初始化展示角色
func ready_show():
	super()
	garden_component.queue_free()



## 初始化花园角色
func ready_garden():
	super()
	garden_component.init_garden_component(garden_date_init)
	sleep_component.signal_is_sleep.connect(garden_component.disable_component.bind(ComponentNormBase.E_IsEnableFactor.Sleep))
	sleep_component.signal_not_is_sleep.connect(garden_component.enable_component.bind(ComponentNormBase.E_IsEnableFactor.Sleep))
	## 如果白天睡觉
	if is_sleep_in_day:
		sleep_component.judge_is_sleeping()
	shadow.visible = false

## 植物模仿者更新body颜色
func plant_imitater_update_body():
	body.imitater_update_material()

#endregion

#region 植物受伤、死亡
## 被蹦极僵尸偷走
func be_bungi()->Node2D:
	var body_copy:Node2D = body.duplicate()
	plant_cell.add_child(body_copy)
	body_copy.global_position = body.global_position
	## 死亡直接消失,复制一个body给蹦极
	character_death_disappear()
	return body_copy

## 被僵尸啃食
## attack_value:伤害
## attack_zombie:攻击的僵尸
func be_zombie_eat(attack_value:int, _attack_zombie:Zombie000Base):
	hp_component.Hp_loss(attack_value,BulletRegistry.AttackMode.Penetration, true, false)

## 被僵尸啃食一次发光
func be_zombie_eat_once(attack_zombie:Zombie000Base):
	body.body_light()
	_be_zombie_eat_once_special(attack_zombie)


## 被僵尸啃食一次特殊效果,魅惑\大蒜\我是僵尸生产阳光
func _be_zombie_eat_once_special(_attack_zombie:Zombie000Base):
	pass

## 植物首次死亡前冻结攻击来源；死亡信号清理光环后，亡语仍使用死亡瞬间的词条。
func character_death():
	if is_death:
		return
	_death_attack_context = capture_attack_context()
	# 在占用释放、光环撤销和亡语之前冻结永久状态；记录不会保存死亡实例本身。
	PlantRevivalArchive.record_death(self)
	## 发射死亡信号并执行原生亡语，此时不再依赖动态提供者。
	super()
	if is_instance_valid(hurt_box_component):
		## 要先删除碰撞器，否则僵尸攻击检测组件有问题
		hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	if is_death_free:
		queue_free()

## 死亡不消失
func character_death_not_disappear():
	is_death_free = false
	hp_component.Hp_loss_death()

#endregion

#region 与铲子\种植交互
## 开始预铲，提升显示层级并高亮；重复调用不再叠加。
func be_shovel_look() -> void:
	if _is_shovel_look_active:
		return

	_is_shovel_look_active = true
	_shovel_z_offset = 10 if Global.config_service.plant_be_shovel_front else 0
	z_index += _shovel_z_offset
	body.set_other_color(
		BodyCharacter.E_ChangeColors.BeShovelLookColor,
		Color(2, 2, 2)
	)

## 结束预铲，仅撤销本次实际增加的层级；重复调用无副作用。
func be_shovel_look_end() -> void:
	if not _is_shovel_look_active:
		return

	_is_shovel_look_active = false
	z_index -= _shovel_z_offset
	_shovel_z_offset = 0
	body.set_other_color(
		BodyCharacter.E_ChangeColors.BeShovelLookColor,
		Color(1, 1, 1)
	)

## 被铲子铲除,禁止亡语
func be_shovel_kill():
	is_can_death_language = false
	death_recording_enabled = false
	hp_component.Hp_loss_death()

## 手持紫卡植物可以种植在该植物上
func preplant_purple_body_light_and_dark():
	if Global.config_service.plant_be_shovel_front:
		z_index += 10
	body.body_light_and_dark()

## 手持紫卡植物可以种植在该植物上结束
func preplant_purple_body_light_and_dark_end():
	if Global.config_service.plant_be_shovel_front:
		z_index -= 10
	body.body_light_and_dark_end()

#endregion
## 咖啡豆沿用一点五秒的原生伸缩动画，完成后授予独立的永久唤醒。
## 动画期间即使已被月光唤醒，也不会丢失咖啡豆的永久效果。
func coffee_bean_awake_up():
	if is_death or is_queued_for_deletion() or not is_inside_tree() \
			or not is_instance_valid(sleep_component) or sleep_component.is_permanently_awake \
			or not is_instance_valid(plant_cell):
		return
	var game: MainGameManager = Global.main_game # 最终伸缩回调也必须保留本次战场身份。
	if not is_instance_valid(game):
		return
	var phase: StagePhaseDefinition = AdventureSession.get_active_phase(game.game_para) # 普通轮次不会改变阶段身份。
	if not CoffeeBeanUsePlan.wakeup_context_current(game, plant_cell.board, phase):
		return
	if _coffee_wake_tween != null and _coffee_wake_tween.is_valid():
		if _coffee_wake_game_ref != null and CoffeeBeanUsePlan.wakeup_context_current(
				_coffee_wake_game_ref.get_ref() as MainGameManager, _coffee_wake_board, _coffee_wake_phase):
			return
		_coffee_wake_tween.kill()
	_coffee_wake_game_ref = weakref(game)
	_coffee_wake_board = plant_cell.board
	_coffee_wake_phase = phase
	_coffee_wake_tween = create_tween()
	_coffee_wake_tween.tween_property(body, ^"scale:y", 0.8, 0.5)
	_coffee_wake_tween.tween_property(body, ^"scale:y", 1.2, 0.5)
	_coffee_wake_tween.tween_property(body, ^"scale:y", 1, 0.5)
	_coffee_wake_tween.tween_callback(_finish_coffee_wakeup.bind(
		_coffee_wake_game_ref, _coffee_wake_board, _coffee_wake_phase))

## [param game_ref]、[param board]、[param phase] 限定原目标的永久唤醒；成功或拒绝均释放重入标记。
func _finish_coffee_wakeup(game_ref: WeakRef, board: BoardRuntime, phase: StagePhaseDefinition) -> void:
	_coffee_wake_tween = null
	_coffee_wake_game_ref = null
	_coffee_wake_board = null
	_coffee_wake_phase = null
	var game: MainGameManager = game_ref.get_ref() as MainGameManager # 失效引用只结束本次动画，不寻找替代植物。
	if CoffeeBeanUsePlan.wakeup_context_current(game, board, phase) \
			and MushroomPlantQuery.is_active(self, game) and is_instance_valid(sleep_component):
		sleep_component.wake_permanently()


## 植物修改睡眠
func update_is_sleeping(new_is_sleeping:bool):
	self.is_sleeping = new_is_sleeping


#region 花园植物
## 满足当前需求
func satisfy_need(item: GardenManager.E_NeedItem):
	garden_component.satisfy_need(item)

## 获取当前花园植物数据
func get_curr_plant_data():
	return garden_component.get_curr_plant_data()
#endregion

## 获取植物存档数据
func gat_save_game_data_plant()->Dictionary:
	var save_game_data_plant: Dictionary = {} # 基础身份、生命与永久唤醒，不保存临时光环来源。
	save_game_data_plant["is_sleeping"] = is_sleeping
	# 临时光环只重建来源，不把保存时的清醒误存成永久咖啡豆效果。
	save_game_data_plant["is_permanently_awake"] = sleep_component.is_permanently_awake
	save_game_data_plant["plant_type"] = plant_type
	save_game_data_plant["curr_hp"] = hp_component.curr_hp
	save_game_data_plant["is_imitater_material"] = is_imitater_material
	if revival_health_scale < 1.0:
		save_game_data_plant["revival_health_scale"] = revival_health_scale
		save_game_data_plant["revival_max_health"] = hp_component.max_hp
	var sun: CreateSunComponent = get_node_or_null(^"CreateSunComponent") as CreateSunComponent # 永久咖啡来源随成熟、保存和复生保留。
	if sun != null:
		save_game_data_plant["coffee_solar_bonus"] = sun.coffee_solar_bonus
	return save_game_data_plant

## 恢复 [param save_game_data_plant] 的生命及永久唤醒；临时光环仍由当前场上来源决定。
## 旧档没有永久字段时，仅将日眠环境中本应睡眠的清醒状态视为咖啡豆效果。
func load_game_data_plant(save_game_data_plant:Dictionary):
	var legacy_awake: bool = is_sleep_in_day and sleep_component.is_sleep_environment() \
		and not bool(save_game_data_plant.get("is_sleeping", true)) # 兼容旧版白天咖啡豆存档。
	sleep_component.restore_permanent_awake(bool(save_game_data_plant.get(
		"is_permanently_awake", legacy_awake)))
	var sun: CreateSunComponent = get_node_or_null(^"CreateSunComponent") as CreateSunComponent # 不直接改阳光菇阶段原始产值。
	if sun != null:
		sun.coffee_solar_bonus = float(save_game_data_plant.get("coffee_solar_bonus", 0.0))

	hp_component.curr_hp = save_game_data_plant["curr_hp"]
	hp_component.signal_hp_loss.emit(hp_component.curr_hp, true)


## 离树检查 [param state] 的完整基础字段；失败时不触发任何角色回调。
func accepts_save_state(state: Dictionary) -> bool:
	var solar: Variant = state.get("coffee_solar_bonus", 0.0) # 旧存档没有咖啡永久产值来源。
	var revival: Variant = state.get("revival_health_scale", 1.0) # 旧存档保持正常最终最大生命。
	return state.get("plant_type") is int and int(state["plant_type"]) == int(plant_type) \
		and state.get("curr_hp") is int and int(state["curr_hp"]) > 0 \
		and state.get("is_imitater_material") is bool \
		and (not state.has("is_sleeping") or state["is_sleeping"] is bool) \
		and (not state.has("is_permanently_awake") or state["is_permanently_awake"] is bool) \
		and (solar is int or solar is float) and is_finite(float(solar)) \
		and float(solar) >= 0.0 and float(solar) <= 0.5 \
		and (revival is int or revival is float) and is_finite(float(revival)) \
		and float(revival) > 0.0 and float(revival) <= 1.0 \
		and (not state.has("revival_max_health") or (state["revival_max_health"] is int \
			and int(state["revival_max_health"]) > 0))
