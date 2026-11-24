## 雪球命中特效：只移动和淡出现成飞溅、碎片贴图，不创建替代像素或额外伤害。
extends BulletEffect000Base
class_name HunterSnowballHit

## 飞散与淡出的共同战斗时长，单位为秒；继承场景暂停及游戏倍速。
const LIFETIME_SECONDS: float = 0.38
## 与场景内五个贴图节点顺序对应的最终局部位移，单位为像素。
const SCATTER_OFFSETS: Array[Vector2] = [
	Vector2(-8.0, 6.0), Vector2(10.0, 12.0), Vector2(-22.0, -17.0),
	Vector2(18.0, -22.0), Vector2(-3.0, 22.0),
]
## 原版雪球碰撞声，仅随本物种素材加载，并通过统一音效池播放。
const HIT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/adventure/zombies/hunter/audio/Snowballhit1.ogg"),
	preload("res://assets/adventure/zombies/hunter/audio/Snowballhit2.ogg"),
	preload("res://assets/adventure/zombies/hunter/audio/Snowballhit3.ogg"),
]
## 雪球命中声的播放增益（dB），降低连续命中时的满幅瞬态。
const HIT_GAIN_DB: float = -11.0
## 五个现成贴图的父节点；沿用原命中特效场景的容器位置。
@onready var _pieces: Node2D = $AllParticles2D
## 避免同一个命中特效重复脱离弹体、播放声音或创建淡出补间。
var _activated: bool = false

## [param is_boss_hit] 原样传递原生层级规则；脱离弹体后独立播放，结束立即释放。
func activate_bullet_effect(is_boss_hit: bool = false) -> void:
	if _activated:
		return
	_activated = true
	super(is_boss_hit)
	show()
	var sound_index: int = randi_range(0, HIT_SOUNDS.size() - 1) # 每次激活只选一条真实命中音效。
	SoundManager.play_sfx_with_pool(HIT_SOUNDS[sound_index], HIT_GAIN_DB)
	var tween: Tween = create_tween().set_parallel(true) # 绑定当前特效，跟随父战场暂停及释放。
	for index: int in range(SCATTER_OFFSETS.size()): # 场景顺序固定为大飞溅、小飞溅和三片碎雪。
		var piece: Sprite2D = _pieces.get_child(index) as Sprite2D # 只改变已有贴图的位置，不重采样或绘制图像。
		tween.tween_property(piece, ^"position", piece.position + SCATTER_OFFSETS[index], LIFETIME_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, ^"modulate:a", 0.0, LIFETIME_SECONDS).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
