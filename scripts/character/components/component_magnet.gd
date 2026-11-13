## 磁力菇的原生吸铁组件；攻击专用倍率只缩放吸铁冷却，不改变其他植物行为。
extends ComponentNormBase
class_name MagnetComponent

## 当前吸取铁器的显示容器，铁器沿原有补间进入其中。
@export var curr_iron_container: Node2D
## 原生吸铁冷却，负责保留进度、手动暂停及零速状态。
@onready var attack_cd_timer: SpeedTimer = $AttackCdTimer
## 原场景的吸铁检测范围。
@onready var area_2d: Area2D = $Area2D
## 正常速度下消化铁器的冷却，单位为秒。
@export var attack_cd: float = 30
## 当前显示并等待冷却结束回收的铁器副本。
var curr_iron: Node2D
## 是否处于消化铁器的冷却阶段。
var is_attack_cd: bool = false
## 角色原有速度因素乘积，与攻击专用来源独立保存。
var _owner_speed_product: float = 1.0
## 每个来源提供的相对攻速加成，撤销时不会覆盖其他来源。
var _attack_rate_sources: Dictionary[int, float] = {}
## 攻击来源合成后的冷却倍率，1 表示没有额外攻速。
var _attack_rate_multiplier: float = 1.0

## 开始一次吸铁时发出，供原生植物动画同步状态。
signal signal_attack_start
## 消化冷却完成时发出，随后允许再次吸铁。
signal signal_attack_cd_end

## 分开设置基础冷却与角色倍率，避免来源刷新重复缩短周期。
func _ready() -> void:
	super()
	attack_cd_timer.base_wait_time = attack_cd
	owner_update_speed(GlobalUtils.get_dic_product(owner.influence_speed_factors))

## [param is_enable_factor] 为本次解除的禁用原因；全部原因允许时重新检查原范围内的铁器。
func enable_component(is_enable_factor: E_IsEnableFactor) -> void:
	super(is_enable_factor)
	if is_enabling:
		for area: Area2D in area_2d.get_overlapping_areas(): # 恢复后处理已经位于范围内的目标。
			_on_area_2d_area_entered(area)

## [param iron_node] 为本次吸取的原铁器；保留原生副本显示及补间，只由可变速时钟管理冷却。
func attack_once(iron_node: IronNode) -> void:
	SoundManager.play_character_SFX("magnetshroom")
	is_attack_cd = true
	signal_attack_start.emit()
	iron_node.preprocessing_be_magnet()
	var ori_iron_global_position: Vector2 = iron_node.global_position # 原铁器的世界起点，避免容器坐标变化影响补间。
	var new_iron_node: Node2D = iron_node.duplicate() as Node2D # 独立显示副本，不受原僵尸动画控制。
	curr_iron_container.add_child(new_iron_node)
	new_iron_node.global_position = ori_iron_global_position
	new_iron_node.visible = true
	curr_iron = new_iron_node
	var tween: Tween = get_tree().create_tween() # 保留原版半秒吸入表现，不把攻击冷却倍率写入其他动画。
	tween.tween_property(new_iron_node, "position", Vector2.ZERO, 0.5)
	attack_cd_timer.start_scaled()

## 消化完成后回收显示铁器，并立即检查当前范围内的下一件铁器。
func _on_attack_cd_timer_timeout() -> void:
	signal_attack_cd_end.emit()
	is_attack_cd = false
	curr_iron.queue_free()
	for area: Area2D in area_2d.get_overlapping_areas(): # 冷却期间已进入范围的目标无需重新跨越边界。
		_on_area_2d_area_entered(area)

## [param area] 为进入原生范围的目标区域；禁用或冷却时不触发吸铁。
func _on_area_2d_area_entered(area: Area2D) -> void:
	if not is_enabling or is_attack_cd:
		return
	var area_owner: Node = area.owner # 碰撞区域对应的僵尸或独立梯子实体。
	if area_owner is Zombie000Base:
		if area_owner.iron_type == Zombie000Base.IronType.Null:
			return
		else:
			var iron_node: IronNode = area_owner.iron_node # 僵尸当前可被吸取的铁器。
			if iron_node.is_be_magnet:
				return
			else:
				iron_node.is_be_magnet = true
				attack_once(iron_node)
				area_owner.be_magnet_iron()
	elif area_owner is Ladder:
		var iron_node: IronNode = area_owner.iron_node # 独立梯子上尚未被其他磁力菇吸取的铁器。
		if iron_node.is_be_magnet:
			return
		else:
			iron_node.is_be_magnet = true
		attack_once(iron_node)
		area_owner.ladder_death()

## [param speed_product] 为角色原有速度乘积；来源加成只写吸铁冷却，不反写角色速度。
func owner_update_speed(speed_product: float) -> void:
	_owner_speed_product = speed_product
	_refresh_attack_rate()

## [param source_id] 为有效来源实例 ID；[param bonus] 为相对攻速加成，非正值撤销来源。
## 重复设置幂等；非有限值忽略，调用方负责先合成同种不叠加词条。
func set_attack_rate_source(source_id: int, bonus: float) -> void:
	if source_id <= 0 or not is_finite(bonus):
		return
	var next_bonus: float = maxf(0.0, bonus) # 非正值统一表示清除本来源。
	if float(_attack_rate_sources.get(source_id, 0.0)) == next_bonus:
		return
	if next_bonus == 0.0:
		_attack_rate_sources.erase(source_id)
	else:
		_attack_rate_sources[source_id] = next_bonus
	_attack_rate_multiplier = 1.0
	for amount: float in _attack_rate_sources.values(): # 各独立来源的相对攻速加成相加。
		_attack_rate_multiplier += amount
	_refresh_attack_rate()

## 冷却进度和零速暂停继续由 SpeedTimer 维护，不直接修改 paused 或剩余时间。
func _refresh_attack_rate() -> void:
	if is_instance_valid(attack_cd_timer):
		attack_cd_timer.set_speed_scale(_owner_speed_product * _attack_rate_multiplier)
