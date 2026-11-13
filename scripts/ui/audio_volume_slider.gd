## 音量滑块，将线性音量实时应用到指定总线并保存到玩家配置。
extends HSlider

## 音频总线名称，应与项目的音频总线布局一致。
@export var bus_name: StringName = &"BGM"
## 总线在 AudioServer 中的索引，未找到时为 -1。
var _bus_index: int = -1

## 初始化音量范围，并在控件重新显示时读取总线的最新值。
func _ready() -> void:
	_bus_index = AudioServer.get_bus_index(bus_name)
	if _bus_index < 0:
		editable = false
		push_warning("找不到音频总线：" + String(bus_name))
		return
	max_value = 1.0
	step = 0.01
	_refresh_volume()
	visibility_changed.connect(_refresh_volume)
	value_changed.connect(_apply_volume)

## 读取当前音量，不触发写入配置。
func _refresh_volume() -> void:
	if is_visible_in_tree():
		set_value_no_signal(clampf(SoundManager.get_volum(_bus_index), 0.0, 1.0))

## 将 [param volume] 应用到总线并保存到当前档案。
func _apply_volume(volume: float) -> void:
	SoundManager.set_volume(_bus_index, volume)
	Global.config_service.save_config()
