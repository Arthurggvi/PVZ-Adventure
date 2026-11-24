extends Node2D
class_name ZombieDeathBomb

@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2
## 尚未报告播放完成的粒子发射器数量，零表示尚未开始或已结束。
var _emitters_left := 0


## 在僵尸销毁前将爆炸迁移到行节点，超额时跳过粒子。
func activate_it() -> void:
	if _emitters_left > 0:
		return
	var game := get_tree().current_scene as MainGameManager # 预览没有战场额度。
	var kind := StringName(scene_file_path) # 小推车击杀等复用同一爆炸场景。
	var origin: Vector2 = global_position # 迁移前记录去重使用的爆心。
	if is_instance_valid(game) and not game.blast_fx_budget.can_start(kind, origin):
		return
	reparent(owner.get_parent())
	if is_instance_valid(game):
		game.blast_fx_budget.track(self, kind, origin)
	_emitters_left = 2
	gpu_particles_2d.finished.connect(_on_emitter_finished, CONNECT_ONE_SHOT)
	gpu_particles_2d_2.finished.connect(_on_emitter_finished, CONNECT_ONE_SHOT)
	gpu_particles_2d.emitting = true
	gpu_particles_2d_2.emitting = true


## 两个发射器可能以任意顺序结束，最后一个完成时释放表现与额度。
func _on_emitter_finished() -> void:
	_emitters_left -= 1
	if _emitters_left == 0:
		queue_free()
