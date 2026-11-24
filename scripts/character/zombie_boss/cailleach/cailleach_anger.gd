## 凯莱赫「愠怒」的一次完整施法。真实暴雪、近镜雪和眼部星芒按同一关键帧推进。
extends Node

## 白影消退并归还画面后，通知本体解除免伤与继续计时。
signal finished

## 复用战斗的全局瞬间泛白与离焦。
const Whiteout = preload("res://scripts/fx/battle_whiteout.gd")
## 愠怒专用的两层近镜雪。
const AngerSnow = preload("res://scripts/character/zombie_boss/cailleach/cailleach_anger_snow.gd")
## 从实际亮眼射出的光，位于人物原画前方、HUD 后方。
const EYE_FLARE: Shader = preload("res://shaders/adventure/wonderland/cailleach_anger_eye.gdshader")
## 杖击现有的高频星闪与爆鸣。愠怒只取音轨，眼光和风雪都有独立表演。
const STAR_CUE: String = "res://resources/adventure/audio/cailleach_staff_impact.ogg"
## 二阶段图集实际亮眼的归一化中心。
const EYE_UV := Vector2(0.480, 0.225)
## 从起雪到星爆的动作秒数。
const IMPACT_AT: float = 2.85
## 星爆后的风雪至少持续这么多动作秒，技能尚未结束时可以继续保持。
const PEAK_HOLD: float = 0.67
## 从回落到完全显形的慢速收势，单位动作秒。
const SETTLE_SECONDS: float = 3.22

## 启动时确认的正式战斗，用于当前镜头、风向与结算身份。
var _battle: MainGameManager
## 本阶段在天幕与雪脊之间的实际人物，提供每帧白眼的屏幕位置。
var _pose: AnimatedSprite2D
## 已完成源图去白边的原画材质，演出仅暂时向它写入白影权重。
var _portrait: ShaderMaterial
## 常驻雪脊卷雾材质，施法时增厚后再恢复。
var _ridge: ShaderMaterial
## 此次随机技能在眼部星爆时执行的结算；允许返回可等待的异步工作。
var _effect: Callable
## 近处激雪使用的真实本场天气。
var _weather: SnowEnvironmentController
## 两个不同距离的附加雪层。
var _snow: AngerSnow
## 屏幕位置随眼睛更新的局部星芒平面。
var _eye: ColorRect
## 从起势经过的动作秒。
var _age: float = 0.0
## 进入平息后累计的动作秒。
var _settle_age: float = 0.0
## 星爆只发布一次，即使在技能结算中触发其他同步事件。
var _struck: bool = false
## 技能回调已返回或其异步结算已结束。
var _effect_finished: bool = false
## 停止后异步完成不再改变任何一帧。
var _stopped: bool = false

## [param battle] 提供原暴雪和镜头。[param pose] 为原画节点，[param portrait] 与 [param ridge] 为本体材质。
## [param effect] 在星爆同一游戏帧调用，并在其结束后允许风雪回落。
func _init(battle: MainGameManager, pose: AnimatedSprite2D, portrait: ShaderMaterial,
		ridge: ShaderMaterial, effect: Callable) -> void:
	_battle = battle
	_pose = pose
	_portrait = portrait
	_ridge = ridge
	_effect = effect
	_weather = battle.background_manager.snow_environment
	name = "CailleachAnger"

## 用短阵风猛烈抬起本关暴雪，再让缓慢的白影出现在天气里。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_weather.play_wind_burst(Vector2(-1170.0, 124.0), IMPACT_AT + 0.22, 0.22)
	_snow = AngerSnow.new(_weather)
	add_child(_snow)
	var optics := CanvasLayer.new() # 星芒是眼部在空气里的光，近处大雪仍能从它前方掠过。
	optics.layer = 5
	add_child(optics)
	var material := ShaderMaterial.new() # 只在视口内由眼睛带动这一小块发光平面。
	material.shader = EYE_FLARE
	_eye = ColorRect.new()
	_eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye.material = material
	_eye.hide()
	optics.add_child(_eye)

## 将 [param delta] 按原画行动倍率换算为动作秒。技能和星爆尾峰完成后才切入收势。
func _process(delta: float) -> void:
	if _stopped:
		return
	if not is_instance_valid(_battle) or _battle.is_queued_for_deletion() \
			or _battle.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		_end()
		return
	var step: float = minf(delta, 0.12) * _pose.speed_scale # 与本体同步，保留掉帧时的关键帧顺序。
	_age += step
	if not _struck and _age >= IMPACT_AT:
		_impact()
		if _stopped:
			return
	if _effect_finished and _age >= IMPACT_AT + PEAK_HOLD:
		_settle_age = minf(SETTLE_SECONDS, _settle_age + step)
	_present()
	if _settle_age >= SETTLE_SECONDS:
		_end()

## 在技能点拍白屏、点亮眼部星芒、起风、起音，并立刻消费一次回调。
func _impact() -> void:
	_struck = true
	var origin: Vector2 = _eye_origin() # 白闪中心使用已经投影过的原画亮眼。
	_weather.play_wind_burst(Vector2(-2050.0, -31.0), PEAK_HOLD + SETTLE_SECONDS)
	_battle.camera_2d.shake_once(Vector2(12.0, 18.5), 0.49, 15.2)
	var flash := Whiteout.new() # 眼部高光领先极短一拍，随后冷白几乎盖住整个画面。
	flash.configure(origin, 0.76, 0.995, 0.044, 0.81)
	add_child(flash)
	var stream: AudioStream = load(STAR_CUE) as AudioStream # 复用尖锐星爆音色，稍抬音高以区别脚边冲击。
	if stream != null:
		var cue := AudioStreamPlayer.new() # 音轨与施法节点一起暂停或释放。
		cue.stream = stream
		cue.bus = SoundManager.spatial_sfx_bus(SoundManagerClass.SFXSpace.COMBAT)
		cue.volume_db = -2.2
		cue.pitch_scale = 1.085
		add_child(cue)
		cue.play()
	var invoke: Callable = _effect # 在调用外部技能前先消费，避免重入或重复结算。
	_effect = Callable()
	if invoke.is_valid():
		await invoke.call()
	_effect_finished = true

## 计算当前动画帧构图中实际眼球的屏幕位置，跟随视口缩放与镜头震动。
func _eye_origin() -> Vector2:
	var image: Texture2D = _pose.sprite_frames.get_frame_texture(_pose.animation, _pose.frame) # 原画为居中图集精灵。
	var point: Vector2 = (EYE_UV - Vector2(0.5, 0.5)) * image.get_size() + _pose.offset # 从图集单帧换算至原画局部。
	return _pose.get_global_transform_with_canvas() * point

## 让近镜雪先急涨，人物白影慢半拍稳定，星爆后随技能完成逐层回落。
func _present() -> void:
	var clearing: float = smoothstep(0.0, SETTLE_SECONDS, _settle_age) # 全部曲线在结束处连续归零。
	var shell: float = smoothstep(0.14, 1.50, _age) * (1.0 - smoothstep(0.29, 2.97, _settle_age)) # 让原画先于余雪显现。
	_portrait.set_shader_parameter(&"anger_veil", shell)
	if _ridge != null:
		_ridge.set_shader_parameter(&"anger_veil", shell)
	var snow_fill: float = smoothstep(0.0, 0.32, _age) * (0.76 + 0.24 * smoothstep(2.38, IMPACT_AT, _age)) # 前半秒便能看出雪量变化。
	_snow.present(snow_fill * (1.0 - clearing))
	var burst_age: float = _age - IMPACT_AT # 负值是眼中光点蓄亮的短拍。
	_eye.visible = burst_age >= -0.33 and burst_age < 0.94
	if _eye.visible:
		var scale_px: float = get_viewport().get_visible_rect().size.y # 星芒与实际画面高度成比例。
		_eye.size = Vector2(1.38, 0.67) * scale_px
		_eye.position = _eye_origin() - _eye.size * 0.5
		(_eye.material as ShaderMaterial).set_shader_parameter(&"strike_age", burst_age)

## 归还材质和所有本次表演节点，再通知僵王打开受击窗口。
func _end() -> void:
	stop()
	finished.emit()

## 角色死亡或换场可以立即停止，未到关键帧的回调随之丢弃。
func stop() -> void:
	if _stopped:
		return
	_stopped = true
	set_process(false)
	_effect = Callable()
	_reset_portrait()
	queue_free()

## 还原真实原画与常驻雪脊材质，避免打断时残留白影。
func _reset_portrait() -> void:
	if _portrait != null:
		_portrait.set_shader_parameter(&"anger_veil", 0.0)
	if _ridge != null:
		_ridge.set_shader_parameter(&"anger_veil", 0.0)

## 战场直接移除时不发布结算或收势信号。
func _exit_tree() -> void:
	if not _stopped:
		_reset_portrait()
