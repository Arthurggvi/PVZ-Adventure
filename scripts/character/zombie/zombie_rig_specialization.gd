## 原版陆行装备分支特化：仅删除物种永远不使用的隐藏分件变换轨道。
## 原生混合树、步幅、动作事件、攻击、换图、可见性和所有实际装备均保持不变。
extends RefCounted

## 显式场景身份；不根据当前血量、临时可见性或随机外观推断物种。
const SCENES := {
	1: "zombie_001_norm", 2: "zombie_002_flag", 3: "zombie_003_cone",
	5: "zombie_005_bucket", 7: "zombie_007_screendoor",
}
## 普僵共用骨架的可选装备分支，旗帜与铁门的实际持握分件不混为一谈。
const COMMON_UNUSED := [&"Zombie_flaghand", &"Zombie_flag", &"Zombie_innerarm_screendoor",
	&"Anim_screendoor", &"Zombie_innerarm_screendoor_hand", &"Zombie_outerarm_screendoor",
	&"Anim_cone", &"Anim_bucket"]
## 只裁剪纯视觉的局部位姿；保留所有状态机可见性、换图、方法及其他轨道。
const TRANSFORMS := [&"position", &"rotation", &"scale", &"skew"]

## [param zombie] 为入树前的真实出战实体；返回空数组即使用原有动画库。
static func unused_branches(zombie: Zombie000Base) -> Array[StringName]:
	var result: Array[StringName] = [] # 尚未通过骨架和物种检查。
	var species: int = int(zombie.zombie_type) # 具体物种，不使用基类继承身份。
	if not SCENES.has(species) or zombie.scene_file_path != "res://scenes/character/zombie/" + SCENES[species] + ".tscn":
		return result
	if zombie.character_init_type != Character000Base.E_CharacterInitType.IsNorm or zombie.is_death or zombie.is_show or zombie.is_mini_zombie or zombie.curr_zombie_row_type != CharacterRegistry.ZombieRowType.Land:
		return result
	if species == 7:
		result.assign([&"Zombie_flaghand", &"Zombie_flag", &"Anim_cone", &"Anim_bucket"])
	elif species == 2:
		result.assign([&"Anim_screendoor", &"Zombie_innerarm_screendoor_hand", &"Zombie_outerarm_screendoor", &"Anim_cone", &"Anim_bucket"])
	else:
		result.assign(COMMON_UNUSED)
		if species == 3:
			result.erase(&"Anim_cone")
		elif species == 5:
			result.erase(&"Anim_bucket")
	var rig := zombie.get_node_or_null(^"Body/BodyCorrect") as Node2D # 原生骨架坐标不变。
	if rig == null:
		return []
	for branch: StringName in result:
		var wrapper := rig.get_node_or_null(NodePath(branch)) as Node2D # 只允许确实隐藏的完整装备容器。
		if wrapper == null or wrapper.visible or wrapper.get_child_count() == 0 or wrapper.get_script() != null:
			return []
	return result

## [param original] 为已完成等阶及图集换图的只读动画库；[param branches] 为物种明确不存在的装备。
## 若任何原生片段写入容器本身或含非纯视觉轨道，则该分支保留原样。
static func compile(original: AnimationLibrary, branches: Array[StringName]) -> AnimationLibrary:
	var safe: Array[StringName] = branches.duplicate() # 先做整个库的拓扑验证。
	for clip: StringName in original.get_animation_list():
		var animation: Animation = original.get_animation(clip)
		for track: int in animation.get_track_count():
			var path: NodePath = animation.track_get_path(track)
			if path.is_absolute() or path.get_name_count() < 3 or path.get_name(0) != &"Body" or path.get_name(1) != &"BodyCorrect":
				continue
			var branch: StringName = path.get_name(2)
			if safe.has(branch) and (path.get_name_count() == 3 or animation.track_get_type(track) != Animation.TYPE_VALUE):
				safe.erase(branch) # 容器状态或非值事件不满足隐藏证明。
	if safe.is_empty():
		return original
	var result := AnimationLibrary.new() # 整个战场的同物种、同等阶共用。
	for clip: StringName in original.get_animation_list():
		var source: Animation = original.get_animation(clip) # 无可删轨道时继续复用资源。
		var edited: Animation
		for track: int in range(source.get_track_count()-1,-1,-1):
			var path: NodePath = source.track_get_path(track)
			if source.track_get_type(track) != Animation.TYPE_VALUE or path.is_absolute() or path.get_name_count() < 4 or path.get_subname_count() != 1:
				continue
			if path.get_name(0) != &"Body" or path.get_name(1) != &"BodyCorrect" or not safe.has(path.get_name(2)) or not TRANSFORMS.has(path.get_subname(0)):
				continue
			if edited == null:
				edited = source.duplicate() as Animation
			edited.remove_track(track)
		result.add_animation(clip, edited if edited != null else source)
	return result
