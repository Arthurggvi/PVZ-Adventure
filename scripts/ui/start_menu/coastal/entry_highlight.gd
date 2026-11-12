extends RefCounted
## 建筑视觉层：输入命中与状态不依赖效果算法；可按uniform契约替换材质。
## Shader输入类型验证，失败时不替换当前可用材质。
const Uniforms=preload("res://scripts/ui/start_menu/coastal/effect_uniforms.gd")
## 默认效果保持已批准画面。
const DEFAULT_SHADER := "res://shaders/ui/main_menu/entry_highlight.gdshader"
## 当前场景独占高亮材质与显示节点。
var material: ShaderMaterial
var display: TextureRect
## 基础表现来自entries.style，效果参数不能改业务状态。
var style: Dictionary={}
## 入口对应的可见蒙版；不等同于点击范围。
var masks: Dictionary={}
## 当前入口、目标强度和连续过渡状态。
var active_id := ""
var desired := 0.0
var amount := 0.0
## 当前反馈色；替换算法时保留。
var accent := Vector3(1.0,.86,.58)
## 显式效果时间，与本机日时钟分离。
var effect_seconds := 0.0

## [param host] 提供纹理/视口工厂；[param folder] 为数据根，缺入口配置则透传。
func configure(host: Node, folder: String, source: SubViewport) -> SubViewport:
	if not FileAccess.file_exists(folder.path_join("config/entries.json")):
		return source
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/entries.json"))) # 单一几何与样式来源。
	style=data.style.duplicate(true)
	for entry: Dictionary in data.entries:
		masks[entry.id]=host.texture_file(folder.path_join("entry_assets/"+entry.id+".png"))
	var view: SubViewport=host.make_view(source.size) # 高亮始终位于风/船变换之前。
	display=host.artwork(view,source.get_texture())
	var candidate: Dictionary=prepare_effect({}) # 默认材质也走同一个真实契约。
	assert(candidate.ok,str(candidate.get("error","Invalid default hover")))
	install_effect(candidate)
	return view

## [param effect] 只指定shader与parameters；先准备候选，不修改当前材质或过渡。
func prepare_effect(effect: Variant) -> Dictionary:
	if display==null:
		return {"ok":true,"skip":true} if effect is Dictionary and effect.is_empty() else {"ok":false,"error":"此场景未配置建筑高亮层"}
	if not effect is Dictionary:
		return {"ok":false,"error":"hover必须为对象"}
	for key: String in effect:
		if key not in ["shader","parameters"]:
			return {"ok":false,"error":"未知hover字段："+key}
	if not effect.get("shader",DEFAULT_SHADER) is String or not effect.get("parameters",{}) is Dictionary:
		return {"ok":false,"error":"hover.shader必须为路径，parameters必须为对象"}
	var defaults: Dictionary={"fill_gain":float(style.get("fill_gain",.13)),"inner_edge_gain":float(style.get("inner_edge_gain",.18))} # 替换算法仅继承其声明过的基础参数。
	return Uniforms.prepare(str(effect.get("shader",DEFAULT_SHADER)),effect.get("parameters",{}),defaults)

## [param candidate] 由prepare_effect生成；一次性替换，不重建命中或重新绑定业务信号。
func install_effect(candidate: Dictionary) -> void:
	if candidate.get("skip",false):
		return
	material=candidate.material
	var id: String=active_id if masks.has(active_id) else str(masks.keys()[0]) # 离开时仍保留旧入口的渐出。
	material.set_shader_parameter("entry_mask",masks[id])
	material.set_shader_parameter("strength",amount)
	material.set_shader_parameter("accent",accent)
	material.set_shader_parameter("effect_seconds",effect_seconds)
	display.material=material

## [param id] 为空表示离开；[param mode] 区分权限，[param pressed] 为按下反馈。
func set_target(id: String, mode: String, pressed: bool=false) -> void:
	if material==null:
		return
	if id.is_empty() or not masks.has(id):
		desired=0.0
		return
	if active_id!=id:
		active_id=id
		amount=0.0
		material.set_shader_parameter("strength",amount)
		material.set_shader_parameter("entry_mask",masks[id])
	var rgb: Array=style.available_color if mode=="available" else style.locked_color # 效果替换不能把锁定对象变成可用状态。
	accent=Vector3(rgb[0],rgb[1],rgb[2])
	material.set_shader_parameter("accent",accent)
	desired=(1.0 if mode=="available" else float(style.locked_strength))*(float(style.pressed_multiplier) if pressed else 1.0)

## [param delta] 独立推进悬停强度，不重置其他动画。
func advance(delta: float) -> void:
	if material==null:
		return
	var duration: float=style.fade_in_seconds if desired>amount else style.fade_out_seconds # 保持原渐入/渐出语义。
	amount=move_toward(amount,desired,delta/maxf(duration,.001))
	material.set_shader_parameter("strength",amount)

## [param seconds] 显式控制可动画效果，暂停/回放可重复。
func set_elapsed(seconds: float) -> void:
	effect_seconds=seconds
	if material!=null:
		material.set_shader_parameter("effect_seconds",seconds)
