## 天气强度的独立关键帧，时间以所在阶段开始时为零点。
extends Resource
class_name WeatherKeyframe

## 从阶段天气开始到此关键帧的秒数，必须严格递增。
@export_range(0.0, 3600.0, 0.1) var time_seconds: float = 0.0
## 原版雨幕及雨声的归一化强度，0 无雨，1 最强。
@export_range(0.0, 1.0, 0.01) var rain: float = 0.0
## 湿镜头的归一化强度，0 透明，1 使用完整预设。
@export_range(0.0, 1.0, 0.01) var lens: float = 0.0
## 风沙的归一化强度，0 无沙，1 使用完整沙暴预设；与降雨独立。
@export_range(0.0, 1.0, 0.01) var sand: float = 0.0
