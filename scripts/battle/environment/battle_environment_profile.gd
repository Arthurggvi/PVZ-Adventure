## 阶段环境的静态表现参数；不包含地形、种植坐标、关卡编号或音乐控制。
extends Resource
class_name BattleEnvironmentProfile

## 进入环境的渐变秒数，按真实时间推进。
@export_range(0.1, 8.0) var enter_seconds: float = 3.6
## 离开阶段时恢复干净画面和音效的秒数。
@export_range(0.1, 4.0) var exit_seconds: float = 1.0
## 折射上限，以 1920 像素宽画面的像素为单位。
@export_range(0.0, 3.0) var refraction_pixels: float = 1.6
## 整屏水下透镜位移基准，1920 像素宽；包含实体和 UI，0 时不创建透镜及输入映射。
@export_range(0.0, 48.0) var screen_refraction_pixels: float = 0.0
## 背景介质散射的混合量，单位轮廓与 UI 不参与。
@export_range(0.0, 0.6) var haze_strength: float = 0.085
## 实体与镜头之间的薄水层强度；远处略强，UI 不参与柔焦或散射。
@export_range(0.0, 0.3) var veil_strength: float = 0.0
## 距离散射后的深海蓝。
@export var haze_color: Color = Color("0b263c")
## 偶发远方洋流的海青光。
@export var event_color: Color = Color("38bfb7")
## 选择性泛光的起始亮度。
@export_range(0.1, 0.9) var bloom_threshold: float = 0.46
## 小范围柔光与大范围扩散的强度。
@export var bloom_gains := Vector2(0.20, 0.065)
## 小、大光晕的半径，按 1920 像素宽画面换算。
@export var bloom_radii := Vector2(8.0, 38.0)
## 环境事件之间的候选等待时间，单位秒。
@export var event_interval := Vector2(8.0, 20.0)
## 每次候选时机真正发生事件的概率。
@export_range(0.0, 1.0) var event_probability: float = 0.78
## 每次声画事件持续时间范围，单位秒。
@export var event_duration := Vector2(6.0, 9.0)
## 入水后的首次洋流事件延迟，秒；可提前到巨浪内部形成连续声画冲击。
@export_range(0.0, 8.0) var first_event_delay: float = 4.0
## 循环压力底噪；仅该关卡资源引用，不进入全局预加载。
@export var pressure_stream: AudioStream
## 随洋流事件出现的遥远共鸣。
@export var resonance_stream: AudioStream
## 环境底层与事件峰值的播放器音量，受 SFX 总音量再次控制。
@export var pressure_db: float = -22.0
## 将基础水下处理安装到 SFX 总线，覆盖金币、种植、UI 和直接播放器；BGM 始终旁路。
@export var filter_all_sfx: bool = false
## 远方共鸣的峰值音量，实际响度再乘共同事件包络。
@export var resonance_db: float = -17.0
## 近战音效保留部分瞬态，远处声源更沉闷。
@export var combat_cutoff_hz: float = 4800.0
## 近战低通的滚降阶数；较缓的 6 dB 保留啃食、命中高频瞬态的可辨识部分。
@export var combat_filter_db: AudioEffectFilter.FilterDB = AudioEffectFilter.FILTER_12DB
## 补偿基础滤波损失；全局模式覆盖全部 SFX，否则只用于近战，不改玩家音量或音乐。
@export_range(0.0, 6.0) var combat_gain_db: float = 0.0
## 远处声源保留中低频轮廓，单位 Hz。
@export var distant_cutoff_hz: float = 2600.0
## 环境声的低通截止频率。
@export var ambience_cutoff_hz: float = 1500.0
## 近战、远处声源、环境声的湿声预算；全局模式下后两者扣除已共享的近战预算。
@export var reverb_wet := Vector3(0.09, 0.14, 0.18)

## 在正式阶段入口检查有限参数，不创建渲染器或音频节点。
func validate() -> PackedStringArray:
	var errors := PackedStringArray() # 阻止异常资源进入运行时。
	if not is_finite(enter_seconds) or enter_seconds <= 0.0 or not is_finite(exit_seconds) or exit_seconds <= 0.0:
		errors.append("环境渐变时长必须为有限正数。")
	for interval: Vector2 in [event_interval, event_duration]: # 随机范围必须有明确的正上下界。
		if not interval.is_finite() or interval.x <= 0.0 or interval.y < interval.x:
			errors.append("环境事件时间范围非法。")
	for cutoff: float in [combat_cutoff_hz, distant_cutoff_hz, ambience_cutoff_hz]: # Godot 低通允许的频率范围。
		if not is_finite(cutoff) or cutoff < 20.0 or cutoff > 20500.0:
			errors.append("环境低通频率超出可用范围。")
	return errors
