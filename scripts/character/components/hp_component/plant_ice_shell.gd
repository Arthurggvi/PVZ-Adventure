## 普通植物冻结的独立耐久池；猎人持久性随冰壳保存，不另设冻结计时器。
## 普通定时冻结仍读取角色原生状态，重复施冻不会补回本次剩余耐久。
extends RefCounted
class_name PlantIceShell

## 新冰壳的固定耐久，不参与植物本体最大生命、回复或生命百分比。
const MAX_HP: int = 3000
## 首次实际冻结才加载代理场景，避免植物基础脚本形成预加载循环或扩大冷启动依赖。
const TARGET_SCENE_PATH: String = "res://scenes/character/plant/plant_ice_shell_target.tscn"
## [param amount] 是唯一耐久的新值，代理生命组件只同步查询镜像。
signal durability_changed(amount: int)
## 拥有原生冻结因子与视觉的本株植物，不跨实例或跨战场继承。
var _plant: Plant000Base
## 本次冰壳剩余耐久；破壳时交回原生解冻入口。
var _hp: int = 0
## 猎人造成的持久冰封；只随破壳、清寒、死亡或真正离树解除。
var _persistent: bool = false
## 挂在原生命面板中的独立耐久标签，遵循植物血量显示设置。
var _label: Label
## 本壳唯一的敌方设施受击代理；植物仍保留原阵营与原受击区域。
var _target: PlantIceShellTarget

## [param plant] 是唯一状态所有者；[param label_parent] 是已有生命面板。
## 每个生命组件只安装一次；冻结后显式创建敌方设施代理，不增加全局缓存或僵尸登记。
func setup(plant: Plant000Base, label_parent: Control) -> void:
	_plant = plant
	if not is_instance_valid(_plant) or not is_instance_valid(label_parent):
		return
	_label = Label.new()
	_label.name = "IceShellLabel"
	_label.position = Vector2(-30.0, 28.0)
	_label.add_theme_color_override("font_color", Color(0.64, 0.88, 1.0))
	_label.add_theme_font_size_override("font_size", 12)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_parent.add_child(_label)
	_plant.signal_update_speed.connect(_on_speed_changed)
	_plant.signal_character_death.connect(_clear_owner_state)
	_plant.tree_exiting.connect(_on_tree_exiting)
	_on_speed_changed(1.0)

## 返回当前冰壳是否有效；死亡、离树或普通冻结结束后立即为假。
func is_active() -> bool:
	return current_hp() > 0

## 返回当前可消耗耐久；不以生命面板可见性作为战斗资格。
func current_hp() -> int:
	return _hp if _is_ordinary_frozen() else 0

## 返回是否由猎人维持本次普通冻结；原有定时冻结不得延长或替换它。
func is_persistent() -> bool:
	return _persistent and is_active()

## 为已通过外部控制资格检查的植物准备持久冰壳，返回是否首次授予。
## 调用方须在同一同步调用中进入原生冻结；已有任意寒冷冻结均拒绝。
func begin_persistent() -> bool:
	if not _is_live_plant() or is_active() or _plant.is_cold_frozen():
		return false
	_persistent = true
	_hp = MAX_HP
	_update_label()
	return true

## 返回本株是否仍是出战中的有效植物；换格离树期间查询暂时失效但不删除耐久。
func _is_live_plant() -> bool:
	return is_instance_valid(_plant) and _plant.is_inside_tree() and not _plant.is_death \
		and not _plant.is_queued_for_deletion() \
		and _plant.character_init_type == Character000Base.E_CharacterInitType.IsNorm

## 只读取原生普通冻结因子，不把深寒、眩晕或其他零速来源变成冰壳。
func _is_ordinary_frozen() -> bool:
	return _is_live_plant() and _plant.influence_speed_factors.get(
		Character000Base.E_Influence_Speed_Factor.IceFreezeSpeed, 1.0) <= 0.0

## [param _rate] 是原生合成速度；只同步普通冻结的进入和退出，不重置已有耐久。
func _on_speed_changed(_rate: float) -> void:
	if not _is_ordinary_frozen():
		_clear()
		return
	if _hp == 0:
		_hp = MAX_HP
	_update_label()
	_ensure_target.call_deferred()

## 物理碰撞回调结束后才创建代理，避免在物理查询刷新中修改碰撞形状。
## 多个同帧速度通知只会得到一个代理；清寒后晚到的创建请求直接结束。
func _ensure_target() -> void:
	if not is_active() or (is_instance_valid(_target) and not _target.is_queued_for_deletion()):
		return
	var scene: PackedScene = load(TARGET_SCENE_PATH) as PackedScene # 资源由引擎缓存，冰壳不建立额外全局资源表。
	if scene == null:
		push_error("无法加载植物冰壳受击代理")
		_plant.end_ice_freeze_control()
		return
	var instance: Node = scene.instantiate() # 类型不符时仍保留原节点引用以便释放。
	var target: PlantIceShellTarget = instance as PlantIceShellTarget # 本实例显式绑定同一耐久池。
	if target == null:
		push_error("植物冰壳代理场景类型不匹配")
		instance.free()
		_plant.end_ice_freeze_control()
		return
	_target = target
	target.setup(_plant, self)
	_plant.add_child(target)
	target.sync_placement()

## 换格时同步已有代理；尚未创建的代理会直接读取新位置，不重置剩余耐久。
func sync_target_placement() -> void:
	if is_instance_valid(_target) and not _target.is_queued_for_deletion():
		_target.sync_placement()

## 吸收 [param damage] 点已完成减伤的伤害，返回继续进入技能护甲及本体的余量。
## 破壳保留旧减速与其他控制；持久特效只在此时启动一次原生碎冰粒子。
func absorb(damage: int) -> int:
	if damage <= 0 or not is_active():
		return maxi(0, damage)
	var absorbed: int = mini(damage, _hp) # 仅消耗实际存在的耐久，保持统一伤害回执准确。
	_hp -= absorbed
	_update_label()
	if _hp == 0:
		_plant.end_ice_freeze_control(_persistent)
	return damage - absorbed

## 只清本壳数据；原生解冻信号不会反过来再次触发解冻。
func _clear() -> void:
	_hp = 0
	_persistent = false
	_update_label()
	var target: PlantIceShellTarget = _target # 先撤销所有权再通知代理，防止死亡回调重复清壳。
	_target = null
	if is_instance_valid(target):
		target.retire()

## 死亡和真正退场清理持久视觉与控制，不创建解冻保护计时器。
func _clear_owner_state() -> void:
	if is_instance_valid(_plant):
		_plant.clear_cold()
	_clear()

## 同步换格保留本壳及原计时；真正离树清掉临时状态，避免重挂旧实例残留冻结。
func _on_tree_exiting() -> void:
	if not _plant.is_being_relocated:
		_clear_owner_state()

## 冰壳和技能护甲分行显示，不覆盖植物本体生命数字。
func _update_label() -> void:
	if is_instance_valid(_label):
		_label.visible = _hp > 0
		_label.text = "冰壳 %d" % _hp
	durability_changed.emit(_hp)
