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
	var tween: Tween = create_tween() # 绑定植物生命周期，离树后不唤醒其他实例。
	tween.tween_property(body, ^"scale:y", 0.8, 0.5)
	tween.tween_property(body, ^"scale:y", 1.2, 0.5)
	tween.tween_property(body, ^"scale:y", 1, 0.5)
	tween.tween_callback(sleep_component.wake_permanently)


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
	return save_game_data_plant

## 恢复 [param save_game_data_plant] 的生命及永久唤醒；临时光环仍由当前场上来源决定。
## 旧档没有永久字段时，仅将日眠环境中本应睡眠的清醒状态视为咖啡豆效果。
func load_game_data_plant(save_game_data_plant:Dictionary):
	var legacy_awake: bool = is_sleep_in_day and sleep_component.is_sleep_environment() \
		and not bool(save_game_data_plant.get("is_sleeping", true)) # 兼容旧版白天咖啡豆存档。
	sleep_component.restore_permanent_awake(bool(save_game_data_plant.get(
		"is_permanently_awake", legacy_awake)))

	hp_component.curr_hp = save_game_data_plant["curr_hp"]
	hp_component.signal_hp_loss.emit(hp_component.curr_hp, true)


## 离树检查 [param state] 的完整基础字段；失败时不触发任何角色回调。
func accepts_save_state(state: Dictionary) -> bool:
	return state.get("plant_type") is int and int(state["plant_type"]) == int(plant_type) \
		and state.get("curr_hp") is int and int(state["curr_hp"]) > 0 \
		and state.get("is_imitater_material") is bool \
		and (not state.has("is_sleeping") or state["is_sleeping"] is bool) \
		and (not state.has("is_permanently_awake") or state["is_permanently_awake"] is bool)
