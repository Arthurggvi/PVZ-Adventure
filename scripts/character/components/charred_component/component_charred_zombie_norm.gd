extends CharredComponent
class_name CharredComponentZombieNorm
## 灰烬组件：常规僵尸的原画分件只在灰烬死亡时实例化，原生动画与独立退场时序不变。

## 已内嵌灰烬树的其他物种继续沿用原有场景；支持的物种共享已加载的原画模板。
@export var lazy_visual_scene: PackedScene
## 原生灰烬动画播放器；延迟装配的物种在死亡之前没有播放器节点。
@onready var anim_lib: AnimationPlayer = get_node_or_null("ZombieCharred/CharredCorrect/AnimLib") as AnimationPlayer
## 保留原有身体引用，供旧场景及继承者使用。
@onready var body: BodyCharacter = %Body
## 原生播放片段；特定物种可选择另一段灰烬动画。
@export var anim_lib_name := "ALL_ANIMS"

## 装配当前原画，外层CharredCorrect原有偏移、比例及方向保持不变。
func _ensure_visual() -> bool:
	if is_instance_valid(anim_lib):
		return true
	if lazy_visual_scene == null:
		push_error("灰烬组件缺少原画模板")
		return false
	var visual: Node2D = lazy_visual_scene.instantiate() as Node2D # 只在首次实际灰烬时生成分件。
	if visual == null:
		return false
	var player: AnimationPlayer = visual.get_node_or_null("AnimLib") as AnimationPlayer # 原生动画路径相对于独立视觉根。
	if player == null or not player.has_animation(anim_lib_name):
		visual.free()
		push_error("灰烬模板缺少原生动画")
		return false
	var zombie := owner_character as Zombie000Base # 与出生时等阶纹理入口一致。
	if zombie != null and zombie.adventure_tier_id != &"":
		var art: Script = load("res://scripts/adventure/adventure_zombie_tier_art.gd") # 运行期依赖避免基类编译循环。
		var catalog: Script = load("res://scripts/adventure/adventure_zombie_tier_art_catalog.gd")
		art._apply_tree(visual,catalog.textures_for(int(zombie.zombie_type),zombie.adventure_tier_id))
	get_node("ZombieCharred/CharredCorrect").add_child(visual)
	anim_lib = player
	return true

## 灰烬演出仍脱离角色本体独立退场；没有伪造尸体或改变伤害时序。
func play_charred_anim():
	if not _ensure_visual():
		return
	super()
	anim_lib.play(anim_lib_name)
	await anim_lib.animation_finished
	queue_free()
