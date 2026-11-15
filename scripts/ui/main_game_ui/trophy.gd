## 奖杯点击时收取战场掉落，白屏演出结束后通知本局离场。
extends Node2D
class_name Trophy

## 点击奖杯到白屏完成的时长（游戏秒）。
const WHITEOUT_SECONDS := 5.0

## 奖杯所属的战斗。
@onready var main_game: MainGameManager

## 未拾取时在奖杯后方脉动的光晕。
@onready var pick_up_glow: Sprite2D = $PickUpGlow

## 拾取后出现的旋转光束。
@onready var all_rays: Node2D = $AllRays
## 最终覆盖战场的白光。
@onready var glow: Node2D = $Glow
## 按钮禁用后忽略重复的奖杯拾取请求。
@onready var trophy_button: TextureButton = $TrophyButton

## 播放奖杯待机光晕，并按玩法决定是否立即保存原版进度。
func _ready():
	main_game = get_tree().current_scene
	var tween: Tween = create_tween() # 待机光晕的循环补间。
	tween.tween_property(pick_up_glow, "scale", Vector2(1.5, 1.5), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(pick_up_glow, "scale", Vector2(1, 1), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.set_loops()  # 无限循环
	# 僵尸岛通关由独立状态服务结算，奖杯生成时不写入原版进度。
	if not AdventureSession.owns_battle(main_game.game_para):
		Global.save_service.save_now()

## 先整批收取普通掉落，再在白屏演出中收取保底物品和首通钱币。
func _on_trophy_button_pressed() -> void:
	if trophy_button.disabled:
		return
	trophy_button.disabled = true
	var tween_glow: Tween = create_tween() # 掉落收取与白屏共用时间轴，暂停和倍速保持同步。
	tween_glow.tween_property(glow, "modulate:a", 1.0, WHITEOUT_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	main_game.drop_item_manager.start_victory_collection(tween_glow)
	SoundManager.play_other_SFX("winmusic")
	var center: Vector2 = get_viewport().get_visible_rect().size / 2 + main_game.camera_2d.global_position # 奖杯移向画面中心。
	var tween: Tween = create_tween() # 奖杯向屏幕中央移动的补间。
	tween.tween_property(self, "position", center, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	all_rays.visible = true
	for ray: Node2D in all_rays.get_children(): # 每束光独立旋转并放大。
		var tween_rays1: Tween = create_tween() # 光束旋转一周的补间。
		tween_rays1.tween_property(ray, "rotation", ray.rotation + TAU, WHITEOUT_SECONDS) \
			.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)

		var tween_rays2: Tween = create_tween() # 光束逐渐放大到覆盖场地的补间。
		tween_rays2.tween_property(ray, "scale", Vector2(10, 10), WHITEOUT_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	glow.visible = true
	await tween_glow.finished
	main_game.drop_item_manager.finish_victory_collection()
	EventBus.push_event("win_main_game")


## 锤子模式中悬停奖杯时显示鼠标，方便点击。
func _on_trophy_button_mouse_entered() -> void:
	## 如果有锤子
	if main_game.game_para.is_hammer:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
