## 原始逐帧素材的动画适配器；只消费角色状态，不决定伤害、位移或生命。
extends AnimComponentBase
class_name ImportedZombieAnimator

## 真实素材精灵；所有帧已由图集边距对齐至同一脚点。
@onready var _sprite: AnimatedSprite2D = %SourceSprite
## 所属实体使用原僵尸接口，不依赖某个特定物种。
@onready var _zombie: Zombie000Base = owner as Zombie000Base
## 行为组件请求的临时动作；空名称恢复普通走路与啃咬。
var _override: StringName = &""
## 临时动作独有的播放倍率，用来匹配行为组件提供的动作时长。
var _override_playback_rate: float = 1.0
## 当前动画速度，包含原生寒冷、黄油和独立角色技能减速。
var _speed: float = 1.0
## 原生碾压等入口可显式停止播放器，自动状态选择不能将其重启。
var _stopped: bool = false
## 死亡动作只进入一次，终帧只发出一次淡出请求。
var _dying: bool = false
## 防止同一死亡动作的结束通知重复释放实体。
var _fade_requested: bool = false

## 初始化接口与原帧播放器；此时父节点尚未执行自己的ready。
func _ready() -> void:
	animation_origin_speed = 1.0
	_sprite.animation_finished.connect(_finished)
	_zombie.signal_character_death.connect(_begin_death)
	_select(&"idle")

## [param _delta] 由引擎播放器推进；本组件只在角色动作变化时切换一次。
func _process(_delta: float) -> void:
	if _stopped or _dying:
		return
	var clip: StringName = _override # 行为覆盖优先于普通动作，但不能覆盖死亡。
	if clip.is_empty():
		clip = &"idle"
		if _zombie.character_init_type == Character000Base.E_CharacterInitType.IsNorm:
			if _zombie.is_attack:
				clip = &"eat"
			elif _zombie.is_walk and is_instance_valid(_zombie.move_component) and _zombie.move_component.is_move:
				clip = &"walk"
	_select(clip)

## 行为层请求 [param clip]；当前动作仍在播放时保留播放进度，未知名称不替换当前动作。
## [param duration] 为完整动作秒数，非正值沿用资源帧速。
func set_override(clip: StringName, duration: float = 0.0) -> void:
	if _dying or _stopped or not _sprite.sprite_frames.has_animation(clip):
		return
	_override = clip
	_override_playback_rate = clip_duration(clip) / duration if duration > 0.0 else 1.0
	_sprite.play(clip, _override_playback_rate)

## 只撤销行为层的动作选择，不清除其他来源的速度和暂停状态。
func clear_override() -> void:
	_override = &""

## 返回 [param clip] 在一倍速下的完整时长，未知动作返回0秒。
func clip_duration(clip: StringName) -> float:
	var frames: SpriteFrames = _sprite.sprite_frames # 帧时长来自原资源，不假定每个图集条目同长。
	if not frames.has_animation(clip) or frames.get_animation_speed(clip) <= 0.0:
		return 0.0
	var duration: float = 0.0 # 累积去重帧所保留的时间权重。
	for index: int in range(frames.get_frame_count(clip)): # 只读取当前动作，不复制纹理。
		duration += frames.get_frame_duration(clip, index)
	return duration / frames.get_animation_speed(clip)

## [param speed_factor_product] 为角色的合成速率；死亡动作不继承致死前的零速控制。
func owner_update_speed(speed_factor_product: float) -> void:
	_speed = maxf(0.0, speed_factor_product)
	if not _dying and not _stopped:
		_sprite.speed_scale = _speed

## [param speed_scale] 保留既有动画接口，直接换成播放器倍率。
func update_anim_speed_scale(speed_scale: float) -> void:
	owner_update_speed(speed_scale)

## 原生小推车/压扁接管表现后，禁止自动动作把精灵重新播放。
func stop_anim() -> void:
	_stopped = true
	_sprite.pause()

## 切换到 [param clip] 的首帧；同名动作和无效资源不重复播放。
func _select(clip: StringName) -> void:
	var playback_rate: float = _override_playback_rate if clip == _override else 1.0 # 与角色的合成速度相乘。
	if _sprite.animation != clip and _sprite.sprite_frames.has_animation(clip):
		_sprite.play(clip, playback_rate)
	elif not _sprite.is_playing() and not _stopped and not _dying:
		_sprite.play(clip, playback_rate)

## 先占有死亡表现再播放原始倒地帧，不能复活或改写伤害结算。
func _begin_death() -> void:
	if _dying:
		return
	_dying = true
	_override = &""
	_sprite.speed_scale = 1.0
	if not _stopped:
		_sprite.play(&"death")

## 转发原动画接口，并在真实死亡动作结束后走原生淡出回收。
func _finished() -> void:
	var clip: StringName = _sprite.animation # 信号订阅者可能改变动画，因此先保留当前名字。
	_on_animation_finished(clip)
	if clip == &"death" and _dying and not _fade_requested:
		_fade_requested = true
		_zombie._fade_and_remove()
