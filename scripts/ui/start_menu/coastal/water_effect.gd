extends RefCounted
## 水面算法与独立周期适配器；不拥有船体、岸线或场景光照。
## 数值转换复用同一类型校验，不吞掉拼写错误。
const Values=preload("res://scripts/ui/start_menu/coastal/effect_uniforms.gd")
## 已实现的算法编号；新增算法只扩展水面include和此映射。
const PATTERNS: Dictionary={"drift":0,"ripples":1,"still":2}
## 材质属于当前场景实例。
var material: ShaderMaterial
## 水面参数快照；空配置保持现有算法。
var settings: Dictionary={}
## 未指定独立周期时沿用原6秒配置，不改变已批准效果。
var default_period := 6.0
## 原水面与船共用的初始相位，仅作为兼容默认值。
var default_phase := 0.0

## [param data] 是水面算法配置；返回空字符串才可提交。
static func validate(data: Variant) -> String:
	if not data is Dictionary:
		return "water必须为对象"
	for key: String in data: # 允许字段是明确API，不自动接受shader任意参数。
		if key not in ["pattern","period_seconds","phase_radians","transverse_ratio","shimmer_scale","ripple_center","ripple_spacing","ripple_cycles"]:
			return "未知water参数："+key
	if not PATTERNS.has(data.get("pattern","drift")):
		return "未知水面算法"
	for key: String in ["period_seconds","phase_radians","transverse_ratio","ripple_spacing","ripple_cycles"]:
		if data.has(key) and not Values.finite_number(data[key]):
			return "water."+key+"必须为有限数值"
	if data.has("period_seconds") and (float(data.period_seconds)<.05 or float(data.period_seconds)>3600.0):
		return "water.period_seconds超界"
	if absf(float(data.get("transverse_ratio",.32)))>1.0:
		return "water.transverse_ratio须在-1到1之间"
	if float(data.get("ripple_spacing",35.0))<2.0 or absf(float(data.get("ripple_cycles",2.0)))>32.0:
		return "水面波长或频率超界"
	for key: String in ["shimmer_scale","ripple_center"]:
		if data.has(key):
			var decoded: Dictionary=Values.decode(data[key],TYPE_VECTOR3 if key=="shimmer_scale" else TYPE_VECTOR2) # 检查向量维数和有限值。
			if not decoded.ok:
				return key+"："+str(decoded.error)
			if key=="shimmer_scale" and (decoded.value.x<1.0 or decoded.value.y<1.0 or decoded.value.z<1.0):
				return "shimmer_scale分量须大于等于1像素"
	return ""

## [param data] 已通过validate；只提交本效果拥有的uniform，不改水域蒙版。
func apply(data: Dictionary) -> void:
	settings=data.duplicate(true)
	var scale_values: Array=settings.get("shimmer_scale",[37.0,9.0,21.0]) # 原亮纹空间尺度。
	var center: Array=settings.get("ripple_center",[1567.0,419.0]) # 原图像素坐标。
	var parameters: Dictionary={"water_pattern":PATTERNS[settings.get("pattern","drift")],"water_transverse_ratio":float(settings.get("transverse_ratio",.32)),"water_shimmer_scale":Vector3(scale_values[0],scale_values[1],scale_values[2]),"ripple_origin":Vector2(center[0],center[1]),"ripple_spacing":float(settings.get("ripple_spacing",35.0)),"ripple_cycles":float(settings.get("ripple_cycles",2.0))} # 不触碰船体相位。
	for key: String in parameters:
		material.set_shader_parameter(key,parameters[key])

## [param seconds] 为显式动作秒数；改水周期不会改变船、旗或风的相位。
func set_elapsed(seconds: float) -> void:
	var period: float=float(settings.get("period_seconds",default_period)) # 单位秒，已验证正数。
	var phase: float=fposmod(seconds/period,1.0)*TAU+float(settings.get("phase_radians",default_phase)) # 不读取全局TIME。
	material.set_shader_parameter("water_angle",phase)
