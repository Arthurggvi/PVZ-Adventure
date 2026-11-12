extends RefCounted
## 统一时间状态采样，不读取本机时钟；所有区域共享相同参数。

## [param profile] 为含 keyframes 的配置；[param progress] 为 0～1 的预览时段。
## 返回 shader 参数字典，时间超界时钳制到首末关键帧。
static func sample(profile: Dictionary, progress: float) -> Dictionary:
	var keys: Array = profile.keyframes # 按 position 升序存储的关键帧。
	var value := clampf(progress, float(keys[0].position), float(keys[-1].position)) # 有效进度。
	for index in range(keys.size() - 1): # 寻找包含当前进度的区间。
		var left: Dictionary = keys[index] # 区间起点。
		var right: Dictionary = keys[index + 1] # 区间终点。
		if value > float(right.position):
			continue
		var ratio := (value - float(left.position)) / (float(right.position) - float(left.position)) # 区间归一化。
		ratio = ratio * ratio * (3.0 - 2.0 * ratio)
		var result := {} # 本帧全部区域共享的参数。
		for name: String in left.uniforms: # 各关键帧必须提供同一参数集合。
			var a: Variant = left.uniforms[name] # 起点标量或向量。
			var b: Variant = right.uniforms[name] # 终点标量或向量。
			if a is Array:
				var vector := Vector3(float(a[0]), float(a[1]), float(a[2])) # 起点三维值。
				result[name] = vector.lerp(Vector3(float(b[0]), float(b[1]), float(b[2])), ratio)
			else:
				result[name] = lerpf(float(a), float(b), ratio)
		return result
	return {} # 配置不足时由调用者拒绝继续渲染。
