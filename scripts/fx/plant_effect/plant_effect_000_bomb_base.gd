extends Node2D
class_name BombEffectBase

## 同一节点只启动一次表现。
var _started := false


## 只对爆炸表现申请额度，伤害和结算信号继续由原调用端处理。
func activate_bomb_effect() -> void:
	if _started or not is_inside_tree() or is_queued_for_deletion():
		return
	_started = true
	var game := get_tree().current_scene as MainGameManager # 预览场景可直接播放原效果。
	if is_instance_valid(game) and is_instance_valid(game.bombs):
		var kind := StringName(scene_file_path) # 同一场景的原版与连锁爆炸共用额度。
		var origin: Vector2 = global_position # 在变更父节点之前保存世界坐标。
		if not game.blast_fx_budget.can_start(kind, origin):
			queue_free()
			return
		if get_parent() != game.bombs:
			reparent(game.bombs)
		game.blast_fx_budget.track(self, kind, origin)
	visible = true
	_play_effect()


## 特效子类在这里启动各自的动画、粒子及收尾。
func _play_effect() -> void:
	pass
