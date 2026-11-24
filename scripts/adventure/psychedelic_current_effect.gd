## 致幻洋流的场景内动效时钟。海面与天空共享天光相位，各自独立绘制。
## 材质实例随场景销毁，暂停冻结，重开从初始相位开始，不改变棋盘或原图。
extends Node

## 每组相位的秒数周期，整数谐波在周期边界连续。
const PERIODS := Vector4(18.0, 47.0, 83.0, 137.0)
## 演出速度，与战斗加速倍率独立。
@export_range(0.0, 2.0, 0.05) var motion_speed: float = 1.0
## 海面原画精灵，只修改其本场景材质参数。
@export var sea: Sprite2D
## 天空原画精灵，与海面位于不同背景层。
@export var sky: Sprite2D
## 波浪起伏、折射与细节强度。
@export_range(0.0, 2.0, 0.05) var wave_strength: float = 1.0
## 彩光亮度，使用柔和曝光上限保留颜色。
@export_range(0.0, 2.0, 0.05) var light_strength: float = 1.0
## 青紫粉金光谱的混合权重。
@export_range(0.0, 1.0, 0.05) var color_strength: float = 1.0
## 天空极光与分层云光强度。
@export_range(0.0, 2.0, 0.05) var sky_strength: float = 1.0
## 双精度累计秒数，上传材质前分别取模，长时间运行仍保留运动精度。
var elapsed_seconds: float = 0.0
## 只属于当前战斗的海面材质。
var _sea_material: ShaderMaterial
## 只属于当前战斗的天空材质。
var _sky_material: ShaderMaterial

## 复用权威行界生成视觉保护线；不维护第二份种植或水路数据。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# 场景已声明 resource_local_to_scene，每次进入战斗都有独立材质。
	_sea_material = sea.material as ShaderMaterial
	_sky_material = sky.material as ShaderMaterial
	var game := get_parent() as MainGameManager # 棋盘在父节点进入树时已安装。
	var edges := PackedFloat32Array() # 把世界行界转换成海面原图UV。
	for edge: float in game.game_para.board_definition.row_edges: # 每条行界只在初始化时换算。
		edges.append((edge - sea.position.y) / (sea.scale.y * sea.texture.get_height()))
	_sea_material.set_shader_parameter("row_edges", edges)
	_sea_material.set_shader_parameter("sky_texture", sky.texture)
	_sea_material.set_shader_parameter("wave_strength", wave_strength)
	_sky_material.set_shader_parameter("sky_strength", sky_strength)
	for material: ShaderMaterial in [_sea_material, _sky_material]: # 光色参数使用同一份配置。
		material.set_shader_parameter("light_strength", light_strength)
		material.set_shader_parameter("color_strength", color_strength)
	_update_phase()

## [param delta] 为游戏时间步长；除去战斗倍速，保留暂停和本场景速度配置。
func _process(delta: float) -> void:
	elapsed_seconds += delta / maxf(Engine.time_scale, 0.001) * motion_speed
	_update_phase()

## 只上传四个有界角度，无 Shader TIME 的暂停穿透或周期跳变。
func _update_phase() -> void:
	var phase := Vector4( # 四组连续角度分别驱动浪、流、极光和暖光。
		fposmod(elapsed_seconds, PERIODS.x) / PERIODS.x * TAU,
		fposmod(elapsed_seconds, PERIODS.y) / PERIODS.y * TAU,
		fposmod(elapsed_seconds, PERIODS.z) / PERIODS.z * TAU,
		fposmod(elapsed_seconds, PERIODS.w) / PERIODS.w * TAU)
	_sea_material.set_shader_parameter("motion", phase)
	_sky_material.set_shader_parameter("motion", phase)
