extends Node2D
class_name ZamboniDeathBomb

@onready var body: Node2D = $Body
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2

var is_activate:=false
var _flying_sprites = []

## 车身存活期间无需为尚未启用的碎片运行每帧处理。
func _ready() -> void:
	set_process(false)

func _process(delta):
	if is_activate:
		for sprite_data in _flying_sprites:
			var node = sprite_data.node
			var vel = sprite_data.velocity
			var rot = sprite_data.angular_speed

			# 更新位置和旋转
			node.global_position += vel * delta
			node.rotation += deg_to_rad(rot) * delta
			# 添加阻力
			sprite_data.velocity = vel.move_toward(Vector2.ZERO, delta * 200)

## 造冰车与投篮车复用战场爆炸额度，超额时由伤害入口继续完成死亡。
func activate_it() -> void:
	if is_activate:
		return
	var game := get_tree().current_scene as MainGameManager # 预览没有战场额度。
	var kind := StringName(scene_file_path) # 同一碎片场景在附近同帧只播放一次。
	var origin: Vector2 = global_position # 迁移到行节点前的爆心世界坐标。
	if is_instance_valid(game) and not game.blast_fx_budget.can_start(kind, origin):
		return
	is_activate = true
	visible = true
	explode()
	reparent(owner.get_parent())
	if is_instance_valid(game):
		game.blast_fx_budget.track(self, kind, origin)
	set_process(true)
	gpu_particles_2d.emitting = true
	gpu_particles_2d_2.emitting = true
	await gpu_particles_2d.finished
	queue_free()

func explode():
	var base_force = 150
	var base_rot = 100  # 最大角速度

	for child in body.get_children():
		if child is Sprite2D:
			# 给它添加炸飞动画（速度、旋转、重力等）
			var dir = Vector2(randf() * 1.5 - 0.75, -1).normalized()
			var force = base_force
			var rot_speed = randf_range(-base_rot, base_rot)

			# 把炸飞行为统一加到动画系统里（如用 Dictionary 存状态）
			_flying_sprites.append({
				"node": child,
				"velocity": dir * force,
				"angular_speed": rot_speed,
			})
