## 雪山的美术和风场预设，仅保存静态配置。
extends Resource
class_name SnowVisualProfile

## 常态选卡和无阶段时间轴时的落雪、雪风、云量。
@export var initial_channels := Vector3(0.27, 0.19, 0.15)
## 主风方向，世界坐标向左为负。
@export var wind_direction := Vector2(-1.0, 0.12)
## 弱风与满风之间的移动速度，单位世界像素每秒。
@export var wind_speed := Vector2(24.0, 238.0)
## 普通雪与暴雪的向下速度范围，单位世界像素每秒。
@export var fall_speed := Vector2(78.0, 112.0)
## 世界雪墙和雪粒的冷灰散射颜色，与阶段能见度配合。
@export var haze_color := Color(0.70, 0.76, 0.80)
## 普通雪中的角色 RGB 乘色，保留原有状态颜色及透明度。
@export var actor_snow_tint: Color = Color(0.95, 0.975, 0.995)
## 雪墙最密时的色温上限，空间遮蔽仍由世界雪层绘制。
@export var actor_storm_tint: Color = Color(0.91, 0.95, 0.985)
## 镜头飘雪与 HUD 共用的冷白色，颜色透明度由镜头材质统一限制。
@export var lens_tint := Color(0.863, 0.902, 0.918)
## 镜头整面轻调色的透明度上限，不等于局部雪掠强度。
@export_range(0.0, 0.18, 0.001) var lens_frost_alpha: float = 0.09
## 无极光、无山体的完整底图，可保留固定远云。
@export var sky_without_aurora: Texture2D
## 同画布对齐的稳定山体层，天空范围透明。
@export var mountains: Texture2D
## 可独立采样的低饱和极光 RGBA 透明带或图集。
@export var aurora_ribbon: Texture2D
## 极光条带在源图中的归一化 UV 范围，整张独立条带使用默认值。
@export var aurora_region := Rect2(0.0, 0.0, 1.0, 1.0)
## 可选的透明高云，水平无缝平移以遮挡极光。
@export var storm_clouds: Texture2D
## 普通雪的连续风声，导入时启用循环。缺暴雪专用素材时也用于较强风雪。
@export var wind_loop: AudioStream
## 强风雪的连续风声，随现有阶段目标与普通风声渐变。导入时启用循环。
@export var blizzard_wind_loop: AudioStream

## 只有明确提供无极光底图、对齐山体和独立条带时才启用动态极光。
func has_aurora_layers() -> bool:
	return sky_without_aurora != null and mountains != null \
		and sky_without_aurora.get_size() == mountains.get_size() and aurora_ribbon != null
