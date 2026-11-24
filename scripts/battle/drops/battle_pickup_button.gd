## 战斗中让持卡或持工具的玩家点到下方格子，沿用掉落物按钮自身的矩形拾取范围。
extends BaseButton

## [param point] 为按钮局部坐标。格内判定使用 GUI 已换算的视口坐标，兼容相机、掉落层和折射。
func _has_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return false
	var game: MainGameManager = Global.main_game # 非战斗场景的钱币仍使用原按钮命中。
	if not is_instance_valid(game) or not game.is_ancestor_of(self):
		return true
	var hand: HandManager = game.hand_manager # 只读取本局手持状态，掉落物无需监听卡片切换。
	return not is_instance_valid(hand) or not hand.has_board_action_at(get_global_transform_with_canvas() * point)
