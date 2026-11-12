extends RefCounted
## 局部灯光时间调制；只乘已烘焙光场，不改日周期、源图或玩家时间。
## 浮点RGBA通道的既有顺序，增加独立灯组需先重建对应技术资产。
const GROUPS: Array[String]=["home","library","shop","research"]
## 复用有限数值校验。
const Values=preload("res://scripts/ui/start_menu/coastal/effect_uniforms.gd")
## 每组的完整参数快照，空配置代表恒定1倍。
var groups: Dictionary={}
## 宿主独占材质；不持有宿主引用或全局计时器。
var material: ShaderMaterial

## [param data] 为按组命名的配置；返回错误说明，空字符串表示可提交。
static func validate(data: Variant) -> String:
	if not data is Dictionary:
		return "lights必须为对象"
	for group: String in data: # 只能操作已发布四个通道。
		if not GROUPS.has(group) or not data[group] is Dictionary:
			return "未知灯组或参数不是对象："+group
		var item: Dictionary=data[group] # 仅查看，不修改调用方。
		for key: String in item:
			if key not in ["mode","minimum","maximum","period_seconds","phase"]:
				return group+"包含未知参数："+key
		if item.get("mode","steady") not in ["steady","breathe","flicker","off"]:
			return group+"的mode不受支持"
		for key: String in ["minimum","maximum","period_seconds","phase"]:
			if item.has(key) and not Values.finite_number(item[key]):
				return group+"."+key+"必须为有限数值"
		var minimum: float=float(item.get("minimum",1.0)) # 默认保留现有效果。
		var maximum: float=float(item.get("maximum",1.0))
		var period: float=float(item.get("period_seconds",4.0)) # 单位为动作秒，不是本机小时。
		if minimum<0.0 or maximum<minimum or maximum>8.0 or period<.05 or period>3600.0:
			return group+"强度或周期超界"
	return ""

## [param seconds] 是同一显式动作时钟；计算确定性倍率，不累加帧误差。
func energies(seconds: float) -> Vector4:
	var result := Vector4.ONE # 没有配置的组保持中性。
	for index: int in GROUPS.size():
		var item: Dictionary=groups.get(GROUPS[index],{}) # 四组共享同一算法。
		var mode: String=str(item.get("mode","steady"))
		var maximum: float=float(item.get("maximum",1.0)) # steady使用maximum作常量倍率。
		var minimum: float=float(item.get("minimum",1.0))
		var angle: float=TAU*(fposmod(seconds/float(item.get("period_seconds",4.0)),1.0)+float(item.get("phase",0.0))) # phase单位为周期。
		var weight := 1.0 # 完全恒定模式。
		if mode=="breathe":
			weight=.5-.5*cos(angle)
		elif mode=="flicker":
			weight=.5+.25*sin(angle)+.15*sin(3.0*angle)+.1*sin(7.0*angle) # 有界、可回放，不用逐帧随机。
		result[index]=0.0 if mode=="off" else lerpf(minimum,maximum,weight)
	return result

## [param seconds] 统一驱动受光、窗灯与光晕；不会让只有地面呼吸而窗口不动。
func set_elapsed(seconds: float) -> void:
	var value: Vector4=energies(seconds) # 三层使用相同四通道倍率。
	for uniform: String in ["local_group_energy","emission_group_energy","halo_group_energy"]:
		material.set_shader_parameter(uniform,value)
