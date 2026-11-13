## 等阶用例共用的真实草坪。关闭自然出怪，让用例单独控制注入的实体和事件。
extends RefCounted

## 在 [param parent] 下启动正常战斗场景，并由场景自身登记战场身份。
static func mount(parent: Node) -> MainGameManager:
	var level := ResourceLevelData.new() # 单场无自然波次的测试配置。
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_day_sun = false
	level.is_lawn_mover = false
	var battle := preload("res://scenes/main/MainGame01Front.tscn").instantiate() as MainGameManager # 使用真实管理器和地块。
	battle.game_para = level
	parent.add_child(battle)
	return battle
