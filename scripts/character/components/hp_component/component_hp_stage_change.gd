extends Node2D
class_name HpStageChangeComponent
## 血量阶段变化组件,坚果和南瓜头使用
## 血量到达临界值时变化

@onready var owner_character: Character000Base = owner
@onready var hp_component: HpComponent = %HpComponent

@export_group("血量临界值(两者个数必须对应)")
@export_subgroup("本体血量临界值(血量临界值数组默认为空（2个）即可)")
## 血量临界值数组，从满血到死亡顺序,默认为空即可
@export var boundary_value_hp:Array[int]
## 每阶段血量改变的精灵节点（默认有两个阶段：掉手、掉头）
@export var body_change:Array[ResourceBodyChange]
## 当前血量阶段
var curr_hp_stage := -1:
	set(value):
		curr_hp_stage = value
		signal_hp_stage_change.emit(curr_hp_stage)

signal signal_hp_stage_change(curr_hp_stage:int)

@export_subgroup("一类防具(血量临界值数组默认为空（3个）即可)")
## 血量临界值数组，从满血到死亡顺序,默认为空即可
@export var boundary_value_hp_armor1:Array[int]
## 每阶段血量改变的精灵节点（默认有两个阶段：掉手、掉头）
@export var body_change_armor1:Array[ResourceBodyChange]
## 当前血量阶段
var curr_hp_armor1_stage := -1

@export_subgroup("二类防具(血量临界值数组默认为空（3个）即可)")
## 血量临界值数组，从满血到死亡顺序,默认为空即可
@export var boundary_value_hp_armor2:Array[int]
## 每阶段血量改变的精灵节点（默认有两个阶段：掉手、掉头）
@export var body_change_armor2:Array[ResourceBodyChange]
## 当前血量阶段
var curr_hp_armor2_stage := -1

func _ready() -> void:
	## 初始化参数
	if boundary_value_hp.is_empty():
		@warning_ignore("integer_division")
		boundary_value_hp.append(hp_component.max_hp * 2 / 3 - 1)	## 掉手
		@warning_ignore("integer_division")
		boundary_value_hp.append(hp_component.max_hp * 1 / 3 - 1)	## 掉头
		if owner is Plant000Base:
			printerr("植物使用血量阶段变化组件需对对`boundary_value_hp`赋值")

	## 修改死亡临界值
	if boundary_value_hp[-1] != 0:
		hp_component.set_death_hp(boundary_value_hp[-1])

	## 只有僵尸血量组件会初始化防具参数
	if hp_component is HpComponentZombie:
		## 初始化防具参数
		if boundary_value_hp_armor1.is_empty() and hp_component.max_hp_armor1 != 0:
			boundary_value_hp_armor1.append(hp_component.max_hp_armor1 * 2 / 3 - 1)
			boundary_value_hp_armor1.append(hp_component.max_hp_armor1 * 1 / 3 - 1)
			boundary_value_hp_armor1.append(0)

		if boundary_value_hp_armor2.is_empty() and hp_component.max_hp_armor2 != 0:
			boundary_value_hp_armor2.append(hp_component.max_hp_armor2 * 2 / 3 - 1)
			boundary_value_hp_armor2.append(hp_component.max_hp_armor2 * 1 / 3 - 1)
			boundary_value_hp_armor2.append(0)

## Before _ready, scale only explicit scene thresholds. Empty arrays will be
## generated from the already-scaled maximum HP by the component itself.
static func scale_positive_thresholds(values: Array[int], factor: float) -> void:
	for i in range(values.size()):
		if values[i] > 0:
			values[i] = maxi(1, roundi(float(values[i]) * factor))

func scale_spawn_thresholds(body_factor: float, armor_factor: float) -> void:
	scale_positive_thresholds(boundary_value_hp, body_factor)
	scale_positive_thresholds(boundary_value_hp_armor1, armor_factor)
	scale_positive_thresholds(boundary_value_hp_armor2, armor_factor)

## Rebase visual damage stages when a newly spawned plant's maximum HP changes.
## The stage component owns this data; callers never edit threshold arrays.
func set_spawn_max_health(new_max: int) -> void:
	# Spawn binding runs before @onready references become available.
	var health: HpComponent = get_parent().get_node_or_null("HpComponent") as HpComponent
	if health == null:
		push_error("HpStageChangeComponent requires sibling HpComponent")
		return
	var original_max: int = health.max_hp
	if original_max <= 0 or new_max <= 0:
		push_error("Invalid health for stage rebasing")
		return
	scale_positive_thresholds(boundary_value_hp, float(new_max) / float(original_max))
	health.set_spawn_max_health(new_max)
	if not boundary_value_hp.is_empty() and boundary_value_hp[-1] != 0:
		health.set_death_hp(boundary_value_hp[-1])

#region 本体body变化
## 判断body是否需要变化
## curr_hp: 当前剩余血量
func judge_body_change(curr_hp:int, is_drop:=true):
	## 角色不存在 or 最后血量状态 or 不掉落
	if not is_instance_valid(owner_character) or curr_hp_stage == boundary_value_hp.size() - 1 or not is_drop:
		return
	## 循环数组
	for i in range(boundary_value_hp.size()):
		if curr_hp_stage < i and curr_hp <= boundary_value_hp[i]:
			curr_hp_stage = i
			if body_change[i] == null:
				continue

			body_change[i].update_body(self)

## 获取所有的本体body掉落物
func get_all_body_change()->Array[ZombieDropBase]:
	var all_node_drop :Array[ZombieDropBase] = []

	for i in range(body_change.size()):
		if body_change[i] == null:
			continue
		var body_drop:ZombieDropBase = body_change[i].get_drop_node(self)
		if body_drop != null:
			all_node_drop.append(body_drop)
	return all_node_drop

#endregion

#region 防具body变化
## 防具血量变化判断,判断body是否需要变化
## curr_hp: 当前剩余血量
func judge_body_change_armor(curr_hp_arm:int, _curr_hp:int, is_drop:bool=true, is_armor1:bool=true):
	## 角色不存在  or 不掉落
	if not is_instance_valid(owner_character) or not is_drop:
		return

	if is_armor1:
		curr_hp_armor1_stage = update_hp_armor_stage(curr_hp_arm, curr_hp_armor1_stage, boundary_value_hp_armor1, body_change_armor1)
	else:
		curr_hp_armor2_stage = update_hp_armor_stage(curr_hp_arm, curr_hp_armor2_stage, boundary_value_hp_armor2, body_change_armor2)

func update_hp_armor_stage(curr_hp_arm:int, curr_hp_armor_stage:int, boundary_value_hp_armor:Array[int], body_change_armor:Array[ResourceBodyChange]):
	## 最后血量状态
	if curr_hp_armor_stage == boundary_value_hp_armor.size() - 1 :
		return curr_hp_armor_stage

	## 循环数组
	for i in range(boundary_value_hp_armor.size()):
		if curr_hp_armor_stage < i and curr_hp_arm <= boundary_value_hp_armor[i]:
			#print("当前血量状态：", curr_hp_stage, "小于状态：", i)
			#print("当前血量：", curr_hp_stage, "小于状态：", i)
			curr_hp_armor_stage = i

			if body_change_armor[i] == null:
				continue
			body_change_armor[i].update_body(self)

	return curr_hp_armor_stage
#endregion

## 将 [param stages] 中已发生的伤势应用到新身体，不重复生成掉落物。
func restore_body_stages(stages: Vector3i) -> void:
	_restore_visual_stages(body_change, stages.x)
	_restore_visual_stages(body_change_armor1, stages.y)
	_restore_visual_stages(body_change_armor2, stages.z)
	curr_hp_stage = stages.x
	curr_hp_armor1_stage = stages.y
	curr_hp_armor2_stage = stages.z

## 按原变化顺序应用 [param changes]，只重放到 [param stage]。
func _restore_visual_stages(changes: Array[ResourceBodyChange], stage: int) -> void:
	for index: int in range(mini(stage + 1, changes.size())): # 从首个可见损伤阶段开始，并保持原顺序。
		if changes[index] != null:
			changes[index].update_body(self, false)

## 小僵尸大麻烦更新僵尸血量变化临界值
func update_mini_zombie_hp_stage_change():
	for i in range(boundary_value_hp.size()):
		boundary_value_hp[i] /= 2
	## 修改死亡临界值
	if boundary_value_hp[-1] != 0:
		hp_component.set_death_hp(boundary_value_hp[-1])

	## 初始化防具参数
	if hp_component.max_hp_armor1 != 0:
		for i in range(boundary_value_hp_armor1.size()):
			boundary_value_hp_armor1[i] /= 2

	if hp_component.max_hp_armor2 != 0:
		for i in range(boundary_value_hp_armor2.size()):
			boundary_value_hp_armor2[i] /= 2

