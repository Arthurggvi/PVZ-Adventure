## TMC-112 的屏幕镜片、持续走针和到期单响。
extends CanvasLayer

## 覆盖战场和环境合成，位于续战、暂停和技能 Cut-in 之下。
const BATTLE_FILTER_LAYER := 40
## 技能绑定时才读取专用着色器。
const CLOCK_GLASS := preload("res://shaders/adventure/clockmaker_time_glass.gdshader")
## 机械秒表实录剪成可循环的交替滴答，整个减速期间共用一个播放器。
const STOPWATCH_TICKS: AudioStreamOggVorbis = preload("res://assets/adventure/audio/skills/clockmaker_stopwatch_loop.ogg")
## 立式座钟报时的最后一击及其混响余韵，来源记在 clockmaker_credits.md。
const RELEASE_CHIME := preload("res://assets/adventure/audio/skills/clockmaker_release_chime.ogg")
## 只读取施放时钟，未创建独立的补间或定时器。
const Slowdown = preload("res://scripts/adventure/skills/battle_action_slowdown.gd")

## 当前施放的权威进度。
var _clock: Slowdown
## 此次施放独有的镜片参数，避免改写其他场景或同时存在的材质。
var _glass: ShaderMaterial
## 跟随减速节点存亡的秒表声；自然到期时先停止，再响钟。
var _stopwatch: AudioStreamPlayer

## 绑定 [param clock] 并继承战场暂停。
func _init(clock: Slowdown) -> void:
	_clock = clock
	layer = BATTLE_FILTER_LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE

## 显式重抓已经合成的战场，兼容前面的浪花折射、教堂光照和环境滤镜。
func _ready() -> void:
	_clock.expired.connect(_play_release_chime, CONNECT_ONE_SHOT)
	var capture := BackBufferCopy.new() # 必须紧邻镜片之前复制当前画面。
	capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(capture)
	_glass = ShaderMaterial.new()
	_glass.shader = CLOCK_GLASS
	var screen := ColorRect.new() # 仅绘制画面，让卡槽、快捷键和鼠标继续走原有入口。
	screen.material = _glass
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_glass()
	_stopwatch = AudioStreamPlayer.new()
	_stopwatch.stream = STOPWATCH_TICKS
	_stopwatch.bus = SoundManager.spatial_sfx_bus(SoundManager.SFXSpace.UI)
	_stopwatch.volume_db = -6.0
	add_child(_stopwatch)
	_stopwatch.play()

## [param _delta] 只由减速来源消费，本层按渲染帧读取同一时钟。
func _process(_delta: float) -> void:
	_update_glass()

## 向着色器传入统一的剩余强度和已过战斗秒。
func _update_glass() -> void:
	_glass.set_shader_parameter(&"strength", _clock.slowdown_strength())
	_glass.set_shader_parameter(&"seconds", _clock.elapsed)

## 停止秒表，在当前阶段下播放一次钟鸣与余韵。
func _play_release_chime() -> void:
	_stopwatch.stop()
	var phase: Node = _clock.get_parent() # 阶段续战或离场时释放整个声音节点。
	var chime := AudioStreamPlayer.new() # 由原生播放完成信号清理，暂停时和战场同步。
	chime.stream = RELEASE_CHIME
	chime.bus = SoundManager.spatial_sfx_bus(SoundManager.SFXSpace.UI)
	chime.volume_db = -4.0
	chime.process_mode = Node.PROCESS_MODE_PAUSABLE
	chime.finished.connect(chime.queue_free, CONNECT_ONE_SHOT)
	phase.add_child(chime)
	chime.play()
