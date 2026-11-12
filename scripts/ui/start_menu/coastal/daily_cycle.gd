extends RefCounted
## 环形24小时采样；只产出显示参数，绝不影响任务、存档或战斗时间。

## [param config] 的关键帧按hour升序；[param hour] 可超界，午夜自动环绕。
static func sample(config: Dictionary, hour: float) -> Dictionary:
	var keys: Array=config.keyframes # 已保存的美术关键状态。
	assert(keys.size()>=2)
	var value := fposmod(hour,24.0) # 23:59与00:00在同一圆环上。
	for index: int in keys.size(): # 最后一项接次日第一项。
		var left: Dictionary=keys[index]
		var right: Dictionary=keys[(index+1)%keys.size()]
		var begin := float(left.hour) # 当前段起点。
		var end := float(right.hour)+(24.0 if index==keys.size()-1 else 0.0)
		var point := value+(24.0 if value<begin and index==keys.size()-1 else 0.0)
		if point<begin or point>end:
			continue
		var ratio := (point-begin)/(end-begin) # 区间内平滑、首尾导数为零。
		ratio=ratio*ratio*(3.0-2.0*ratio)
		return blend(decode(left.uniforms),decode(right.uniforms),ratio)
	return decode(keys[0].uniforms)

## [param source] 将JSON三元素数组转换为shader向量；返回新字典，不改配置。
static func decode(source: Dictionary) -> Dictionary:
	var result := {} # 本帧独立值。
	for key: String in source:
		var value: Variant=source[key] # 标量或三元组。
		result[key]=Vector3(value[0],value[1],value[2]) if value is Array else float(value)
	return result

## [param a]、[param b] 具有相同键；按 [param weight] 在参数空间重校时钟，避免快放一天。
static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var result := {} # 返回可直接提交材质的值。
	for key: String in b:
		assert(a.has(key),"Daily cycle inconsistent parameter: "+key)
		result[key]=a[key].lerp(b[key],weight) if b[key] is Vector3 else lerpf(float(a[key]),float(b[key]),weight)
	return result
