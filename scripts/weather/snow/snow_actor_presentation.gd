## 本局角色表现输入。天气控制器供时和供风，原登记器决定哪些角色接收。
extends Node

## 接触暗部和雪缘各自按战场深度批绘制。
const Footing = preload("res://scripts/weather/snow/snow_footing.gd")
## 颜色和抖雪蓄积的采样间隔，单位为游戏秒。
const SAMPLE_INTERVAL: float = 0.10
## 一次天气采样允许抖落的植株和僵尸总数。
const MAX_SHEDS: int = 2

## 当前天气推进获取的实际风，单位世界像素/秒。
var wind: Vector2 = Vector2.ZERO
## 归一化的阵风脉冲，供角色抖雪与地面薄雪共用。
var gust: float = 0.0
## 每游戏秒的粉雪蓄积变化，停雪后减淡抖雪。
var deposition_rate: float = 0.0
## 本步用于颜色和抖雪蓄积的游戏秒数，零表示沿用上次样本。
var sample_seconds: float = 0.0
## 低频更新的 RGB 环境乘数，透明度恒为 1。
var tint: Color = Color.WHITE
## 是否允许更多的抖雪颗粒。
var high_quality: bool = false
## 本局地板颜色和风雪配置。
var _profile: SnowVisualProfile
## 累计至下一次采样的游戏秒数，首帧取当前天气。
var _pending: float = SAMPLE_INTERVAL
## 本样本尚可提交的脱落次数，超额立即舍弃。
var _sheds_left: int = 0
## 植物和僵尸共用原有的短寿命抖雪池。
var _flurries: SnowPlantFlurries
## 集中管理的足底表现，地板痕迹仍由 SnowSurface 管理。
var footing: Footing

## 用本场 [param profile] 配置颜色，接触绘制读取 [param surface] 与 [param game] 的真实行。
func configure(profile: SnowVisualProfile, surface: SnowSurface, game: MainGameManager) -> void:
	_profile = profile
	_flurries = SnowPlantFlurries.new()
	add_child(_flurries)
	footing = Footing.new()
	add_child(footing)
	footing.configure(surface, game)

## [param delta] 为天气步秒数，[param snowfall] 为归一化降雪，[param world_wind] 为世界像素/秒。
## [param weather] 与世界雪共用能见度损失、阵风、地吹雪和雪墙相位。
## [param aurora] 是受云遮蔽的极弱环境色，[param fine] 是本场质量档。
func begin_step(delta: float, snowfall: float, world_wind: Vector2, weather: Vector4, aurora: Color, fine: bool) -> void:
	wind = world_wind
	gust = weather.y
	high_quality = fine
	footing.begin_step(wind.x, gust)
	_pending += delta
	sample_seconds = 0.0
	if _pending < SAMPLE_INTERVAL:
		return
	sample_seconds = minf(_pending, 0.25)
	_pending = 0.0
	_sheds_left = MAX_SHEDS
	deposition_rate = snowfall * (0.062 + snowfall * 0.025) if snowfall > 0.003 else -0.019
	var cold: Color = _profile.actor_snow_tint.lerp(_profile.actor_storm_tint, weather.x) # 随现有能见度损失加深色温。
	cold = Color.WHITE.lerp(cold, smoothstep(0.0, 0.20, snowfall + weather.x)) # 停雪时逐渐回到中性。
	var glow: float = minf(aurora.a, 0.055) * 0.35 # 沿用天空已衰减的权重，最多产生不到 2% 的偏色。
	cold.g = lerpf(cold.g, 1.0, glow)
	cold.r *= 1.0 - glow * (1.0 - aurora.r)
	tint = tint.lerp(cold, 1.0 - exp(-6.0 * sample_seconds))

## 若本天气样本仍有预算，从 [param point] 释放共享粉雪。成功时返回 true。
func shed(point: Vector2) -> bool:
	if _sheds_left <= 0 or not point.is_finite():
		return false
	_sheds_left -= 1
	_flurries.shed(point, wind, high_quality)
	return true

## 提交两类角色的接触批次并推进共用粉雪，[param delta] 为本次天气步的游戏秒数。
func finish_step(delta: float) -> void:
	footing.finish_step()
	_flurries.advance(delta, wind, high_quality)
