## 融合体后代的短出生衔接：只叠加身体偏移、透明度与脚点遮罩，不改变战斗资格。
class_name LargeFusionBirthReveal
extends Node

## 身体从融合体下缘舒展到普通行走姿势的游戏秒数。
const DURATION: float = 0.38
## 额外压低的身体距离；不移动角色根节点、受击框或脚点。
const START_OFFSET: float = 28.0
## 后代实例拥有此节点，角色释放时演出一并清理。
var _source: Zombie000Base
## 只改身体已有的姿态合成入口，不直接覆盖 position。
var _body: BodyCharacter
## 此次演出已经播放的秒数，随场景暂停。
var _age: float = 0.0
## 本组件上次叠加的纵向偏移，结束时只撤销这一份。
var _offset: float = 0.0
## 出生前的透明度，只在通道仍归本组件时恢复。
var _original_alpha: float = 1.0
## 上次写入的透明度，用于识别其他系统接管此通道。
var _last_alpha: float = 1.0
## 外部重写透明度后立即放弃该通道，不覆盖其死亡或受击表现。
var _owns_alpha: bool = true
## 安装遮罩前的身体材质；非空时根本不安装出生遮罩。
var _original_material: Material
## 仅记录本次安装的独立遮罩，不能清除后来替换的材质。
var _mask: ShaderMaterial
## 遮罩安装前受影响的身体部件。
var _material_users: Array[Node2D] = []
## 各部件原来的材质继承状态，与部件列表一一对应。
var _original_inheritance: Array[bool] = []
## 各部件原来的材质对象，用来识别期间发生的材质替换。
var _part_materials: Array[Material] = []
## 正常结束、死亡与离树可以同时发生，所有附加状态只撤销一次。
var _released: bool = false

## 给已正常登记的 [param child] 播放纯视觉出生；展示实例和正在退场的角色直接跳过。
static func present(child: Zombie000Base) -> void:
	if not is_instance_valid(child) or not child.is_inside_tree() or child.is_queued_for_deletion() \
			or child.is_death or child.retiring_from_battle \
			or child.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not is_instance_valid(child.body) or child.get_node_or_null(^"FusionBirthReveal") != null:
		return
	var reveal: LargeFusionBirthReveal = LargeFusionBirthReveal.new() # 先绑定角色，再让入树回调安装表现。
	reveal.name = &"FusionBirthReveal"
	reveal._source = child
	reveal._body = child.body
	child.add_child(reveal)

## 安装独立的短出生表现；不调用带有行为锁、密集泥土或音效的通用出土入口。
func _ready() -> void:
	if not is_instance_valid(_source) or not is_instance_valid(_body):
		_finish()
		return
	_original_alpha = _body.modulate.a
	_last_alpha = _original_alpha
	_original_material = _body.material
	_source.signal_character_death.connect(_finish, CONNECT_ONE_SHOT)
	if _original_material == null:
		_remember_material_users(_body)
		_body.body_mask_start(_source.global_position.y)
		_mask = _body.material as ShaderMaterial
	_apply_offset(START_OFFSET)
	_apply_alpha(0.14)
	LargeFusionDust.emit_ground(_source.get_parent() as Node2D, _source.global_position, 0.70, LargeFusionDust.Kind.BIRTH)

## [param delta] 为引擎游戏时间；新生立即死亡或清场时不等待演出走完。
func _process(delta: float) -> void:
	if not is_instance_valid(_source) or not is_instance_valid(_body) or _source.is_death \
			or _source.is_queued_for_deletion() or _source.retiring_from_battle:
		_finish()
		return
	_age = minf(_age + delta, DURATION)
	var progress: float = _age / DURATION # 姿势和透明度共用同一暂停友好的进度。
	_apply_offset(START_OFFSET * pow(1.0 - progress, 3.0))
	_apply_alpha(lerpf(0.14, 1.0, smoothstep(0.0, 0.90, progress)))
	if _mask != null and _body.material == _mask:
		_mask.set_shader_parameter(&"cutoff_y", _source.global_position.y)
	if _age >= DURATION:
		_finish()

## [param next_offset] 只替换本组件的附加高度，保留并行入水、抛飞和原生姿态变化。
func _apply_offset(next_offset: float) -> void:
	_body.pose_position += Vector2(0.0, next_offset - _offset)
	_offset = next_offset

## [param factor] 只控制 alpha；若外部写过这一通道，保留外部结果及所有 RGB 调色。
func _apply_alpha(factor: float) -> void:
	if not _owns_alpha:
		return
	if not is_equal_approx(_body.modulate.a, _last_alpha):
		_owns_alpha = false
		return
	_last_alpha = _original_alpha * factor
	_body.modulate.a = _last_alpha

## 保存 [param parent] 下将被通用遮罩改为继承材质的部件，与原工具的递归范围保持一致。
func _remember_material_users(parent: Node2D) -> void:
	for child: Node in parent.get_children(): # 非 Node2D 分支不会被通用材质工具修改。
		if child is Node2D:
			var part: Node2D = child as Node2D # 保留原资源身份，避免收尾改动后加的材质。
			_material_users.append(part)
			_original_inheritance.append(part.use_parent_material)
			_part_materials.append(part.material)
			_remember_material_users(part)

## 普通结束和死亡信号共用收尾，节点释放不等待任何补间或协程。
func _finish() -> void:
	_release()
	queue_free()

## 直接清场释放角色也会执行，避免只有正常播完才恢复临时状态。
func _exit_tree() -> void:
	_release()

## 仅撤销自己仍持有的表现状态，不能抹除其他效果接管后的颜色或材质。
func _release() -> void:
	if _released:
		return
	_released = true
	set_process(false)
	if is_instance_valid(_source) and _source.signal_character_death.is_connected(_finish):
		_source.signal_character_death.disconnect(_finish)
	if not is_instance_valid(_body):
		return
	_apply_offset(0.0)
	_apply_alpha(1.0)
	if _mask != null and _body.material == _mask:
		_body.material = _original_material
		for index: int in range(_material_users.size()): # 只还原未被其他系统接管的部件。
			var part: Node2D = _material_users[index] # 此部件可能已因死亡掉落而提前释放。
			if is_instance_valid(part) and part.use_parent_material and part.material == _part_materials[index]:
				part.use_parent_material = _original_inheritance[index]
	_material_users.clear()
	_original_inheritance.clear()
	_part_materials.clear()
