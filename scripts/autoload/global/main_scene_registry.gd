extends Node
class_name MainSceneRegistry


## 加载场景
enum MainScenes{
	MainGameFront,
	MainGameBack,
	MainGameRoof,

	StartMenu = 100,
	ChooseLevelAdventure,
	ChooseLevelMiniGame,
	ChooseLevelPuzzle,
	ChooseLevelSurvival,
	ChooseLevelCustom,

	Garden = 200,
	Almanac,
	Store,

	Null = 999,
}
@export var MainScenesMap = {
	MainScenes.MainGameFront: "res://scenes/main/MainGame01Front.tscn",
	MainScenes.MainGameBack: "res://scenes/main/MainGame02Back.tscn",
	MainScenes.MainGameRoof: "res://scenes/main/MainGame03Roof.tscn",

	MainScenes.StartMenu: "res://scenes/main/01StartMenuCoastal.tscn",
	MainScenes.ChooseLevelAdventure: "res://scenes/main/02AdventureChooesLevel.tscn",
	MainScenes.ChooseLevelMiniGame: "res://scenes/main/03MiniGameChooesLevel.tscn",
	MainScenes.ChooseLevelPuzzle: "res://scenes/main/04PuzzleChooesLevel.tscn",
	MainScenes.ChooseLevelSurvival: "res://scenes/main/05SurvivalChooesLevel.tscn",
	MainScenes.ChooseLevelCustom: "res://scenes/main/06CustomChooesLevel.tscn",

	MainScenes.Garden: "res://scenes/main/10Garden.tscn",
	MainScenes.Almanac: "res://scenes/main/11Almanac.tscn",
	MainScenes.Store: "res://scenes/main/12Store.tscn",
}

## 场景僵尸的行类型
@export var ZombieRowTypewithMainScenesMap:Dictionary[MainScenes, CharacterRegistry.ZombieRowType] = {
	MainScenes.MainGameFront:CharacterRegistry.ZombieRowType.Land,
	MainScenes.MainGameBack:CharacterRegistry.ZombieRowType.Both,
	MainScenes.MainGameRoof:CharacterRegistry.ZombieRowType.Land,
}

## 基础战场 ZombiesRoot 自上而下的静态行协议，仅包含枚举，不加载战场资源。
## 分别对应 MainGame01Front、MainGame02Back、MainGame03Roof.tscn；实际装配时由
## BoardSceneAdapter 在地形覆盖前核对节点，场景布局改动必须同步维护本表。
const LEGACY_SPAWN_ROWS := {
	MainScenes.MainGameFront: [CharacterRegistry.ZombieRowType.Land,
		CharacterRegistry.ZombieRowType.Land, CharacterRegistry.ZombieRowType.Land,
		CharacterRegistry.ZombieRowType.Land, CharacterRegistry.ZombieRowType.Land],
	MainScenes.MainGameBack: [CharacterRegistry.ZombieRowType.Land,
		CharacterRegistry.ZombieRowType.Land, CharacterRegistry.ZombieRowType.Pool,
		CharacterRegistry.ZombieRowType.Pool, CharacterRegistry.ZombieRowType.Land,
		CharacterRegistry.ZombieRowType.Land],
	MainScenes.MainGameRoof: [CharacterRegistry.ZombieRowType.Land,
		CharacterRegistry.ZombieRowType.Land, CharacterRegistry.ZombieRowType.Land,
		CharacterRegistry.ZombieRowType.Land, CharacterRegistry.ZombieRowType.Land],
}

## 返回 [param scene] 的基础行类型副本；未登记场景返回空数组，不触发资源读取。
func get_legacy_spawn_rows(scene: MainScenes) -> Array[CharacterRegistry.ZombieRowType]:
	var rows: Array[CharacterRegistry.ZombieRowType] = [] # 隔离调用方的关卡覆盖与静态表。
	rows.assign(LEGACY_SPAWN_ROWS.get(scene, []))
	return rows

## 核对 [param scene] 的静态协议与已实例化的 [param root]，不创建第二张战场。
## 必须在本局 terrain_rows 覆盖前调用；未登记或节点/出生标记不一致时返回 false。
func matches_legacy_spawn_rows(scene: MainScenes, root: Node) -> bool:
	var rows: Array[CharacterRegistry.ZombieRowType] = get_legacy_spawn_rows(scene) # 只读标量表。
	if root == null or rows.is_empty() or root.get_child_count() != rows.size():
		return false
	for index: int in range(rows.size()): # 沿用场景 ZombiesRoot 的权威顺序。
		var row := root.get_child(index) as ZombieRow # 正式战场已有行节点。
		if row == null or not row.has_node(^"ZombieCreatePosition") or row.zombie_row_type != rows[index]:
			return false
	return true
