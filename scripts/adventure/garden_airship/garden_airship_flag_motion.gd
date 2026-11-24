## 用本局风场驱动布料折波，保留挂点和渐变速度。时间来自自然飞行秒。
extends RefCounted

## 本关已有的按实际甲板坐标采样的风场。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 三条红带、四幅蓝旗及船尾小旗的挂点。横坐标包含船框加宽，单位为战场世界像素。
const ANCHORS: Array[float] = [6.0, 837.0, 1360.0, 774.0, 1337.0, 98.0, 1324.0, 1473.0]
## 轻红带、厚蓝旗及较小旗尾各自的风力响应时间，单位为秒。
const LAGS: Array[float] = [0.025, 0.04, 0.045, 0.09, 0.10, 0.13, 0.14, 0.065]

## 各片布的相位以周期为单位。快慢风可连续切换，浮点相位不无限增长。
var _cycles := PackedFloat32Array([0.12, 0.33, 0.68, 0.54, 0.22, 0.80, 0.39, 0.91])
## 缓存同一帧实际采样的局部风力，复用固定缓冲区。
var _loads := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## 上次写入材质的平均张力，避免静止时重复提交。
var _last_tension: float = -1.0

## 向 [param material] 提交 [param wind]、自然步长 [param step] 与显示权重 [param amount]。
## 每处布料独立积分，减弱动效时同时调低幅度和折波速率。
func apply(material: ShaderMaterial, wind: Wind, step: float, amount: float) -> void:
	var tempo: float = lerpf(0.58, 1.0, amount) # 减弱动效仍保留风速间的可见差异。
	for index: int in ANCHORS.size(): # 只处理当前飞艇已有的八个挂点。
		var load: float = wind.strength_at(ANCHORS[index], LAGS[index]) # 局内真实风，而非布料自造的全局脉冲。
		var surge: float = smoothstep(0.20, 0.98, load) # 巡航频率已可读，高风段逐渐加密。
		var frequency: float = lerpf(0.73, 3.58, surge) * tempo # 单位为周期每秒。
		_cycles[index] = fposmod(_cycles[index] + frequency * step, 1.0)
		_loads[index] = load
	material.set_shader_parameter(&"ribbon_phase", Vector3(_cycles[0], _cycles[1], _cycles[2]))
	material.set_shader_parameter(&"ribbon_wind", Vector3(_loads[0], _loads[1], _loads[2]))
	material.set_shader_parameter(&"pennant_phase", Vector4(_cycles[3], _cycles[4], _cycles[5], _cycles[6]))
	material.set_shader_parameter(&"pennant_wind", Vector4(_loads[3], _loads[4], _loads[5], _loads[6]))
	material.set_shader_parameter(&"rail_pennant", Vector2(_cycles[7], _loads[7]))
	material.set_shader_parameter(&"cloth_amount", amount)
	var tension: float = minf(0.34, wind.cruise_load * 0.47) # 平均姿态更拉紧，褶波仍由各挂点的局部风压控制。
	if absf(tension - _last_tension) > 0.002:
		material.set_shader_parameter(&"cruise_tension", tension)
		_last_tension = tension
