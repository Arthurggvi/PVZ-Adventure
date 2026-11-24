## 炮口、落地和空爆共享暖色闪光、火星与逐渐散开的烟团。
extends Node2D
class_name CannonTurretBurst

## Particle Pack 的 smoke_08 和 flare_01 缩小后用于世界粒子。
## Kenney，CC0 1.0，[url=https://kenney.nl/assets/particle-pack]原始素材[/url]。
const SMOKE_TEXTURE: Texture2D = preload("res://assets/adventure/zombies/cannon_turret/fx_smoke.png")
## 同一素材包的柔边高光供火星和尾焰共用。
const FLARE_TEXTURE: Texture2D = preload("res://assets/adventure/zombies/cannon_turret/fx_flare.png")
## 沿用项目原声，通过炮塔专用的相对增益留出混音余量。
const LAUNCH_SOUND: AudioStream = preload("res://assets/audio/SFX/plant/coblaunch.ogg")
## 空爆与落地使用同一声源，播放时分开设置音高和增益。
const IMPACT_SOUND: AudioStream = preload("res://assets/audio/SFX/zombie/explosion.ogg")
## 相对增益为 dB。地爆稍重，空爆更轻、更短。
const LAUNCH_GAIN: float = -6.5
## 落地爆炸保留比炮口略重的平均响度。
const GROUND_GAIN: float = -8.5
## 高频空爆与落地冲击使用不同响度。
const AIR_GAIN: float = -11.0

## 每种事件拥有独立的表现预算与粒子配方。
enum Kind { Launch, Ground, Air }

## 当前表演种类，自生成至回收保持不变。
var _kind: Kind
## 表演经过的战斗秒数，驱动火光和压力环。
var _age: float = 0.0
## 保留到全部粒子消散的场景时长。
var _lifetime: float
## 本次爆心处的世界横向气流，未注入风的战场为零。
var _aft: float = 0.0


## 在 [param game] 的效果层播放 [param kind]。[param at] 是世界爆心。
## [param direction] 是出膛轴线，落地和空爆使用固定世界朝向。
static func play(game: MainGameManager, kind: Kind, at: Vector2, direction: Vector2 = Vector2.RIGHT) -> void:
	match kind:
		Kind.Launch:
			SoundManager.play_world_sfx(LAUNCH_SOUND, game, at, LAUNCH_GAIN, 0.98, &"cannon_fire", true, 2)
		Kind.Ground:
			SoundManager.play_world_sfx(IMPACT_SOUND, game, at, GROUND_GAIN, 0.94, &"cannon_burst", true, 3)
		Kind.Air:
			SoundManager.play_world_sfx(IMPACT_SOUND, game, at, AIR_GAIN, 1.16, &"cannon_burst", true, 3)
	var key := StringName("cannon_turret_burst_%d" % kind) # 三种粒子分别合并邻近的同帧重叠。
	if not game.blast_fx_budget.can_start(key, at):
		return
	var burst := CannonTurretBurst.new() # 粒子留在世界中，炮塔后坐和弹体释放不会拖走旧烟。
	burst._kind = kind
	game.bombs.add_child(burst)
	burst.global_position = at
	burst.global_rotation = direction.angle() if kind == Kind.Launch else 0.0
	if is_instance_valid(game.world_wind):
		burst._aft = game.world_wind.wind_for_visual(at).x
		if kind != Kind.Launch:
			game.world_wind.shed_fragments(at)
	game.blast_fx_budget.track(burst, key, at)
	burst._emit()


## 启动短火星与慢烟团，采用同一纹理组区分冲量和扩散速度。
func _emit() -> void:
	var launch: bool = _kind == Kind.Launch # 炮口是轴向喷射，其他两种以爆心散开。
	var ground: bool = _kind == Kind.Ground # 触地碎屑偏向上方，余烟更大。
	_lifetime = 1.19 if ground else (0.87 if launch else 0.78)
	var sparks := ParticleProcessMaterial.new() # 高频明亮火星先离开爆心。
	sparks.particle_flag_disable_z = true
	sparks.direction = Vector3.RIGHT if launch else Vector3(0.0, -1.0, 0.0)
	sparks.spread = 25.0 if launch else (105.0 if ground else 180.0)
	sparks.initial_velocity_min = 72.0 if ground else 64.0
	sparks.initial_velocity_max = 218.0 if launch else (190.0 if ground else 136.0)
	sparks.gravity = Vector3(_aft * 0.42, 108.0 if ground else 48.0, 0.0)
	sparks.damping_min = 88.0
	sparks.damping_max = 144.0
	sparks.angle_min = -26.0
	sparks.angle_max = 26.0
	sparks.scale_min = 0.14 if launch else 0.13
	sparks.scale_max = 0.39 if ground else (0.46 if launch else 0.36)
	sparks.color_ramp = _ramp(Color(1.0, 0.90, 0.52), Color(1.0, 0.40, 0.12, 0.92), Color(0.60, 0.19, 0.07, 0.0))
	_spawn_particles(FLARE_TEXTURE, sparks, 30 if ground else (20 if launch else 17), 0.42 if ground else 0.32, true)

	var smoke := ParticleProcessMaterial.new() # 烟团先受冲量推开，再停滞和扩散。
	smoke.particle_flag_disable_z = true
	smoke.direction = Vector3.RIGHT if launch else Vector3(0.0, -1.0, 0.0)
	smoke.spread = 36.0 if launch else (95.0 if ground else 178.0)
	smoke.initial_velocity_min = 25.0 if launch else 19.0
	smoke.initial_velocity_max = 99.0 if launch or ground else 61.0
	smoke.gravity = Vector3(_aft * 0.86, -19.0, 0.0)
	smoke.damping_min = 32.0
	smoke.damping_max = 61.0
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	smoke.angular_velocity_min = -34.0
	smoke.angular_velocity_max = 39.0
	smoke.scale_min = 0.31 if ground else 0.19
	smoke.scale_max = 0.70 if ground else (0.54 if launch else 0.43)
	smoke.scale_curve = _growth_curve()
	smoke.color_ramp = _ramp(Color(0.97, 0.69, 0.43, 0.87), Color(0.44, 0.38, 0.32, 0.94), Color(0.27, 0.25, 0.24, 0.0))
	_spawn_particles(SMOKE_TEXTURE, smoke, 17 if ground else (10 if launch else 9), _lifetime - 0.04, false)
	queue_redraw()


## 以 [param texture]、[param motion] 启动 [param count] 个粒子。
## [param duration] 为粒子寿命，[param additive] 用于要叠亮的火星。
func _spawn_particles(texture: Texture2D, motion: ParticleProcessMaterial, count: int, duration: float,
		additive: bool) -> void:
	var emitter := GPUParticles2D.new() # 世界坐标独立推进，使用一次曝光后随父节点清理。
	emitter.position.x = 9.0 if _kind == Kind.Launch else 0.0
	emitter.texture = texture
	emitter.process_material = motion
	emitter.amount = count
	emitter.lifetime = duration
	emitter.explosiveness = 0.94
	motion.lifetime_randomness = 0.22
	emitter.visibility_rect = Rect2(-240.0, -210.0, 490.0, 450.0)
	emitter.one_shot = true
	emitter.emitting = false
	if additive:
		var blend := CanvasItemMaterial.new() # 火星加亮，烟团沿用正常透明混合。
		blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		emitter.material = blend
		emitter.z_index = 1
	add_child(emitter)
	emitter.emitting = true


## 将 [param start]、[param middle]、[param finish] 转换为粒子寿命上的渐变。
static func _ramp(start: Color, middle: Color, finish: Color) -> GradientTexture1D:
	var gradient := Gradient.new() # 快速由高温过渡到扩散阶段。
	gradient.offsets = PackedFloat32Array([0.0, 0.27, 1.0])
	gradient.colors = PackedColorArray([start, middle, finish])
	var texture := GradientTexture1D.new() # Godot 粒子按年龄连续采样。
	texture.gradient = gradient
	texture.width = 64
	return texture


## 返回供炮口与爆炸烟团共用的扩散曲线。
static func _growth_curve() -> CurveTexture:
	var curve := Curve.new() # 新生烟团小，扩散后接近设置的完整尺度。
	curve.add_point(Vector2(0.0, 0.28))
	curve.add_point(Vector2(0.44, 0.77))
	curve.add_point(Vector2(1.0, 1.0))
	var texture := CurveTexture.new() # 低分辨率足够表达平滑的体积扩散。
	texture.width = 64
	texture.curve = curve
	return texture


## [param delta] 为战斗秒数，压力环消退后只保持粒子。
func _process(delta: float) -> void:
	var was_visible: bool = _age < 0.48 # 短闪和压力环消失后无需继续提交绘制命令。
	_age += delta
	if _age >= _lifetime:
		queue_free()
	elif was_visible:
		queue_redraw()


## 炮口画一道轴向火舌与向前推开的压力环，爆炸画放射状高亮与前沿。
func _draw() -> void:
	if _age >= 0.48:
		return
	var launch: bool = _kind == Kind.Launch # 炮口始终朝局部右侧。
	var ground: bool = _kind == Kind.Ground # 地爆压扁压力环，让接地点容易辨认。
	var flash: float = 1.0 - smoothstep(0.0, 0.16 if launch else 0.27, _age) # 高亮只占冲量开头几帧。
	if launch and flash > 0.0:
		# 大焰和白热芯随炮口同步，外沿比核心晚一拍消失。
		draw_colored_polygon(PackedVector2Array([Vector2(-3, -8), Vector2(14, -13), Vector2(42, -4),
			Vector2(53, 0), Vector2(30, 7), Vector2(13, 11), Vector2(-3, 8)]), Color(1.0, 0.52, 0.13, flash * 0.88))
		draw_colored_polygon(PackedVector2Array([Vector2(-2, -5), Vector2(12, -7), Vector2(38, 0),
			Vector2(11, 6), Vector2(-2, 5)]), Color(1.0, 0.92, 0.59, flash))
	elif flash > 0.0:
		var radius: float = (36.0 if ground else 22.0) * (1.0 - exp(-15.0 * (_age + 0.045))) # 火团迅速扩张。
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.55, 0.15, flash * 0.66), true, -1.0, true)
		draw_circle(Vector2.ZERO, radius * 0.58, Color(1.0, 0.90, 0.62, flash * 0.85), true, -1.0, true)
	var wave: float = 1.0 - pow(1.0 - clampf(_age / 0.48, 0.0, 1.0), 2.0) # 压力前沿先快后慢。
	var ring := Color(1.0, 0.73, 0.37, pow(1.0 - wave, 1.1) * 0.84) # 扩散时逐渐透出背景。
	if launch:
		draw_arc(Vector2(11.0 + wave * 9.0, 0.0), 10.0 + wave * 30.0, -0.94, 0.94, 28, ring, 1.7, true)
	else:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.52 if ground else 0.87))
		draw_arc(Vector2.ZERO, 12.0 + wave * (83.0 if ground else 47.0), 0.0, TAU, 48, ring, 2.2, true)
		draw_set_transform(Vector2.ZERO)
