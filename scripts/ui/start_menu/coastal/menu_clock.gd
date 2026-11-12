extends RefCounted
## 菜单专用显示时钟：当地时间决定光照，动作时间由宿主独立推进。
## 唯一环形插值器。
const Cycle=preload("res://scripts/ui/start_menu/coastal/daily_cycle.gd")
## 可编辑日周期配置，不含玩家状态。
var config: Dictionary
## 可注入的当地小时来源，生产默认读系统当地时间。
var source: Callable
## 是否由制作/验收手动指定时刻。
var manual := false
## 当前显示对应的真实或手动小时。
var current_hour := 0.0
## 当前输出及跨时钟跳变的起点。
var values: Dictionary={}
var _from: Dictionary={}
var _target: Dictionary={}
## 自上次采样/过渡启动的累计秒数。
var _sample_age := 0.0
var _blend_age := 0.0

## [param settings] 定义日周期；[param reader] 可替换当地时间来源，启动立即给正确状态。
func configure(settings: Dictionary, reader: Callable=Callable()) -> void:
	config=settings
	source=reader
	resync(true)

## 返回本机当地小时，不请求网络、位置或时区服务。
static func local_hour() -> float:
	var now := Time.get_time_dict_from_system(false) # false指系统当地时间，不是UTC。
	return float(now.hour)+float(now.minute)/60.0+float(now.second)/3600.0

## [param immediate] 用于初次进入或显式预览；普通系统时钟变化平滑改参数而非快放时段。
func resync(immediate: bool=false) -> void:
	if manual:
		return
	current_hour=fposmod(float(source.call()) if source.is_valid() else local_hour(),24.0)
	_from=values.duplicate()
	_target=Cycle.sample(config,current_hour)
	_blend_age=0.0
	_sample_age=0.0
	if immediate or values.is_empty():
		values=_target.duplicate()
		_from=values.duplicate()
		_blend_age=float(config.resync_seconds)

## [param delta] 只推进显示过渡；不回写系统时间，也不修改动作相位。
func advance(delta: float) -> Dictionary:
	if manual:
		return values
	_sample_age+=delta
	if _sample_age>=float(config.poll_seconds):
		resync(false)
	_blend_age=minf(_blend_age+delta,float(config.resync_seconds))
	var blend := _blend_age/maxf(float(config.resync_seconds),.001) # 跨暂停/调钟的显示过渡。
	blend=blend*blend*(3.0-2.0*blend)
	values=Cycle.blend(_from,_target,blend)
	return values

## [param hour] 指定制作时刻；关闭手动模式调用use_local，不改变实际电脑时间。
func set_manual_hour(hour: float) -> void:
	manual=true
	current_hour=fposmod(hour,24.0)
	values=Cycle.sample(config,current_hour)

## 恢复系统当地时钟；默认平滑接回，避免跳过中间的参数更新。
func use_local() -> void:
	manual=false
	resync(false)
