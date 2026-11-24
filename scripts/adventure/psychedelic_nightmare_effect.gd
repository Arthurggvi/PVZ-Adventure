## 噩梦天幕与陆地的独立材质导演；地面光固定在格缝，保留原图、格位和原版镜头。
extends Node

## 各组相位的真实秒数周期；使用整数谐波，跨周期没有跳变。
const PERIODS := Vector4(11.0, 19.0, 43.0, 79.0)
## 固定种植地面的美术节点。
@export var ground: Sprite2D
## 与战场分层绘制的天幕节点。
@export var sky: Sprite2D
## 本局独占的陆地灯光材质。
@export var ground_material: ShaderMaterial
## 本局独占的云层与裂隙材质。
@export var sky_material: ShaderMaterial
## 灯光强度，只影响噩梦画面。
@export_range(0.0, 2.0, 0.05) var light_strength: float = 1.0
## 本次进入噩梦后的双精度计时，不受战斗倍速影响。
var elapsed_seconds: float = 0.0
## 防止同一局进入 Boss 时重新启动视觉相位。
var active: bool = false

## 普通阶段保持休眠，实际切入或重开噩梦时才启用。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	_update_phase()

## 按 [param board] 的权威格界安装灯光；不改变地形、格子或相机。
func activate(board: BoardGridDefinition) -> void:
	ground.material = ground_material
	sky.material = sky_material
	var rows := PackedFloat32Array() # 原图中的行界 UV。
	var columns := PackedFloat32Array() # 原图中的列界 UV。
	for edge: float in board.row_edges: # 继承正式噩梦的全部行界。
		rows.append((edge - ground.position.y) / (ground.scale.y * ground.texture.get_height()))
	for edge: float in board.column_edges: # 继承正式噩梦的全部列界。
		columns.append((edge - ground.position.x) / (ground.scale.x * ground.texture.get_width()))
	ground_material.set_shader_parameter("row_edges", rows)
	ground_material.set_shader_parameter("column_edges", columns)
	for material: ShaderMaterial in [ground_material, sky_material]: # 两层使用同一曝光强度。
		material.set_shader_parameter("light_strength", light_strength)
	active = true
	_update_phase()
	set_process(true)

## [param delta] 为引擎帧步长；暂停冻结，二倍速不加快云层和闪光。
func _process(delta: float) -> void:
	elapsed_seconds += delta / maxf(Engine.time_scale, 0.001)
	_update_phase()

## 上传云层相位及点光时钟，不创建粒子节点、计时器或持续增长的纹理缓存。
func _update_phase() -> void:
	var phase := Vector4( # 呼吸、云缝、主云层、远层漂移。
		fposmod(elapsed_seconds, PERIODS.x) / PERIODS.x * TAU,
		fposmod(elapsed_seconds, PERIODS.y) / PERIODS.y * TAU,
		fposmod(elapsed_seconds, PERIODS.z) / PERIODS.z * TAU,
		fposmod(elapsed_seconds, PERIODS.w) / PERIODS.w * TAU)
	ground_material.set_shader_parameter("motion", phase)
	sky_material.set_shader_parameter("motion", phase)
	ground_material.set_shader_parameter("light_clock_seconds", elapsed_seconds)
