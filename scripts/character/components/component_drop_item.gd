## 僵尸常规死亡掉落组件，生成银币、金币、钻石；冒险战斗中额外生成材料。
extends ComponentNormBase
class_name DropItemComponent

@export_group("掉落相关")
## 可以掉落坐标X范围,若x在该范围内可以掉落(僵尸逃跑\魅惑离开当前页面)
@export var can_drop_x_range :Vector2 = Vector2(0, 900)
## 死亡时抽取一次钱币掉落的概率。
@export var drop_coin_rate := 0.3
## 掉落银币、金币、钻石的比例（要求和为1）
@export var drop_coin_silver_glod_diamond_rate := [0.5,0.4,0.1]
## 掉落生产的偏移y值
@export var correct_y:float=100
## 金币移动的目标位置与初始位置的y的范围
@export var target_move_y_range:Vector2 = Vector2(80, 90)

#region 僵尸掉落
## 掉落金银钻；冒险战斗中同时按阶段材料池尝试掉落材料。
func drop_coin():
	if not is_enabling:
		return
	var battle: MainGameManager = Global.main_game # 预览中的击杀不产生可写入玩家档案的掉落。
	if is_instance_valid(battle) and not battle.preview_return_scene.is_empty():
		return
	if global_position.x > can_drop_x_range.y or global_position.x < can_drop_x_range.x:
		return

	var drop_position := Vector2(
		clamp(global_position.x, 0, get_viewport().get_visible_rect().size.x),
		clamp(global_position.y - correct_y, 0, get_viewport().get_visible_rect().size.y)
	)
	var coin_chance: float = drop_coin_rate # 原版战斗使用组件配置的概率。
	# 材料与金币各自独立判定，互不影响。
	if AdventureSession.owns_battle(Global.game_para):
		EventBus.push_event("create_material_drop", [drop_position])
		var effects: PlayerEffects = AdventureSession.player_effects_for(Global.game_para) # 使用出战时的装备快照。
		coin_chance = minf(1.0, coin_chance * effects.coin_drop_chance_multiplier)

	if randf() < coin_chance or coin_chance >= 1.0:

		EventBus.push_event("create_coin", [
			drop_coin_silver_glod_diamond_rate,\
			drop_position,
			Vector2(randf_range(-50, 50), randf_range(target_move_y_range.x, target_move_y_range.y))
		])

#endregion

