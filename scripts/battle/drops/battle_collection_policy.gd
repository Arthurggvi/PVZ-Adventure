## 冒险战斗的自动收集只读取本局装备能力和期限。
extends RefCounted
class_name BattleCollectionPolicy

## [param sun] 区分阳光与公共掉落；本函数只决定是否发起正常收集，不修改任何资产。
static func allows(sun: bool) -> bool:
	if not is_instance_valid(Global.main_game) or not AdventureSession.owns_battle(Global.main_game.game_para):
		return false
	var effects: PlayerEffects = AdventureSession.player_effects_for(Global.main_game.game_para) # 不直接访问装备库存。
	return effects.can_collect(sun)
