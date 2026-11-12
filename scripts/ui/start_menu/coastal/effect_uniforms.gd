extends RefCounted
## 效果材质的输入契约：先验证完整配置，再创建独立实例，避免拼错参数却静默无效。

## [param value] 是否为有限数值；不把bool或字符串当浮点数。
static func finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

## [param value] 转换为声明的 [param kind]；失败返回带error的字典，不提交材质。
static func decode(value: Variant, kind: int) -> Dictionary:
	if kind==TYPE_FLOAT and finite_number(value):
		return {"ok":true,"value":float(value)}
	if kind==TYPE_INT and finite_number(value) and float(value)==floor(float(value)):
		return {"ok":true,"value":int(value)}
	if kind==TYPE_BOOL and value is bool:
		return {"ok":true,"value":value}
	if kind in [TYPE_VECTOR2,TYPE_VECTOR3,TYPE_VECTOR4]:
		if typeof(value)==kind and value.is_finite():
			return {"ok":true,"value":value}
		var length: int=2 if kind==TYPE_VECTOR2 else (3 if kind==TYPE_VECTOR3 else 4) # JSON向量维数。
		if value is Array and value.size()==length:
			for component: Variant in value: # 每个分量均必须有限。
				if not finite_number(component):
					return {"ok":false,"error":"向量包含非有限数值"}
			if length==2:
				return {"ok":true,"value":Vector2(value[0],value[1])}
			if length==3:
				return {"ok":true,"value":Vector3(value[0],value[1],value[2])}
			return {"ok":true,"value":Vector4(value[0],value[1],value[2],value[3])}
	return {"ok":false,"error":"参数类型不匹配，声明类型="+str(kind)}

## [param path] 为仓内Shader；[param parameters] 仅开放效果参数，不覆盖输入/状态。
## [param defaults] 是原样式的可选参数；仅在新Shader声明它们时继承。
static func prepare(path: String, parameters: Dictionary, defaults: Dictionary) -> Dictionary:
	if not path.begins_with("res://shaders/ui/main_menu/") or not ResourceLoader.exists(path):
		return {"ok":false,"error":"效果材质不存在或不在菜单材质目录："+path}
	var shader: Shader=ResourceLoader.load(path,"Shader",ResourceLoader.CACHE_MODE_IGNORE) as Shader # 避免复用别的实例参数。
	if shader==null or shader.get_mode()!=Shader.MODE_CANVAS_ITEM:
		return {"ok":false,"error":"资源不是CanvasItem Shader："+path}
	var uniforms: Dictionary={} # 实际材质声明，而非手写猜测参数表。
	for property: Dictionary in shader.get_shader_uniform_list():
		uniforms[str(property.name)]=int(property.type)
	var required: Dictionary={"entry_mask":TYPE_OBJECT,"strength":TYPE_FLOAT,"accent":TYPE_VECTOR3,"effect_seconds":TYPE_FLOAT} # 输入与时间状态由控制器持有。
	for key: String in required:
		if uniforms.get(key,-1)!=required[key]:
			return {"ok":false,"error":"hover材质缺少约定参数："+key}
	var values: Dictionary={} # 只接收被实际Shader消费的默认参数。
	for key: String in defaults:
		if uniforms.has(key):
			values[key]=defaults[key]
	for key: String in parameters:
		if required.has(key) or not uniforms.has(key):
			return {"ok":false,"error":"不可写或未知hover参数："+key}
		values[key]=parameters[key]
	var decoded: Dictionary={} # 全量转换完成后再实例化，不留半更新状态。
	for key: String in values:
		var result: Dictionary=decode(values[key],uniforms[key]) # 类型由材质自身决定。
		if not result.ok:
			return {"ok":false,"error":key+"："+str(result.error)}
		decoded[key]=result.value
	var material := ShaderMaterial.new() # 每个菜单独立，不改共享资源。
	material.shader=shader
	for key: String in decoded:
		material.set_shader_parameter(key,decoded[key])
	return {"ok":true,"material":material,"parameters":decoded,"shader":path}

## [param data] 为日周期值，[param uniforms] 是实际声明；水面权重由另一材质接收。
static func scene_values(data: Dictionary, uniforms: Dictionary) -> Dictionary:
	var converted: Dictionary={} # 验证完成之前不触碰材质。
	for key: String in data:
		if key=="water_time_gain": # 唯一由宿主显式分流的时段字段。
			continue
		if key in ["local_group_energy","emission_group_energy","halo_group_energy"] or not uniforms.has(key):
			return {"ok":false,"error":"日周期含未知或非所属参数："+key}
		var result: Dictionary=decode(data[key],int(uniforms[key])) # 接收真实类型，拒绝NaN/维数错误。
		if not result.ok:
			return {"ok":false,"error":key+"："+str(result.error)}
		converted[key]=result.value
	return {"ok":true,"values":converted}
