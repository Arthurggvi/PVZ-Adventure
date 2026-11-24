## 融合体艺术层：更新翻滚原画、形变和接触锚点，并播放尘土与声音。
extends Node
class_name LargeFusionPresentation

## 正常翻滚每秒切换的原画帧数；十二帧每三分之二秒完整循环。
const ROLL_FPS: float = 18.0
## 疲劳减速只适度降低动作节奏，仍至少每秒播放十二个清晰原画帧。
const MIN_ROLL_FPS: float = 12.0
## 仅跨帧末尾混合十八毫秒，且不超过单张原画周期的百分之三十二。
const FRAME_BLEND_SECONDS: float = 0.018
## 各帧有厚度下缘到图块中心的原图像素距离，按每行至少十六个不透明像素量测。
const FRAME_FOOT_PIXELS: Array[float] = [161.0, 159.0, 159.0, 160.0, 157.0, 157.0,
	160.0, 157.0, 156.0, 156.0, 156.0, 157.0]
## 碾压锚点到厚实足沿的高度，单位为原图像素。
const CRUSH_HEIGHT_PIXELS: float = 52.0
## 各帧下部前缘到图块中心的距离，取足沿上方 40–64 原图像素内连续实心轮廓的最小值，再内收 2 像素。
const FRAME_CRUSH_FRONT_PIXELS: Array[float] = [105.0, 109.0, 106.0, 85.0, 117.0, 94.0,
	90.0, 109.0, 115.0, 115.0, 112.0, 122.0]
## 稀疏滚尘的最小行程，避免按帧生成粒子。
const DUST_SPACING: float = 29.0
## 仅通过通用僵尸接口读取移动和身体状态。
var _source: Zombie000Base
## 攻击组件只发布一次性状态事件。
var _roller: AttackComponentZombieLargeFusion
## 独立音频所有者，离场清理不影响其他角色。
var _audio: LargeFusionAudio
## 唯一被压缩和逐帧播放的艺术精灵，短混合由同一材质完成。
var _sprite: Sprite2D
## 跟随精灵当前姿态的下部前缘，供攻击组件读取。
var _crush_front: Marker2D
## 仍贴在脚点的阴影，不随原生飞行抬高。
var _shadow: Sprite2D
## 每个实例独立的表面材质，避免图鉴和战斗相互修改。
var _surface: ShaderMaterial
## 精灵初始姿态，用作所有短时形变的合成基准。
var _base_position: Vector2
## 原画基础显示比例，保留迷你模式的父级缩放。
var _base_scale: Vector2
## 阴影基础尺寸与透明度。
var _shadow_scale: Vector2
## 阴影原调色，不改写场景提供的色相。
var _shadow_color: Color
## 连续帧相位，十二回零时不重置动作。
var _phase: float = 0.0
## 最近一次真实移动的原画节奏；没有物理位移的渲染帧不重算混合窗口。
var _cadence: float = ROLL_FPS
## 上一帧真实横坐标，仅读取而不校正角色位置。
var _last_x: float = 0.0
## 累计未发尘的地面行程。
var _dust_distance: float = 0.0
## 当前短撞击、落地与分裂的独立衰减量。
var _impact: float = 0.0
## 距离落地的时间；负值表示本轮尚未落地。
var _landing_age: float = -1.0
## 分裂瞬间的躯体鼓胀，不推开碰撞框。
var _split: float = 0.0
## 耗尽时渐变到低伏姿态，归零速度仍保留缓慢呼吸。
var _rest: float = 0.0
## 局部表现时钟，继承战场暂停。
var _age: float = 0.0
## 死亡后只允许子代显形，母体不再写任何艺术通道。
var _dead: bool = false

## 未配置的展示模板不读取全局战场或播放声音。
func _ready() -> void:
	set_process(false)

## [param source]、[param roller]、[param brood] 和 [param audio] 均属于同一个角色实例。
func configure(source: Zombie000Base, roller: AttackComponentZombieLargeFusion,
		brood: LargeFusionBrood, audio: LargeFusionAudio) -> void:
	_source = source
	_roller = roller
	_audio = audio
	_sprite = source.get_node(^"Body/FusionSprite") as Sprite2D
	_crush_front = _sprite.get_node(^"CrushFront") as Marker2D
	_shadow = source.shadow
	_surface = _sprite.material.duplicate() as ShaderMaterial
	_sprite.material = _surface
	_base_position = _sprite.position
	_base_scale = _sprite.scale
	_shadow_scale = _shadow.scale
	_shadow_color = _shadow.modulate
	_last_x = source.global_position.x
	roller.crush_contact.connect(_on_impact)
	roller.rebound_started.connect(_on_launch)
	roller.rebound_landed.connect(_on_land)
	roller.rolling_exhausted.connect(_on_exhaust)
	brood.child_spawned.connect(_on_child)
	set_process(true)

## [param delta] 仅推进表现；地面停步时不会继续把球体原画播放成空转。
func _process(delta: float) -> void:
	if _dead or not is_instance_valid(_source):
		return
	var displacement: float = _last_x - _source.global_position.x # 向左前进为正，后抛时自然反向翻滚。
	_last_x = _source.global_position.x
	var airborne: bool = _roller.is_rebounding() # 原生飞行仍由攻击组件计算。
	var exhausted: bool = _roller.is_exhausted() # 零移速不会使呼吸或落地尾巴停摆。
	var display: bool = _source.character_init_type != Character000Base.E_CharacterInitType.IsNorm # 图鉴有独立慢速预览。
	var base_speed: float = maxf(_source.move_component.ori_speed, 0.001) # 跟随场景基础移速，不保留旧速度常量。
	if display:
		displacement = delta * base_speed
	var speed_ratio: float = absf(displacement) / maxf(delta * base_speed, 0.001) # 仅用于节奏和音量，不控制实际位移。
	_age += delta
	_impact = move_toward(_impact, 0.0, delta * 5.5)
	_split = move_toward(_split, 0.0, delta * 3.8)
	_rest = move_toward(_rest, 1.0 if exhausted else 0.0, delta * 3.4)
	if _landing_age >= 0.0:
		_landing_age += delta
	if airborne:
		_cadence = ROLL_FPS
		_phase = fposmod(_phase - float(_source.direction_x_root) * delta * _cadence * _source.action_rate(), 12.0) # 后抛按游戏时间反向，不受物理与渲染频率差影响。
	elif absf(displacement) > 0.001 and absf(displacement) < 40.0 and not exhausted:
		_cadence = lerpf(MIN_ROLL_FPS, ROLL_FPS, minf(speed_ratio, 1.0)) # 地面只由真实位移开启，减速仍保留清晰原画节奏。
		_phase = fposmod(_phase + signf(displacement) * delta * _cadence, 12.0)
	var visible_frame: int = _sync_frame(exhausted) # 过渡时使用占优原画的下缘。
	_surface.set_shader_parameter(&"hit_strength", maxf(_impact * 0.70, _split * 0.38))
	_pose(airborne, visible_frame)
	if not display:
		_audio.update_roll(speed_ratio, airborne, exhausted)
		if not airborne and not exhausted:
			_dust_distance += absf(displacement)
			if _dust_distance >= DUST_SPACING:
				_dust_distance = fmod(_dust_distance, DUST_SPACING)
				LargeFusionDust.trail(_source.get_parent() as Node2D, _source.global_position + Vector2(31.0, 0.0))

## [param freeze] 在耗尽或死亡时收束到占优原画，避免停驻和尸体永久留下双重五官。
## 返回当前占优的原画帧号，便于跟随可见轮廓。
func _sync_frame(freeze: bool) -> int:
	var frame: int = floori(_phase) # 主原画仍由唯一连续相位决定。
	var next_frame: int = (frame + 1) % 12 # 正反向和十二到一的边界使用同一对原画。
	var window: float = minf(_cadence * FRAME_BLEND_SECONDS, 0.32) # 其余至少百分之六十八时间保持原画完整。
	var blend: float = smoothstep(1.0 - window, 1.0, fposmod(_phase, 1.0)) # 只在跨帧末尾柔化。
	var visible_frame: int = next_frame if blend >= 0.5 else frame # 以透明度更高的原画确定轮廓。
	if freeze:
		frame = visible_frame
		_phase = float(frame)
		next_frame = (frame + 1) % 12
		blend = 0.0
	_sprite.frame = frame
	_surface.set_shader_parameter(&"next_frame", next_frame)
	_surface.set_shader_parameter(&"frame_mix", blend)
	_surface.set_shader_parameter(&"next_foot_offset", (FRAME_FOOT_PIXELS[next_frame] - FRAME_FOOT_PIXELS[frame]) / 384.0)
	return visible_frame

## [param airborne] 控制空中形变与阴影；[param visible_frame] 决定接触锚点的轮廓。
func _pose(airborne: bool, visible_frame: int) -> void:
	var rolling_wave: float = sin(_phase * TAU / 6.0) * (1.0 - _rest) # 一周两个软体受压重心。
	var breath: float = sin(_age * 3.1) * _rest # 停驻后的低频轻微起伏。
	var land: float = 0.0 if _landing_age < 0.0 else exp(-_landing_age * 9.0) * cos(_landing_age * 23.0) # 接地后一次阻尼回弹。
	var impact_squeeze: float = 0.13 * _impact # 撞击导致的横向收缩量。
	var air_stretch: Vector2 = Vector2(0.95, 1.055) if airborne else Vector2.ONE # 空中仍保留原有抛飞姿态。
	var stretch: Vector2 = Vector2(1.0 + rolling_wave * 0.018, 1.0 - rolling_wave * 0.023) # 保留原图轮廓，只作轻微压缩。
	stretch += Vector2(-impact_squeeze, 0.07 * _impact) + Vector2(0.045, 0.055) * _split
	stretch += Vector2(0.18, -0.16) * land + Vector2(0.10 + breath * 0.012, -0.12 + breath * 0.018) * _rest
	# 过渡的两张原画在 shader 中对齐足沿，因此纵向沿用主原画的足沿基准。
	_crush_front.position = Vector2(-FRAME_CRUSH_FRONT_PIXELS[visible_frame],
		FRAME_FOOT_PIXELS[_sprite.frame] - CRUSH_HEIGHT_PIXELS)
	var impact_shift: float = _crush_front.position.x * _base_scale.x * air_stretch.x * impact_squeeze # 收缩时保持前缘贴住命中点。
	_sprite.scale = _base_scale * stretch * air_stretch
	_sprite.position = Vector2(_base_position.x + impact_shift, -FRAME_FOOT_PIXELS[_sprite.frame] * _sprite.scale.y)
	var height: float = maxf(0.0, (_source.to_global(_source.body.pose_position) - _source.body.global_position).y) if airborne else 0.0 # 只有原生后抛会拉开身体和阴影。
	var lift: float = clampf(height / 80.0, 0.0, 1.0) # 阴影在离地最高点最小且最淡。
	_shadow.scale = _shadow_scale * Vector2(lerpf(1.0, 0.66, lift) + land * 0.13, lerpf(1.0, 0.72, lift))
	_shadow.modulate = _shadow_color * Color(1.0, 1.0, 1.0, lerpf(1.0, 0.38, lift))

## [param point] 是扣血前快照的接触脚点，伤害回调删除植物也不会丢失落尘位置。
func _on_impact(point: Vector2) -> void:
	_impact = 1.0
	LargeFusionDust.emit_ground(_source.get_parent() as Node2D, point, 0.85, LargeFusionDust.Kind.IMPACT)
	_audio.play_event(&"impact")

## 起抛只发一次声音，姿态与阴影继续读取实际高度。
func _on_launch() -> void:
	_landing_age = -1.0
	_audio.play_event(&"launch")

## 真正落地才产生扩散土尘和重落声，第三次同样完整播完尾部。
func _on_land() -> void:
	_landing_age = 0.0
	LargeFusionDust.emit_ground(_source.get_parent() as Node2D, _source.global_position, 1.0, LargeFusionDust.Kind.LANDING)
	_audio.play_event(&"land")

## 耗尽的持续低伏姿态在过程函数渐变，短收气只发一次。
func _on_exhaust() -> void:
	_audio.play_event(&"exhaust")

## [param child] 已成功登记；死亡后代也显形，但不会重新启动母体的翻滚或声音。
func _on_child(child: Zombie000Base) -> void:
	LargeFusionBirthReveal.present(child)
	if not _dead:
		_split = 1.0
		_audio.play_event(&"split")

## 在原生飞行归零前复制当前艺术姿态；母体死亡和子代登记仍立即执行。
func release_death_visual() -> void:
	if _dead:
		return
	_sync_frame(true)
	_sprite.position.y = -FRAME_FOOT_PIXELS[_sprite.frame] * _sprite.scale.y # 死亡收束只校正所选原画脚点，保留当前伸缩和阴影姿态。
	_dead = true
	if _source.character_init_type == Character000Base.E_CharacterInitType.IsNorm and not _source.retiring_from_battle:
		LargeFusionDeathEffect.capture(_source, _sprite, _shadow)
		_audio.play_event(&"death")
	_audio.stop_all()
	_sprite.hide()
	_shadow.hide()
	_source.hp_component.hide()
	set_process(false)
