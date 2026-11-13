## 回旋镖发射的资格、索敌和实例化入口；不管理冷却或创建派生攻击。
extends RefCounted
class_name BloomerangEmitter

## 独立音色函数可在母株离场后继续为已结算命中播放声音。
const Audio = preload("res://scripts/character/plant/bloomerang_audio.gd")

## [param plant] 必须仍属于 [param game] 的 [param round_index] 轮有效地格。
## [param owner_speed] 为角色动作倍率；所有自然发射、连发和补投共用此门禁。
static func can_emit(plant: Plant000Base, game: MainGameManager,
		round_index: int, owner_speed: float) -> bool:
	if not is_instance_valid(plant) or not is_instance_valid(game) \
			or plant.is_death or plant.is_queued_for_deletion() or not plant.is_inside_tree() \
			or game.is_queued_for_deletion() or not game.is_inside_tree() or game != Global.main_game \
			or game.get_tree().current_scene != game or not game.is_ancestor_of(plant) \
			or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or game.curr_game_round != round_index or game.get_tree().paused \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false) \
			or not plant.can_process() or plant.is_sleeping or not is_finite(owner_speed) or owner_speed <= 0.0 \
			or plant.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or plant.has_node(NodePath(AdventurePlantNullification.NODE_NAME)):
		return false
	var cell: PlantCell = plant.plant_cell # 格子登记覆盖普通植物及合法伴生身份。
	var detect: DetectComponent = plant.get_node_or_null("DetectComponent") as DetectComponent # 原株唯一索敌组件。
	return game.board != null and is_instance_valid(cell) and not cell.is_queued_for_deletion() \
		and cell.board == game.board and cell.living_plants().has(plant) \
		and is_instance_valid(detect) and detect.is_enabling \
		and is_instance_valid(game.bullets) and not game.bullets.is_queued_for_deletion()

## [param plant] 的战斗视口左右边界，换算为世界坐标以适配镜头和平移平台。
static func battle_edges(plant: Plant000Base) -> Vector2:
	var transform: Transform2D = plant.get_canvas_transform().affine_inverse() # 屏幕到当前战场的变换。
	var viewport: Rect2 = plant.get_viewport_rect() # 当前视口的屏幕坐标范围。
	var left: float = (transform * viewport.position).x # 镜头可能带缩放，不能直接使用屏幕像素。
	var right: float = (transform * viewport.end).x # 包含宽屏战场的真实右端。
	return Vector2(minf(left, right), maxf(left, right))

## 用 [param edges] 更新 [param detect] 的整行检测宽度；形状必须逐场景实例独立。
## 仅改变横向范围，保留屋顶检测修正已经写入的高度。
static func update_detection(detect: DetectComponent, edges: Vector2) -> void:
	var area: Area2D = detect.get_node("Area2D") as Area2D # 原场景固定的单行检测区域。
	var collision: CollisionShape2D = area.get_node("CollisionShape2D") as CollisionShape2D # 本株独立矩形。
	var rectangle: RectangleShape2D = collision.shape as RectangleShape2D # 场景保证该资源为矩形且本地化。
	var width: float = maxf(1.0, (edges.y - edges.x) / maxf(absf(area.global_scale.x), 0.001)) # 换算为形状局部宽度。
	if not is_equal_approx(rectangle.size.x, width):
		rectangle.size = Vector2(width, rectangle.size.y)
	var center: float = (edges.x + edges.y) * 0.5 # 屏幕中央可能偏离本株，故设置世界坐标。
	if not is_equal_approx(area.global_position.x, center):
		area.global_position = Vector2(center, area.global_position.y)

## [param plant] 用 [param detect] 筛选实际可攻击目标；[param sweep] 允许后方起手。
## [param edges] 排除场外等待进场的对象；返回是否至少有一个合法目标。
static func has_target(plant: Plant000Base, detect: DetectComponent,
		sweep: bool, edges: Vector2) -> bool:
	for target: Character000Base in detect.get_all_enemy_can_be_attacked(): # DetectComponent 已按行、状态和阵营层筛选。
		if target.is_hypno or not is_instance_valid(target.hurt_box_component) \
				or not target.hurt_box_component.is_enabling:
			continue
		var target_x: float = target.hurt_box_component.global_position.x # 僵王根节点可能偏离真实受击区域。
		if target_x >= edges.x and target_x <= edges.y \
				and (sweep or target_x >= plant.global_position.x):
			return true
	return false

## 从 [param plant] 的 [param launch] 创建未入树的新弹；[param detect] 提供原生状态过滤。
## [param shot] 必须是独立快照；[param sound_tier] 冻结命中音色，母株消失不会丢失声音。
## 调用者先登记回收身份及信号，再将返回的新弹加入 shot.game.bullets。
static func create(plant: Plant000Base, launch: Marker2D, detect: DetectComponent,
		shot: BloomerangShotContext, sound_tier: int) -> Bullet017Boomerang:
	if not is_instance_valid(plant) or not is_instance_valid(launch) or not is_instance_valid(detect):
		return null
	return create_at(plant, launch, shot, launch.global_position, plant.lane,
		detect.can_attack_zombie_status, detect.can_attack_plant_status, sound_tier)

## 以世界坐标 [param origin] 和 [param bullet_lane] 创建未入树的新弹，供离手及命中派生共用。
## [param plant]、[param launch] 可为空；母株死亡不阻断已经离手的合法暴雨，但此入口不决定派生规则。
## [param shot] 提供战场及伤害快照；[param zombie_states]、[param plant_states] 为原弹攻击资格。
## [param sound_tier] 冻结声音档，返回弹的音效、初始化和配置只在此处连接一次。
static func create_at(plant: Plant000Base, launch: Marker2D, shot: BloomerangShotContext,
		origin: Vector2, bullet_lane: int, zombie_states: int, plant_states: int,
		sound_tier: int) -> Bullet017Boomerang:
	if shot == null or not shot.is_active() or not is_instance_valid(shot.game.bullets) \
			or shot.game.bullets.is_queued_for_deletion():
		return null
	var bullet: Bullet017Boomerang = Global.bullet_registry.get_bullet_scenes(
		BulletRegistry.BulletType.Bullet017Boomerang).instantiate() as Bullet017Boomerang # 新弹有独立飞行及命中账本。
	bullet.init_bullet({
		Bullet000NormBase.E_InitParasAttr.BulletLane: bullet_lane,
		Bullet000NormBase.E_InitParasAttr.Position: shot.game.bullets.to_local(origin),
		Bullet000NormBase.E_InitParasAttr.Direction: Vector2(shot.launch_direction, 0.0),
		Bullet000NormBase.E_InitParasAttr.CanAttackZombieState: zombie_states,
		Bullet000NormBase.E_InitParasAttr.CanAttackPlantState: plant_states,
		Bullet000NormBase.E_InitParasAttr.DamageMultiplier: shot.damage_multiplier * shot.base_multiplier,
		Bullet000NormBase.E_InitParasAttr.AttackContext: shot.attack_context,
	})
	bullet.impact_sound_tier = sound_tier
	bullet.projectile_factory = create_at
	bullet.configure_flight(shot, plant, launch)
	bullet.impact_resolved.connect(Audio.play_impact.bind(sound_tier).unbind(2))
	return bullet
