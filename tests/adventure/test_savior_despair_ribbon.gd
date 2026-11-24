## 验证绝望的合批光束、照明锚点、弧长映射及动画期间的几何稳定性。
extends SceneTree

## 正式场景中生成流光几何的组件。
const MESH_SCRIPT := "res://scripts/fx/savior_despair_meteor_mesh.gd"
## 流光对外提交弧长进度的正式材质。
const RIBBON_SHADER := "res://shaders/adventure/wonderland/savior_despair_meteor.gdshader"

## 等游戏 Autoload 完成初始化后实例化正式组件。
func _initialize() -> void:
	call_deferred("_run")

## 捕获丢失流光批次、四条带串接、尾端偏离实际格心和逐帧重建。
func _run() -> void:
	if not ResourceLoader.exists(MESH_SCRIPT) or not ResourceLoader.exists(RIBBON_SHADER):
		_fail("正式绝望还没有弧长流光组件")
		return
	var script: GDScript = load(MESH_SCRIPT) # 与教堂场景使用同一生成器。
	if script == null or not script.can_instantiate():
		_fail("无法加载正式弧长流光组件")
		return
	var ribbon = script.new() # 运行正式网格构建而非测试中的近似实现。
	var material := ShaderMaterial.new() # Headless 仍可以读取提交给材质的实际参数。
	material.shader = load(RIBBON_SHADER)
	ribbon.material = material
	root.add_child(ribbon)
	var landings := PackedVector2Array([Vector2(114, 242), Vector2(483, 310), Vector2(617, 427), Vector2(910, 275)]) # 四个不同格心。
	ribbon.begin(landings, 64.0)
	var mesh: ArrayMesh = ribbon.mesh # 检查真正上传的芯带顶点及索引。
	if mesh.get_surface_count() != 1:
		_fail("四条流光没有共用一个表面")
		return
	var arrays: Array = mesh.surface_get_arrays(0) # Godot 实际保存的网格属性。
	var positions: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX] # 2D Canvas 的真实坐标。
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] # 连续弧长及横截面。
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] # 每个三角形只属于一条流光。
	@warning_ignore("integer_division")
	var strip_size: int = positions.size() / landings.size() # 单束全部横截面占用的顶点数。
	if strip_size < 34 or strip_size > 50 or positions.size() != strip_size * landings.size():
		_fail("四条带的弧长采样没有覆盖 16–24 段预算")
		return
	for index: int in range(landings.size()): # 每条流光都应接到自己的实际格心。
		var last: int = (index + 1) * strip_size - 1 # 最后的左右顶点。
		if not ((positions[last] + positions[last - 1]) * 0.5).is_equal_approx(landings[index]) or absf(uvs[last].x - 1.0) > 0.001:
			_fail("流光尾端几何没有接到世界落点")
			return
		var first: int = index * strip_size # 光束的拱顶截面和触地截面都须留有宽度。
		if positions[first].distance_to(positions[first + 1]) < 28.0 or positions[last].distance_to(positions[last - 1]) < 32.0:
			_fail("整束光需要保留约半格宽的截面")
			return
	for index: int in range(0, indices.size(), 3): # 索引范围独立，移过屏幕时不会出现跨格三角形。
		@warning_ignore("integer_division")
		var strip: int = indices[index] / strip_size # 本面片的归属。
		if not range(strip * strip_size, (strip + 1) * strip_size).has(indices[index + 1]) or not range(strip * strip_size, (strip + 1) * strip_size).has(indices[index + 2]):
			_fail("流光索引跨束连接")
			return
	ribbon.present(0.44, 0.85)
	var early_front: Vector2 = ribbon.front(0) # 与光带同步下移的红光世界锚点。
	var early: Vector4 = material.get_shader_parameter(&"head_arc") # 实际用于裁开光头的弧长，而非曲线参数。
	ribbon.present(0.72, 0.85)
	var late_front: Vector2 = ribbon.front(0) # 后半段在同一落点上方继续降低。
	var late: Vector4 = material.get_shader_parameter(&"head_arc") # 第二时刻应沿相同几何向落点推进。
	if early.x < 0.28 or early.x > 0.37 or late.x < 0.72 or late.x > 0.79 or early == late:
		_fail("光头进度不对应实际贝塞尔弧长")
		return
	if early_front.y >= late_front.y or late_front.y >= landings[0].y:
		_fail("飞行光源的高度应随光束前沿连续降低")
		return
	if ribbon.mesh != mesh or ribbon.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != positions:
		_fail("流光动画修改了静态表面")
		return
	var heads := Vector4(1.0, 0.0, 1.0, 1.0) # 被取消的光束始终留在遮罩外。
	ribbon.release(0.25, 0.85, heads)
	if not ribbon.visible:
		_fail("触地后拖尾应沿弧长退出，半程仍有红芒")
		return
	var middle_drain: float = material.get_shader_parameter(&"shaft_drain") # 恢复的是实际从上向下的擦除前沿。
	ribbon.release(0.39, 0.85, heads)
	var near_end: float = material.get_shader_parameter(&"shaft_drain") # 越往后只留靠近地面的光。
	if material.get_shader_parameter(&"head_arc") != heads or middle_drain <= 0.25 or near_end <= middle_drain:
		_fail("已落地的束沿弧长收束，取消的束不能再出现")
		return
	ribbon.release(0.52, 0.85, heads)
	if ribbon.visible:
		_fail("触地退场结束后流光几何仍留在场上")
		return
	ribbon.begin(landings, 64.0)
	ribbon.present(0.40, 0.85)
	if not ribbon.visible or material.get_shader_parameter(&"shaft_drain") != 0.0:
		_fail("下一轮不能继承上一次的拖尾遮罩")
		return
	ribbon.queue_free()
	print("DESPAIR_RIBBON_OK vertices=%s triangles=%s" % [positions.size(), indices.size() / 3.0])
	quit()

## [param reason] 提供简洁、可重复的断言语义。
func _fail(reason: String) -> void:
	push_error("DESPAIR_RIBBON: " + reason)
	quit(1)
