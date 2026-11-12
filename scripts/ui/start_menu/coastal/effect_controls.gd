extends RefCounted
## 三个效果的最小门面：完整验证后一起提交；不持有宿主、存档或全局单例。
## 独立效果实现。
const Light=preload("res://scripts/ui/start_menu/coastal/light_behavior.gd")
const Water=preload("res://scripts/ui/start_menu/coastal/water_effect.gd")
## 已有hover实例与两个时间调制适配器。
var hover: RefCounted
var lights := Light.new()
var water := Water.new()
## 最后一次有效配置，快照返回副本防止调用方绕过校验。
var _profile: Dictionary={"schema_version":1,"hover":{},"lights":{},"water":{}}
## 同一动作时间，不由系统时钟或效果模式切换重置。
var _seconds := 0.0

## [param entry] 是已有高亮层；材质及 [param motion] 只提供现有默认周期。
func configure(entry: RefCounted, light_material: ShaderMaterial, water_material: ShaderMaterial, motion: Dictionary) -> void:
	hover=entry
	lights.material=light_material
	water.material=water_material
	water.default_period=float(motion.loop_seconds)
	water.default_phase=float(motion.boat.phase_offset)
	var result: Dictionary=apply_profile(_profile) # 中性默认必须也经过完整路径。
	assert(result.ok,str(result.get("error","Invalid neutral effects")))

## [param data] 是完整效果配置；失败不提交任何分项，返回具体错误。
func apply_profile(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {"ok":false,"error":"effect_profile必须为对象"}
	for key: String in data:
		if key not in ["schema_version","hover","lights","water"]:
			return {"ok":false,"error":"未知effect_profile字段："+key}
	if data.get("schema_version",1)!=1:
		return {"ok":false,"error":"不支持的effect_profile版本"}
	var light_error: String=Light.validate(data.get("lights",{})) # 验证先于状态改变。
	if not light_error.is_empty():
		return {"ok":false,"error":light_error}
	var water_error: String=Water.validate(data.get("water",{}))
	if not water_error.is_empty():
		return {"ok":false,"error":water_error}
	var prepared: Dictionary=hover.prepare_effect(data.get("hover",{})) # 新材质仅为候选，不替换当前纹理。
	if not prepared.ok:
		return prepared
	hover.install_effect(prepared)
	lights.groups=data.get("lights",{}).duplicate(true)
	water.apply(data.get("water",{}))
	_profile={"schema_version":1,"hover":data.get("hover",{}).duplicate(true),"lights":lights.groups.duplicate(true),"water":water.settings.duplicate(true)}
	set_elapsed(_seconds)
	return {"ok":true,"profile":snapshot()}

## [param path] 可为res配置或制作副本；读取失败保持上次有效状态。
func reload_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok":false,"error":"效果配置不存在："+path}
	var parser := JSON.new() # 保留具体解析错误，而非强制转成空对象。
	var error: Error=parser.parse(FileAccess.get_file_as_string(path)) # 文件只有一次完整提交。
	if error!=OK:
		return {"ok":false,"error":"效果JSON第%d行：%s"%[parser.get_error_line(),parser.get_error_message()]}
	return apply_profile(parser.data)

## 返回最后一次有效值的深复制；不包含材质或运行节点。
func snapshot() -> Dictionary:
	return _profile.duplicate(true)

## [param effect] 更换hover算法/参数，不重建命中和业务入口。
func set_hover_effect(effect: Dictionary) -> Dictionary:
	var candidate: Dictionary=snapshot() # 仅覆盖指定部分。
	candidate.hover=effect.duplicate(true)
	return apply_profile(candidate)

## [param group] 为已烘焙灯组；[param behavior] 控制该组完整同步波形。
func set_light_behavior(group: String, behavior: Dictionary) -> Dictionary:
	var candidate: Dictionary=snapshot() # 未设置的灯组保持恒定1倍。
	candidate.lights[group]=behavior.duplicate(true)
	return apply_profile(candidate)

## [param effect] 控制水面算法与周期，船体原phase不变。
func set_water_effect(effect: Dictionary) -> Dictionary:
	var candidate: Dictionary=snapshot() # 水面接收蒙版仍由已批准资产定义。
	candidate.water=effect.duplicate(true)
	return apply_profile(candidate)

## [param seconds] 是调用者提供的动画秒数；无帧随机、无后台计时器。
func set_elapsed(seconds: float) -> void:
	if not is_finite(seconds):
		return
	_seconds=seconds
	hover.set_elapsed(seconds)
	lights.set_elapsed(seconds)
	water.set_elapsed(seconds)

## 返回实际可调用入口及拥有关系，不声称可调整未实现的几何功能。
func describe() -> Dictionary:
	return {"schema_version":1,"methods":["reload_file","apply_profile","set_hover_effect","set_light_behavior","set_water_effect","snapshot"],"light_groups":Light.GROUPS.duplicate(),"light_modes":["steady","breathe","flicker","off"],"water_patterns":Water.PATTERNS.keys(),"hover_contract":["entry_mask","strength","accent","effect_seconds"],"clock":"explicit_animation_seconds","topology_changes_require_bake":true}
