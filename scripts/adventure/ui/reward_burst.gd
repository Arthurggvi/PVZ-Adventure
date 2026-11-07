## 礼盒领奖表现复用原生星屑；不让礼盒脚本入树，不产生花园奖励或额外存档。
extends RefCounted

## 在 [param parent] 的局部 [param center] 播放星屑和一次礼盒音效，粒子结束自动释放。
static func play(parent: Control, center: Vector2) -> void:
	var source: Node = SceneRegistry.PRESENT.instantiate() # 仅提取原生粒子配置。
	var burst := source.get_node("GPUParticles2D").duplicate() as GPUParticles2D # 与原版礼盒同款彩色星屑。
	source.free()
	burst.position = center
	burst.scale = Vector2.ONE * 1.8
	parent.add_child(burst)
	burst.finished.connect(burst.queue_free)
	burst.restart()
	burst.emitting = true
	SoundManager.play_other_SFX(&"prize")
