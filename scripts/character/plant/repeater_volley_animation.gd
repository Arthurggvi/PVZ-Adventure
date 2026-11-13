## 为单株双发在两次原生发射之间插入方法键；全部弹数共用原生动画时钟。
extends RefCounted
class_name RepeaterVolleyAnimation

## 原生第一段射击动画。
const FIRST: StringName = &"PeaShooter_shooting"
## 原生第二段射击动画。
const SECOND: StringName = &"PeaShooter_shooting2"

## [param plant] 为实际双发；[param extra] 为额外颗数，限定零至四。
## 返回仅属于本株的还原凭据；资源不符合原生双射结构时保持原样并返回空。
static func install(plant: Plant008PeaShooterDouble, extra: int) -> Dictionary:
	var player: AnimationPlayer = plant.get_node_or_null("AnimationPlayer") as AnimationPlayer # 同株动画播放器。
	if player == null or not player.has_animation_library(&""):
		return {}
	var original: AnimationLibrary = player.get_animation_library(&"") # 共享资源只读取，不直接修改。
	if not original.has_animation(FIRST) or not original.has_animation(SECOND):
		return {}
	var first: Animation = original.get_animation(FIRST).duplicate(true) as Animation # 第一段私有副本。
	var second: Animation = original.get_animation(SECOND).duplicate(true) as Animation # 第二段私有副本。
	var first_key: Vector2i = _shoot_key(first) # 第一颗的原生方法轨道和键号。
	var second_key: Vector2i = _shoot_key(second) # 第二颗的原生方法轨道和键号。
	if first_key.x < 0 or second_key.x < 0:
		push_error("双发转职未找到原生发射方法轨道")
		return {}
	var beginning: float = first.track_get_key_time(first_key.x, first_key.y) # 合并时间轴的第一发时刻。
	var ending: float = first.length + second.track_get_key_time(second_key.x, second_key.y) # 合并时间轴的末发时刻。
	var amount: int = clampi(extra, 0, 4) # 四转上限，不受重复配置无限增弹。
	for index: int in range(amount): # 有限、等距插入，原本两颗的时刻保持不变。
		var at: float = lerpf(beginning, ending, float(index + 1) / float(amount + 1)) # 两颗原生子弹之间的局部时刻。
		if is_equal_approx(at, first.length):
			at += 0.001 # 避开状态机切片的零时刻键，防止刚进入下一片段时漏掉发射。
		var animation: Animation = first if at < first.length else second # 精确落在连接点时交给第二片段。
		var track: int = first_key.x if animation == first else second_key.x # 只使用已经找到的方法轨道。
		animation.track_insert_key(track, at if animation == first else at - first.length,
			{"method": &"_shoot_bullet", "args": []})
	var installed := AnimationLibrary.new() # 不复制不相关待机资源，仅替换两段本株发射动画。
	for animation_name: StringName in original.get_animation_list(): # 其余动画继续共享原始只读资源。
		installed.add_animation(animation_name, first if animation_name == FIRST else (
			second if animation_name == SECOND else original.get_animation(animation_name)))
	player.remove_animation_library(&"")
	player.add_animation_library(&"", installed)
	return {"player": player, "original": original, "installed": installed}

## [param animation] 的原生方法轨道中寻找唯一射击键；失败返回负一坐标。
static func _shoot_key(animation: Animation) -> Vector2i:
	for track: int in range(animation.get_track_count()): # 只检查原生发射组件的方法轨道。
		if animation.track_get_type(track) != Animation.TYPE_METHOD \
				or animation.track_get_path(track) != NodePath("AttackComponent"):
			continue
		for key: int in range(animation.track_get_key_count(track)): # 方法键有限，不依赖动画片段的固定轨道编号。
			var value: Dictionary = animation.track_get_key_value(track, key) # 原生方法名与参数。
			if StringName(value.get("method", "")) == &"_shoot_bullet":
				return Vector2i(track, key)
	return Vector2i(-1, -1)

## [param receipt] 来自 install；只有播放器仍引用本次私有库时才还原共享库。
static func release(receipt: Dictionary) -> void:
	var player: AnimationPlayer = receipt.get("player") as AnimationPlayer # 旧植株销毁后不能再触及其播放器。
	if not is_instance_valid(player) or player.is_queued_for_deletion() \
			or not player.has_animation_library(&"") \
			or player.get_animation_library(&"") != receipt.get("installed"):
		return
	player.remove_animation_library(&"")
	player.add_animation_library(&"", receipt.get("original") as AnimationLibrary)
