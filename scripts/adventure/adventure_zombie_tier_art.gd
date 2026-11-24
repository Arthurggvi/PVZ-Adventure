## 僵尸实例级等阶美术绑定：统一替换部件、动画关键帧与受伤状态图。
## 出战外观在入树前准备，原版场景与共享动画保持只读。
extends RefCounted
class_name AdventureZombieTierArt

## 原生动画库的物种装备分支特化；不引入第二套动画时钟。
const RigSpecialization = preload("res://scripts/character/zombie/zombie_rig_specialization.gd")

## 首个实例记录外观替换，后续同场景同等阶的实例复用只读动画与纹理切片。
class PreparedAppearance:
	## 相对于角色根节点的属性替换。
	var properties: Dictionary[NodePath, Dictionary] = {}
	## 相对于角色根节点的动画库替换。
	var libraries: Dictionary[NodePath, Dictionary] = {}
	## 使用同一套贴图的陆行特化库，首次遇到适用实例时建立。
	var _land_rig_libraries: Dictionary[NodePath, Dictionary] = {}
	## 是否确实存在专用等阶美术，决定颜色回退。
	var has_tier_art := false
	## 待分帧构建的同尺寸图集，可在播放器运行期间完成。
	var pending_atlas: ZombieSpriteAtlas

	## 向同场景的 [param zombie] 应用最终外观，复用不可变的素材资源。
	## [param specialize_land_rig] 为 true 时使用陆行物种的特化动画库。
	func apply_to(zombie: Zombie000Base, specialize_land_rig: bool = false) -> void:
		for path: NodePath in properties: # 每个节点只查找一次。
			var node: Node = zombie.get_node(path) # 同一场景的对应部件。
			for property: StringName in properties[path]: # 第一只僵尸编译出的最终属性。
				node.set(property, properties[path][property])
		apply_libraries_to(zombie, specialize_land_rig)

	## 给 [param zombie] 绑定共享动画资源。[param specialize_land_rig] 选择陆行特化形态。
	func apply_libraries_to(zombie: Zombie000Base, specialize_land_rig: bool) -> void:
		var selected: Dictionary[NodePath, Dictionary] = libraries # 水路和其他形态沿用原动画库。
		if specialize_land_rig:
			selected = _libraries_for_land_rig(zombie)
		for path: NodePath in selected: # 播放状态保存在玩家节点，复用的只是动画定义。
			var player := zombie.get_node(path) as AnimationPlayer # 当前实例独立的播放器。
			for library_name: StringName in selected[path]: # 替换有分件变动的共享库。
				player.remove_animation_library(library_name)
				player.add_animation_library(library_name, selected[path][library_name])

	## 以 [param zombie] 对应的原动画库为基础生成陆行特化库，不重复创建图集。
	func _libraries_for_land_rig(zombie: Zombie000Base) -> Dictionary[NodePath, Dictionary]:
		if _land_rig_libraries.is_empty():
			var path: NodePath = ^"AnimationPlayer" # 普僵主混合树使用的播放器。
			var player := zombie.get_node_or_null(path) as AnimationPlayer # 旧资源可能直接来自场景。
			if player == null or not player.has_animation_library(&""):
				return libraries
			var root_libraries: Dictionary = libraries.get(path, {}).duplicate() # 保留其他同级动画库。
			var original: AnimationLibrary = root_libraries.get(&"", player.get_animation_library(&"")) # 优先沿用等阶和图集映射。
			root_libraries[&""] = RigSpecialization.compile(original, RigSpecialization.unused_branches(zombie))
			_land_rig_libraries.assign(libraries)
			_land_rig_libraries[path] = root_libraries
		return _land_rig_libraries


## [param zombie] 是入树前的实体；仅已核对原生骨架和不存在装备的物种使用特化库。
static func can_specialize_land_rig(zombie: Zombie000Base) -> bool:
	return not RigSpecialization.unused_branches(zombie).is_empty()

## 编译 [param zombie] 的 [param tier_id] 外观，并为首个实例应用它。
## [param pack_sprites] 为 true 时同时为图集建立纹理切片；像素读取在后续帧完成。
## [param specialize_land_rig] 为 true 时给符合形态约束的物种裁剪不存在装备的纯视觉轨道。
static func prepare(zombie: Zombie000Base, tier_id: StringName, pack_sprites: bool,
		specialize_land_rig: bool = false) -> PreparedAppearance:
	var appearance := PreparedAppearance.new() # 由战场持有，不污染原版共享场景。
	if tier_id != &"":
		var tier: Dictionary = AdventureZombieTierArtCatalog.textures_for(int(zombie.zombie_type), tier_id) # 原版到等阶映射。
		if not tier.is_empty():
			appearance.has_tier_art = _apply_tree(zombie, tier, zombie, appearance)
	if pack_sprites:
		var parts: Dictionary = {} # 去重的精灵和动画换图片段。
		_collect_parts(zombie, parts)
		var atlas := ZombieSpriteAtlas.new() # 分帧准备的图集，不在生成节点时读取像素。
		atlas.prepare(parts)
		if not atlas.textures.is_empty():
			_apply_tree(zombie, atlas.textures, zombie, appearance)
			appearance.pending_atlas = atlas
	if specialize_land_rig and can_specialize_land_rig(zombie):
		appearance.apply_libraries_to(zombie, true)
	return appearance


## 从 [param node] 的精灵和换图动画收集原纹理，写入去重表 [param parts]。
static func _collect_parts(node: Node, parts: Dictionary) -> void:
	if node is Sprite2D and node.texture != null and node.material == null:
		parts[node.texture] = true
	if node is AnimationPlayer:
		for name: StringName in node.get_animation_list(): # 混合树会沿用播放器中的纹理关键帧。
			var animation: Animation = node.get_animation(name) # 原资源只读。
			for track: int in animation.get_track_count(): # 只收集精灵换图轨道。
				if animation.track_get_type(track) != Animation.TYPE_VALUE \
						or not String(animation.track_get_path(track)).ends_with(":texture"):
					continue
				for key: int in animation.track_get_key_count(track): # 关键帧可能是 null。
					var texture: Variant = animation.track_get_key_value(track, key) # 只接受纹理类。
					if texture is Texture2D:
						parts[texture] = true
	for child: Node in node.get_children(): # 多身体的载具也使用同一个外观图集。
		_collect_parts(child, parts)

## [param zombie] 已实例化、尚未进入场景树的僵尸。
## [param tier_id] 本次战斗唯一等阶 ID。
## 返回是否实际接入专用美术；无图时由绑定器保留既有 tint 表现。
static func apply(zombie: Zombie000Base, tier_id: StringName) -> bool:
	if zombie == null or zombie.is_inside_tree():
		return false
	var textures: Dictionary = AdventureZombieTierArtCatalog.textures_for(
		int(zombie.zombie_type), tier_id)
	if textures.is_empty():
		return false
	return _apply_tree(zombie, textures)

## 为 [param preview] 独立静态预览应用 [param zombie_type]、[param tier_id] 的同一套战斗美术。
## 无专用贴图时复用实战色调；只修改副本，不挂载行为组件或记录遇敌。
static func apply_to_preview(preview: Node2D, zombie_type: int, tier_id: StringName) -> void:
	if preview == null:
		return
	var textures: Dictionary = AdventureZombieTierArtCatalog.textures_for(zombie_type, tier_id) # 使用战斗美术的权威映射。
	var changed: bool = not textures.is_empty() and _apply_tree(preview, textures) # 静态目录可能只有部分身体部件。
	preview.modulate = Color.WHITE if changed else AdventureZombieTierCatalog.get_tier(tier_id).get("tint", Color.WHITE)

## 遍历当前实例所有可见部件及其原版动画组件。
static func _apply_tree(node: Node, textures: Dictionary, root: Node = null,
		appearance: PreparedAppearance = null) -> bool:
	var changed := false
	if node is Sprite2D:
		var sprite: Sprite2D = node as Sprite2D
		var replacement: Texture2D = _texture(sprite.texture, textures)
		if replacement != sprite.texture:
			sprite.texture = replacement
			if appearance != null:
				_remember_property(appearance, root.get_path_to(node), &"texture", replacement)
			changed = true
	if node is AnimationPlayer:
		changed = _apply_animations(node as AnimationPlayer, textures, root, appearance) or changed
	if node.get_script() != null:
		changed = _apply_body_resources(node, textures, root, appearance) or changed
	for child: Node in node.get_children():
		changed = _apply_tree(child, textures, root, appearance) or changed
	return changed

## 不修改原版 Texture2D；仅匹配显式列出的源 PNG。
static func _texture(source: Texture2D, textures: Dictionary) -> Texture2D:
	if source != null:
		if textures.has(source):
			return textures[source] as Texture2D
		if textures.has(source.resource_path):
			return textures[source.resource_path] as Texture2D
	return source

## 只替换含目标纹理的动画，重建当前实例专属 AnimationLibrary。
## 独立拷贝 Animation 可防止污染其他僵尸的 AnimationTree。
static func _apply_animations(player: AnimationPlayer, textures: Dictionary,
		root: Node, appearance: PreparedAppearance) -> bool:
	var any_changed := false
	for library_name: StringName in player.get_animation_library_list():
		var original: AnimationLibrary = player.get_animation_library(library_name)
		var private_library := AnimationLibrary.new()
		var changed := false
		for animation_name: StringName in original.get_animation_list():
			var animation: Animation = original.get_animation(animation_name)
			var local_animation: Animation = null
			for track: int in range(animation.get_track_count()):
				if animation.track_get_type(track) != Animation.TYPE_VALUE or not String(
						animation.track_get_path(track)).ends_with(":texture"):
					continue
				for key: int in range(animation.track_get_key_count(track)):
					var old_value: Variant = animation.track_get_key_value(track, key)
					if not old_value is Texture2D:
						continue
					var next_value: Texture2D = _texture(old_value as Texture2D, textures)
					if next_value != old_value:
						# 延迟克隆：不复制没有纹理变更的庞大原版动画。
						if local_animation == null:
							local_animation = animation.duplicate()
						local_animation.track_set_key_value(track, key, next_value)
			if local_animation != null:
				changed = true
			private_library.add_animation(animation_name,
				local_animation if local_animation != null else animation)
		if changed:
			player.remove_animation_library(library_name)
			player.add_animation_library(library_name, private_library)
			if appearance != null:
				var libraries: Dictionary = appearance.libraries.get_or_add(root.get_path_to(player), {}) # 独立播放器路径。
				libraries[library_name] = private_library
			any_changed = true
	return any_changed

## 按脚本成员扫描换图资源，兼容普通损坏、防具、游泳、眨眼和特殊字典状态。
static func _apply_body_resources(node: Node, textures: Dictionary, root: Node,
		appearance: PreparedAppearance) -> bool:
	var changed := false
	for property: Dictionary in node.get_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var field: StringName = property["name"]
		var original: Variant = node.get(field)
		if not (original is ResourceBodyChange or original is Array or original is Dictionary):
			continue
		var replacement: Variant = _body_resource(original, textures)
		if replacement != original:
			node.set(field, replacement)
			if appearance != null:
				_remember_property(appearance, root.get_path_to(node), field, replacement)
			changed = true
	return changed

## 将 [param path] 上最终的 [param field] 资源保存在 [param appearance]，供新实例使用。
static func _remember_property(appearance: PreparedAppearance, path: NodePath,
		field: StringName, value: Variant) -> void:
	var fields: Dictionary = appearance.properties.get_or_add(path, {}) # 各分件可拥有多个替换属性。
	fields[field] = value

## 仅克隆发生变化的 ResourceBodyChange；保留原数组/字典的类型与键值。
static func _body_resource(value: Variant, textures: Dictionary) -> Variant:
	if value is ResourceBodyChange:
		var source: ResourceBodyChange = value as ResourceBodyChange
		var images: Array[Texture2D] = source.sprite_change_texture.duplicate()
		var changed := false
		for index: int in range(images.size()):
			var replacement: Texture2D = _texture(images[index], textures)
			if replacement != images[index]:
				images[index] = replacement
				changed = true
		if not changed:
			return value
		var local_resource: ResourceBodyChange = source.duplicate()
		local_resource.sprite_change_texture = images
		return local_resource
	if value is Array:
		var source_array: Array = value as Array
		var local_array: Array = source_array.duplicate()
		for index: int in range(source_array.size()):
			local_array[index] = _body_resource(source_array[index], textures)
		return local_array
	if value is Dictionary:
		var source_dict: Dictionary = value as Dictionary
		var local_dict: Dictionary = source_dict.duplicate()
		for entry: Variant in source_dict:
			local_dict[entry] = _body_resource(source_dict[entry], textures)
		return local_dict
	return value
