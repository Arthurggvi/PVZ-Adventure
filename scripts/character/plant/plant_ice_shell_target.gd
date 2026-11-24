## 冰壳的敌方设施受击代理；植物本体保持原阵营，代理不登记为僵尸或植物。
## 只提供碰撞、索敌及生命接口，冰块美术与唯一耐久仍由所属植物的冰壳维护。
extends EnemyStructureBase
class_name PlantIceShellTarget

## 被包住的确切植物；同格南瓜、普通植物和承托分别拥有各自代理。
var _plant: Plant000Base
## 唯一冰壳状态；代理及其生命组件都不保存另一份可消耗耐久。
var _shell: PlantIceShell

## 入树前绑定 [param plant] 与 [param shell]，场景内部组件的 owner 仍为本代理。
func setup(plant: Plant000Base, shell: PlantIceShell) -> void:
	_plant = plant
	_shell = shell
	(get_node(^"HpComponent") as HpComponentIceShell).bind_shell(shell)

## 重挂时同步新行号；不重新登记植物格位、僵尸波次或恢复冰壳耐久。
func _enter_tree() -> void:
	if is_instance_valid(_plant):
		lane = _plant.lane

## 复用设施登记与必要组件，碰撞形状只复制所属植物自身的实际几何。
func _ready() -> void:
	super()
	if not is_instance_valid(_plant) or _shell == null or not _shell.is_active():
		retire()
		return
	var source_real: Area2D = _plant.hurt_box_component.hurt_box_real # 原植物真实受击区，保留南瓜等物种的自身尺寸。
	var source_detect: Area2D = _plant.hurt_box_component.get_node_or_null(^"HurtBoxDetection") as Area2D # 坡面检测可有独立偏移。
	_copy_colliders(source_real, %HurtBoxReal as Area2D)
	_copy_colliders(source_detect if source_detect != null else source_real, %HurtBoxDetection as Area2D)
	sync_placement()

## 复制 [param source] 的碰撞形状到 [param target]；只在延迟创建代理的就绪阶段调用。
## 保持代理的敌方碰撞层，不复制植物阵营、监听信号或其他组件。
func _copy_colliders(source: Area2D, target: Area2D) -> void:
	for previous: Node in target.get_children(): # 移除基础场景的默认胶囊，避免叠加额外命中范围。
		target.remove_child(previous)
		previous.queue_free()
	for collider: Node in source.get_children(): # 只复制形状节点，不复制外部行为。
		if collider is CollisionShape2D or collider is CollisionPolygon2D:
			var copied: Node = collider.duplicate(0) # 仅复制内建几何属性，不继承脚本、信号或组；资源形状可共享。
			target.add_child(copied)
			copied.owner = self

## 植物换格后同步行与两个受击区变换；代理作为植物子节点跟随平台及身体整体移动。
func sync_placement() -> void:
	if not is_node_ready() or not is_instance_valid(_plant) or not is_inside_tree():
		return
	lane = _plant.lane
	(%HurtBoxReal as Area2D).global_transform = _plant.hurt_box_component.hurt_box_real.global_transform
	var source_detect: Area2D = _plant.hurt_box_component.get_node_or_null(^"HurtBoxDetection") as Area2D # 无独立检测区时使用真实区。
	(%HurtBoxDetection as Area2D).global_transform = source_detect.global_transform \
		if source_detect != null else _plant.hurt_box_component.hurt_box_real.global_transform

## 双阵营范围命中与共享 hit_scope 使用所属植物去重，不将本方法用于改变玩家子弹阵营。
func combat_hit_owner() -> Character000Base:
	return _plant if not is_death and not is_queued_for_deletion() and is_instance_valid(_plant) else null

## 火豆、辣椒等设施通用解冻调用转给本株植物；清壳同步关闭本代理。
func cancel_ice() -> void:
	if not is_death and not is_queued_for_deletion() and is_instance_valid(_plant) \
			and _shell != null and _shell.is_active():
		_plant.cancel_ice()

## 普通设施处决只打破冰壳，不杀死所属植物，不产生植物死亡或复生记录。
func character_death() -> void:
	if is_death:
		return
	retire()
	if _shell != null and _shell.is_active():
		_shell.absorb(_shell.current_hp())

## 清寒或破壳立即撤销命中资格，再等待帧末释放碰撞节点；不触发掉落或亡语。
func retire() -> void:
	if is_death:
		return
	is_death = true
	if is_instance_valid(hurt_box_component):
		hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	signal_character_death.emit()
	queue_free()

## 意外单独移除代理也清掉所属冰封；同步换格保留状态，正常清壳不重复回调。
func _exit_tree() -> void:
	if not is_death and is_instance_valid(_plant) and not _plant.is_being_relocated \
			and _shell != null and _shell.is_active():
		_plant.clear_cold()
