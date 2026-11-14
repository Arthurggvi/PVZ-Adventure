extends Node
## 暂时僵尸节点
class_name ZombieShowInStart

@onready var zombie_manager: ZombieManager = %ZombieManager

@export_group("准备阶段展示僵尸")
## 按y轴顺序渲染
@onready var show_zombie_panel: Panel = %ShowZombiePanel
## 不按y轴顺序渲染
@onready var show_zombie_panel_2: Panel = %ShowZombiePanel2

## #关卡前展示僵尸生成默认数量范围
@export var default_show_zombie_num_range:Vector2i = Vector2i(1,4)
## 关卡前展示僵尸生成数量范围(默认不生成旗帜僵尸)
@export var special_show_zombie_num_range: Dictionary[CharacterRegistry.ZombieType, Vector2i] = {
	CharacterRegistry.ZombieType.Z002Flag : Vector2i(0,0)
}
var show_zombies_array :Array[Zombie000Base]


#region 生成关卡前展示僵尸
## 生成一个展示僵尸
func create_show_zombie(zombie_type:CharacterRegistry.ZombieType, parent_node:Panel) -> Zombie000Base:
	var zombie_pos :=Vector2(randf_range(0, parent_node.size.x), randf_range(0, parent_node.size.y))
	var zombie:Zombie000Base = Global.character_registry.get_zombie_info(zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieScenes).instantiate()
	var zombie_init_para:Dictionary = {
		Zombie000Base.E_ZInitAttr.CharacterInitType:Character000Base.E_CharacterInitType.IsShow,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType:CharacterRegistry.ZombieRowType.Land,
		Zombie000Base.E_ZInitAttr.IsMiniZombie: zombie_manager.game_para.is_mini_zombie
	}
	zombie.init_zombie(zombie_init_para)
	parent_node.add_child(zombie)
	zombie.position = zombie_pos
	return zombie

## 生成关卡前展示僵尸；冒险首屏按 4ms 构造预算让出帧，调用方等待全部完成再开始镜头。
func create_prepare_show_zombies() -> void:
	var budget_start: int = Time.get_ticks_usec() # 当前批次主线程构造的计时起点。
	var stagger: bool = AdventureSession.owns_battle(zombie_manager.game_para) # 原版入口保持原有同步行为。
	for zombie_type: int in zombie_manager.zombie_refresh_types: # 本关真实预览名单。
		var zombie_num_range: Vector2i = special_show_zombie_num_range.get(zombie_type, default_show_zombie_num_range) # 原随机数量范围。
		var zombie_num: int = randi_range(zombie_num_range.x, zombie_num_range.y) # 每种物种只抽取一次数量。
		for _index: int in range(zombie_num): # 每次只构造一个完整展示实体。
			if stagger and Time.get_ticks_usec() - budget_start >= 4000:
				await get_tree().process_frame
				if not is_inside_tree():
					return
				budget_start = Time.get_ticks_usec()
			var zombie: Zombie000Base = create_show_zombie(zombie_type, show_zombie_panel) # 后台已准备的资源在主线程实例化。
			show_zombies_array.append(zombie)
	if zombie_manager.is_bungi:
		var bungee: Zombie000Base = create_show_zombie(CharacterRegistry.ZombieType.Z021Bungi, show_zombie_panel_2) # 特殊层的蹦极展示实体。
		show_zombies_array.append(bungee)

## 删除关卡前展示僵尸
func delete_prepare_show_zombies() -> void:
	for z in show_zombies_array:
		z.queue_free()
	show_zombies_array.clear()  # 清空数组
#endregion
