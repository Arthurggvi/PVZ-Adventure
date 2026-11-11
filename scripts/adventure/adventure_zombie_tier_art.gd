## 僵尸实例级等阶美术绑定：统一替换部件、动画关键帧与受伤状态图。
## 只在入树前处理拥有有效冒险等阶的实例；绝不修改原版共享资源。
extends RefCounted
class_name AdventureZombieTierArt

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
static func _apply_tree(node: Node, textures: Dictionary) -> bool:
	var changed := false
	if node is Sprite2D:
		var sprite: Sprite2D = node as Sprite2D
		var replacement: Texture2D = _texture(sprite.texture, textures)
		if replacement != sprite.texture:
			sprite.texture = replacement
			changed = true
	if node is AnimationPlayer:
		changed = _apply_animations(node as AnimationPlayer, textures) or changed
	if node.get_script() != null:
		changed = _apply_body_resources(node, textures) or changed
	for child: Node in node.get_children():
		changed = _apply_tree(child, textures) or changed
	return changed

## 不修改原版 Texture2D；仅匹配显式列出的源 PNG。
static func _texture(source: Texture2D, textures: Dictionary) -> Texture2D:
	if source != null and textures.has(source.resource_path):
		return textures[source.resource_path] as Texture2D
	return source

## 只替换含目标纹理的动画，重建当前实例专属 AnimationLibrary。
## 独立拷贝 Animation 可防止污染其他僵尸的 AnimationTree。
static func _apply_animations(player: AnimationPlayer, textures: Dictionary) -> bool:
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
			any_changed = true
	return any_changed

## 按脚本成员扫描换图资源，兼容普通损坏、防具、游泳、眨眼和特殊字典状态。
static func _apply_body_resources(node: Node, textures: Dictionary) -> bool:
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
			changed = true
	return changed

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
