## 显示战斗提示，并在刷怪前按顺序播放大波与末波红字。
extends Control
class_name UIRemindWord

## 初代 PC 冒险模式旗帜波的预警总时长，单位为游戏秒。
const CLASSIC_FLAG_WARNING_SECONDS: float = 7.5

@onready var ready_plant: TextureRect = $Ready
@onready var set_plant: TextureRect = $Set
@onready var plant: TextureRect = $Plant
## 每次大波前显示的红字。
@onready var approaching: TextureRect = $Approaching
## 仅在末波前、且大波提示结束后显示的红字。
@onready var final_wave: TextureRect = $FinalWave
@onready var zombies_won: TextureRect = $ZombiesWon


## 准备放置植物
func ready_set_plant() -> void:
	visible = true
	SoundManager.play_other_SFX("readysetplant")
	for node in [ready_plant, set_plant, plant]:
		node.visible = true
		await get_tree().create_timer(0.6, false).timeout  # 等待 1 秒
		node.visible = false
	visible = false


## 播放大波提示；[param final] 为真时接着播放最后一波提示。
## [param classic_timing] 为真时，大波与末波的总预警都采用初代 PC 冒险模式时长。
## 动效包含在原有刷怪等待中，战斗暂停时与波次倒计时一起停止。
func zombie_approach(final: bool, classic_timing: bool = false) -> void:
	show()
	SoundManager.play_other_SFX("hugewave")
	# 参照 TextFadeOn 的 12 FPS 素材，从约两倍大小收至原尺寸，尾段淡出。
	await _animate_wave_word(approaching, 4.0, 2.003, 19.0 / 12.0, 4.0 / 12.0)
	# 经典模式把末波红字计入预警总时长；其他关卡沿用 2 秒过渡。
	var gap_seconds: float = 2.0 # 大波红字与末波红字之间的等待。
	if classic_timing:
		gap_seconds = CLASSIC_FLAG_WARNING_SECONDS - 4.0 - (3.0 if final else 0.0)
	await get_tree().create_timer(gap_seconds, false).timeout
	if final:
		SoundManager.play_other_SFX("finalwave")
		# 参照 FinalWave 素材使用更大的入场倍率和更快的收缩。
		await _animate_wave_word(final_wave, 3.0, 3.905, 8.0 / 12.0, 0.25)
	hide()

## [param word] 以中心为轴，从 [param start_scale] 倍缩回原尺寸。
## [param enter_seconds] 和 [param exit_seconds] 是首尾动效的游戏秒数，计入 [param total_seconds]。
func _animate_wave_word(word: TextureRect, total_seconds: float, start_scale: float,
		enter_seconds: float, exit_seconds: float) -> void:
	word.pivot_offset = word.size * 0.5
	word.scale = Vector2.ONE * start_scale
	word.modulate.a = 0.0
	word.show()
	var motion: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP) # 跟随战斗暂停与游戏倍率。
	motion.tween_property(word, "scale", Vector2.ONE, enter_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	motion.parallel().tween_property(word, "modulate:a", 1.0, enter_seconds)
	motion.tween_interval(total_seconds - enter_seconds - exit_seconds)
	motion.tween_property(word, "modulate:a", 0.0, exit_seconds)
	await motion.finished
	word.hide()

## 僵尸获胜
func zombie_won_word_appear() -> void:
	approaching.hide()
	final_wave.hide()
	visible = true
	zombies_won.visible = true
	#await get_tree().create_timer(0.8).timeout  # 等待 1 秒
	#zombies_won.visible = false
	#visible = false
