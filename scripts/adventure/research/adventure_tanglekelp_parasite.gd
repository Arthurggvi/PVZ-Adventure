## 寄生只跟随实际宿主；宿主占格释放前从原生啃食状态辨认目标。
extends Node
class_name AdventureTanglekelpParasite

## 具名节点控制同一宿主只能接受一次寄生。
const NODE_NAME := &"TanglekelpParasite"

## 已成功接受寄生的植物。
var _host: Plant000Base
## 保留原海草的缠绕动画，直到宿主死亡或离场。
var _grab: GrapComponent
## 寄生处决也使用原卡的杀敌奖励。
var _rules: Dictionary[String, Dictionary]

## 在 [param host] 挂载一次寄生并接管 [param grab]；[param rules] 是种植时冻结的书目。
static func attach(host: Plant000Base, grab: GrapComponent, rules: Dictionary[String, Dictionary]) -> void:
	var parasite := AdventureTanglekelpParasite.new() # 具名子节点也是放置预检的独占标记。
	parasite.name = NODE_NAME
	parasite._host = host
	parasite._grab = grab
	parasite._rules = rules
	host.add_child(parasite)
	grab.reparent(parasite, false)
	if host.plant_cell.board != null:
		host.plant_cell.board.plant_dying.connect(parasite._on_plant_dying)

## [param plant] 为死亡通知中的真实对象；只有本宿主的自然死亡能消耗寄生。
func _on_plant_dying(plant: Plant000Base) -> void:
	if plant != _host or not plant.is_can_death_language or not plant.death_recording_enabled \
			or plant.has_node(NodePath(AdventurePlantNullification.NODE_NAME)) \
			or plant.plant_cell.get_spawn_terrain_type() != CharacterRegistry.ZombieRowType.Pool:
		return
	var grabs: AdventureTanglekelpGrabs = AdventureTanglekelpGrabs.capture(plant, _rules) # 此时还可读取宿主的真实占格。
	if grabs == null:
		return
	var biters: Array[Zombie000Base] = [] # 先冻结真实正在啃食的敌人，避免抓取后索敌切换。
	for zombie: Zombie000Base in grabs.battle.game.zombie_manager.all_zombies_1d: # 先找实际啃食者，再读取其所在水陆。
		if not is_instance_valid(zombie) or zombie.is_action_suspended() or zombie.is_cold_frozen():
			continue
		var bite := zombie.attack_component as AttackComponentZombieNorm # 普通、扶梯等共用原生啃食链。
		if bite != null and bite.is_attack_res and is_instance_valid(bite.detect_component) \
				and bite.detect_component.enemy_can_be_attacked == plant and grabs.can_drown_biter(zombie):
			biters.append(zombie)
	grabs.start(_grab, biters)
