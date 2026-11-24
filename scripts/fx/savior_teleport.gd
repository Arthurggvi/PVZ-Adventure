## 教堂传送的局部照明、世界内浮尘和同场共用的钟声。
extends Node

## 正式教堂唯一的局部照明及投影入口。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")
## 在实际原画上控制显隐，位置和尺幅交给原画节点。
const SaviorVisual = preload("res://scripts/character/zombie_boss/savior/savior_visual.gd")
## 死亡时光的聚拢和退去，单位为战斗秒。
const DEPARTURE_SECONDS := 1.08

## 一次传送的真实演员、随时间更新的灯和空气参数。
class Transfer:
	## 不从镜头位置倒推脚点。
	var actor: ZB000Base
	## 当前实际姿势，显隐不会修改动作。
	var pose: SaviorVisual
	## 和真实影子垂足分开，允许光斑上下移动。
	var lamp: Marker2D
	## 按实际原画与世界变换测得的身高。
	var height: float
	## 按固定落点取随机相位，时间只负责推进气流。
	var seed: float
	## 空气批次的时钟、强度、光心高度和落地程度。
	var volume: Color
	## 只有出场的传送需要在收光后交回死亡结算。
	var completed: Callable
	## 退场累计战斗秒。
	var age: float
	## 退场初始是否带有平时的红灯，开白灯时同步渐弱。
	var red_start: float
	## 入场触地或退场聚光已敲过一次。
	var rang := false

## 放在实际角色下方的世界画布，随相机和原场景一起运动。
@export var air: MultiMeshInstance2D

## 本场灯和角色所在的真实世界。
var _world: Node2D
## 白光直接参与已有可见性和剪影。
var _field: LightField
## 控制救主原有红灯的场景回调。
var _set_red: Callable
## 两个分身可同时退场，各自保有灯和动作。
var _transfers: Dictionary[int, Transfer] = {}
## 完全同时的传送共用一次钟击，错开的钟击保留共鸣重叠。
var _last_bell_frame := -1
## 共用一口钟的播放器，和本场战斗一起释放。
@onready var _bell: AudioStreamPlayer = $Bell

## [param world] 与 [param field] 来自正式战斗，[param set_red] 控制原有角色灯。
func configure(world: Node2D, field: LightField, set_red: Callable) -> void:
	_world = world
	_field = field
	_set_red = set_red

## [param actor] 在真实落点按 [param progress] 显形。[param portrait] 时由抬掌帧单独触发钟声。
func arrive(actor: ZB000Base, progress: float, portrait: bool = false) -> void:
	if progress >= 1.0:
		finish_arrival(actor)
		return
	var transfer: Transfer = _track(actor) # 光照在显形前先进入教堂。
	var focus: float = smoothstep(0.06, 0.61, progress) # 光斑沿墙顺到石面。
	var light: float = smoothstep(0.03, 0.37, progress) * (1.0 - smoothstep(0.59, 1.0, progress))
	light *= 0.73 if portrait else 1.0
	var presence: float = smoothstep(0.20, 0.67, progress) # 先看见地表，再显出实际原画。
	_place_light(transfer, light, lerpf(0.66, 0.28, focus))
	transfer.volume = Color(progress, light, 0.66 - 0.38 * focus, focus)
	transfer.pose.set_teleport_pose(presence, light)
	_set_red.call(actor, smoothstep(0.52, 1.0, progress))
	if not portrait:
		_ring_on_contact(transfer, progress, 0.31)

## 将 [param actor] 交回正常原画和红灯，不覆盖已经开始的死亡。
func finish_arrival(actor: ZB000Base) -> void:
	var id: int = actor.get_instance_id() # 使用真实生命周期的实例编号。
	var transfer: Transfer = _transfers.get(id) # 中断时可能尚没有灯。
	if actor.is_death or (transfer != null and transfer.completed.is_valid()):
		return
	if transfer != null:
		_release(id)
	var pose := actor.get_node(^"Body/SaviorVisual") as SaviorVisual # 下一拍交给原有祈祷。
	pose.set_teleport_pose(1.0)
	_set_red.call(actor, 1.0)

## [param actor] 已完成死亡判定。光退去后调用 [param completed] 交回原遭遇结算。
func depart(actor: ZB000Base, completed: Callable) -> void:
	var transfer: Transfer = _track(actor) # 离场留在死亡当帧的真实脚点。
	var source := actor.get_node(^"Body/ChurchLight") as Node2D # 交接还在发亮的角色灯。
	transfer.red_start = float(source.visible)
	transfer.completed = completed
	transfer.age = 0.0
	transfer.rang = false
	_present_departure(transfer, 0.0)

## [param frozen] 只绕过救主特写取得的时停，其他情况下随战斗暂停及离场回收。
func set_cinematic_audio(frozen: bool) -> void:
	_bell.process_mode = Node.PROCESS_MODE_ALWAYS if frozen else Node.PROCESS_MODE_INHERIT

## 播放一次同一口钟。多个间隔触发可保留各自的衰减尾音。
func ring_bell() -> void:
	var frame_id: int = Engine.get_process_frames() # 同帧聚光共享一次环境声。
	if frame_id == _last_bell_frame:
		return
	_last_bell_frame = frame_id
	_bell.bus = SoundManager.spatial_sfx_bus(SoundManager.SFXSpace.DISTANT)
	_bell.play()

## [param delta] 为正常战斗步长；时停镜头以零步长刷新。活动过光源时返回 true。
func present_frame(delta: float) -> bool:
	if _transfers.is_empty():
		return false
	var mesh: MultiMesh = air.multimesh # 只随同时在场的传送容量扩展。
	if mesh.instance_count < _transfers.size():
		mesh.instance_count = maxi(_transfers.size(), mesh.instance_count * 2)
	var slot := 0 # 活动的世界内薄雾连续写入一个批次。
	for id: int in _transfers.keys(): # 允许完成回调释放当前记录。
		var transfer: Transfer = _transfers.get(id) # 回调有可能同时移除下一项。
		if transfer == null:
			continue
		if not is_instance_valid(transfer.actor) or transfer.actor.is_queued_for_deletion():
			_release(id)
			continue
		if transfer.completed.is_valid():
			transfer.age += delta
			var t: float = minf(1.0, transfer.age / DEPARTURE_SECONDS) # 保持完整的光照退场。
			_present_departure(transfer, t)
			if t >= 1.0:
				var done: Callable = transfer.completed # 先收光，再交还奖励。
				_release(id)
				done.call()
				continue
		_submit(transfer, mesh, slot)
		slot += 1
	mesh.visible_instance_count = slot
	return true

## 在 [param progress] 内让红光让位，白光经过原位置，再向上方退去。
func _present_departure(transfer: Transfer, progress: float) -> void:
	var gather: float = smoothstep(0.015, 0.28, progress) # 先把临近石面照亮。
	var lift: float = smoothstep(0.42, 0.99, progress) # 周围受光的位置先从石面移走。
	var light: float = gather * (1.0 - smoothstep(0.50, 1.0, progress))
	var presence: float = 1.0 - smoothstep(0.26, 0.82, progress) # 原画不拉扯，明暗从地面朝上退。
	_place_light(transfer, light, lerpf(0.28, 0.69, lift))
	transfer.volume = Color(progress, light, lerpf(0.28, 0.69, lift), 1.0 - lift)
	transfer.pose.set_teleport_pose(presence, light, true)
	_set_red.call(transfer.actor, transfer.red_start * (1.0 - smoothstep(0.055, 0.43, progress)))
	_ring_on_contact(transfer, progress, 0.22)

## [param threshold] 为 [param transfer] 中灯第一次明确接触石面的归一化时间。
func _ring_on_contact(transfer: Transfer, progress: float, threshold: float) -> void:
	if not transfer.rang and progress >= threshold:
		transfer.rang = true
		ring_bell()

## [param transfer] 的光照中心以身高为单位从 [param elevation] 向地面移动，投影脚点继续使用实际世界节点。
func _place_light(transfer: Transfer, strength: float, elevation: float) -> void:
	if not is_instance_valid(transfer.lamp) or not is_instance_valid(_field):
		return
	transfer.lamp.global_position = transfer.actor.shadow.global_position + Vector2(-0.15, -elevation) * transfer.height
	_field.set_light_intensity(transfer.lamp.get_instance_id(), LightField.Tone.WHITE, strength)

## 为 [param actor] 找回本次传送，首次使用才登记局部真光。
func _track(actor: ZB000Base) -> Transfer:
	var id: int = actor.get_instance_id() # 让灯的生命周期和真实角色绑定。
	if _transfers.has(id):
		return _transfers[id]
	var transfer := Transfer.new() # 所有绘制数据保存在当前实例记录。
	transfer.actor = actor
	transfer.pose = actor.get_node(^"Body/SaviorVisual") as SaviorVisual
	var texture: Texture2D = transfer.pose.sprite_frames.get_frame_texture(transfer.pose.animation, transfer.pose.frame) # 实际裁好的原画。
	transfer.height = texture.get_height() * transfer.pose.get_global_transform().y.length()
	transfer.seed = fposmod(actor.global_position.dot(Vector2(0.051, 0.073)), 1.0)
	if is_instance_valid(_field):
		transfer.lamp = Marker2D.new()
		_world.add_child(transfer.lamp)
		_field.register_light(transfer.lamp, LightField.Tone.WHITE, transfer.height * 0.82, Vector2.ZERO,
			actor.shadow, transfer.height * 1.21, transfer.height * 0.075, 0.0, false, true)
	_transfers[id] = transfer
	return transfer

## 在角色后面的世界层为 [param transfer] 写入一个有界空气图元。
func _submit(transfer: Transfer, mesh: MultiMesh, slot: int) -> void:
	var feet: Vector2 = transfer.actor.shadow.global_position # 主世界和空气网格共用原相机。
	var half: Vector2 = Vector2(0.59, 0.86) * transfer.height # 区域覆盖脚前和头顶上方的一段空气。
	var center: Vector2 = air.to_local(feet - Vector2(0.13, 0.64) * transfer.height) # 略从画面远侧斜过来。
	mesh.set_instance_transform_2d(slot, Transform2D(0.0, half, 0.0, center))
	mesh.set_instance_color(slot, Color(transfer.seed, float(transfer.completed.is_valid()), 0.0))
	mesh.set_instance_custom_data(slot, transfer.volume)

## 收回 [param id] 的灯。完成退场和卸载场景都走同一入口。
func _release(id: int) -> void:
	var transfer: Transfer = _transfers[id] # 白光的清理不影响原来的角色灯。
	if is_instance_valid(transfer.lamp):
		if is_instance_valid(_field):
			_field.unregister_light(transfer.lamp.get_instance_id())
		transfer.lamp.queue_free()
	_transfers.erase(id)
	if _transfers.is_empty() and is_instance_valid(air):
		air.multimesh.visible_instance_count = 0

## 关卡离开时只回收场景内的灯，不再发出死亡奖励通知。
func _exit_tree() -> void:
	for id: int in _transfers.keys(): # 快照允许收回每个当前记录。
		_release(id)
