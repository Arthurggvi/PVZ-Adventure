## 玉米投手保留原生随机装填与离手动画，转职仅替换发出的结果及锁定范围。
extends Plant000Base
class_name Plant035CornPult

## 所有本战场的投掷共用一份时钟及落点缓存。
const CornBattle = preload("res://scripts/adventure/research/corn_battle.gd")
## 帽子源图是独立透明美术，实际选到该分支才取入。
const HAT_PATH := "res://assets/image/plant/corn_popcap_hat.png"
## 源图中紧贴帽身的区域，保持实际透明边缘。
const HAT_REGION := Rect2(204, 86, 1120, 856)
## 生成源图的宽度。Godot 导入时缩小纹理，不让帽子常驻原始大贴图。
const HAT_SOURCE_WIDTH: float = 1536.0
## 每个额外玉米粒略微错开发射轨迹。
const KERNEL_SPACING: float = 0.052
## 各技能在冻结出战卡上的说明。
enum Power { HAT = 1, SLIPPERY = 2, AIR = 4, BUTTER_DAY = 8, POISON = 16, GAMBLER = 32, GREEN = 64, GENETIC = 128 }

## 原生装填概率、目标记录和离手帧均使用同一组件。
@onready var attack_component: AttackComponentBulletCorn = $AttackComponent
## 一次出战的全部词条。
var _powers: int = 0
## 每枚非黄油投掷增加一层，黄油谱系清空。
var gambler_stacks: int = 0
## 赌徒只叠加在这次固定的转职攻速上，不覆盖其他状态因素。
var _fixed_attack_rate: float = 1.0
## 真正绑定在头部的活动帽子。
var _popcap_hat: Sprite2D

## [param events] 经正式研究卡校验后在节点入场前传入。
func configure_promotions(events: Array[Dictionary]) -> void:
	for event: Dictionary in events: # 每阶只拥有实际选择的事件。
		match String(event.kind):
			"corn_popcap": _powers |= Power.HAT
			"corn_slippery": _powers |= Power.SLIPPERY
			"corn_airraid": _powers |= Power.AIR
			"corn_butter_day": _powers |= Power.BUTTER_DAY
			"corn_poison": _powers |= Power.POISON
			"corn_gambler": _powers |= Power.GAMBLER
			"corn_green": _powers |= Power.GREEN
			"corn_genetic": _powers |= Power.GENETIC

## 普通投手保留原版。绿色食品在装填时就禁止黄油分支与黄油贴图。
func ready_norm_signal_connect() -> void:
	super()
	signal_update_speed.connect(attack_component.owner_update_speed)
	if _powers == 0:
		return
	_fixed_attack_rate = float(influence_speed_factors.get(E_Influence_Speed_Factor.AdventurePromotionAttackRate, 1.0))
	if _powers & Power.HAT:
		_attach_hat()
	if _powers & Power.GREEN:
		attack_component.p_butter = 0.0
	if _powers & Power.BUTTER_DAY:
		attack_component.target_override = _three_lane_target
		attack_component.set_requires_target(false)
	if _powers & Power.GAMBLER:
		body.draw.connect(_draw_gambler)
	attack_component.shoot_override = _release_volley
	attack_component.enable_readable_throws()

## 透明图像安装在原生脸部动画坐标，瞄准和待机时自然一起运动。
func _attach_hat() -> void:
	var source := load(HAT_PATH) as Texture2D # 书目不预加载美术源图。
	if source == null:
		return
	var crop := AtlasTexture.new() # 调用源图的透明区域，不替换现有角色贴图。
	var sample_scale: float = float(source.get_width()) / HAT_SOURCE_WIDTH # 根据导入采样密度映射同一透明区域。
	crop.atlas = source
	crop.region = Rect2(HAT_REGION.position * sample_scale, HAT_REGION.size * sample_scale)
	crop.filter_clip = true
	_popcap_hat = Sprite2D.new()
	_popcap_hat.name = "PopCapHat"
	_popcap_hat.texture = crop
	_popcap_hat.position = Vector2(27.0, 3.5) # 以脸部贴图左上角计，帽冠贴住头顶，帽檐露出眉眼。
	_popcap_hat.rotation = -0.12
	_popcap_hat.scale = Vector2.ONE * (0.052 / sample_scale) # 按头宽配比，给前伸的帽檐保留少量余量。
	_popcap_hat.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_popcap_hat.z_index = 2
	$Body/BodyCorrect/Anim_face.add_child(_popcap_hat)

## 黄油日走同一个原生查找周期，允许只有邻行存在敌人时自动开火。
func _three_lane_target() -> Character000Base:
	if not is_instance_valid(Global.main_game) or Global.main_game.board == null:
		return null
	var nearest: Character000Base # 原版探测到的设施和大型僵王可作为兜底。
	for candidate: Character000Base in attack_component.detect_component.get_all_enemy_can_be_attacked(): # 原行优先，保留原版目标类别。
		if candidate.is_in_group(&"lobber_secondary_targets"):
			continue
		if nearest == null or candidate.hurt_box_component.global_position.x < nearest.hurt_box_component.global_position.x:
			nearest = candidate
	if nearest != null:
		return nearest
	var adjacent: Character000Base = CornBattle.for_battle(Global.main_game).butter_target(self) # 仅在本行无目标时扫描共享行表。
	return adjacent if is_instance_valid(adjacent) else attack_component.detect_component.update_first_enemy()

## 一次离手发完有限的投掷计划，每粒及每块额外黄油按顺序应用赌徒。
func _release_volley() -> void:
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(self) # 额外投掷离场后仍归原卡。
	if shot == null or attack_component._aimed_lane < 0:
		return
	var battle: Node = CornBattle.for_battle(shot.game) # 只建立一份战场运行时。
	var target: Character000Base = attack_component.last_target_enemy if is_instance_valid(attack_component.last_target_enemy) else null # 原生瞄准快照。
	var aim: Vector2 = attack_component.last_target_enemy_global_pos # 目标退场时保留最后位置。
	var row: int = target.lane if is_instance_valid(target) and target.lane >= 0 else attack_component._aimed_lane # 跨行目标仍准确。
	var origin: Vector2 = attack_component.release_origin() # 动画离手时从篮中贴图接到首颗可见弹。
	var lead: float = attack_component.release_delay() # 多次冷却集中在同一动作时，画面稍作错峰。
	var green: bool = (_powers & Power.GREEN) != 0 # 绿色食品屏蔽所有黄油谱系。
	var butter: bool = not green and attack_component.attack_bullet_type == BulletRegistry.BulletType.Bullet011Butter # 起手由原动画抽样。
	var count: int = 0 if butter else 1 + (4 if _powers & Power.HAT else 0) + (2 if green else 0) # 每轮最多七粒。
	var air: bool = (_powers & Power.AIR) != 0 # 每粒都需要独立一次锁定。
	var locks: Array[int] = [] # 未选择空袭无需扫盘。
	if air and count > 0:
		locks = battle.raid_locks(count)
	attack_component.signal_shoot_bullet.emit()
	for index: int in range(count): # 粒弹视觉错开，同一轮状态严格按真实投掷顺序累计。
		var growth: float = 1.0 + (0.5 if _powers & Power.HAT else 0.0) + (0.5 if green else 0.0) # 两本粒弹词条按基础加算。
		var damage: int = shot.scaled_damage(roundi(20.0 * growth * (1.0 + 0.4 * gambler_stacks))) # 这一发只享受已经累积的层数。
		battle.launch(shot, CornBattle.Kind.RAID if air else CornBattle.Kind.KERNEL, target, origin, aim, row,
			lead + index * KERNEL_SPACING, damage, (_powers & Power.POISON) != 0, false, 0.0, locks[index] if air else -1)
		if _powers & Power.GAMBLER:
			gambler_stacks += 1
	if butter:
		_throw_butter(battle, shot, target, origin, aim, row, lead)
	if not green and (_powers & Power.SLIPPERY) != 0 and randf() < 0.30:
		_throw_butter(battle, shot, target, origin, aim, row, lead + maxf(0.10, count * KERNEL_SPACING))
	if _powers & Power.GAMBLER:
		update_speed_factor(_fixed_attack_rate + 0.40 * gambler_stacks, E_Influence_Speed_Factor.AdventurePromotionAttackRate)
		body.queue_redraw()
	if attack_component.is_first_animated_volley():
		attack_component.play_throw_sfx(origin)

## [param battle] 为 [param shot] 的黄油或变异炮弹：[param target]、[param origin]、[param aim]、[param row] 与 [param delay] 已冻结。
func _throw_butter(battle: Node, shot: RepeaterShotContext, target: Character000Base, origin: Vector2,
		aim: Vector2, row: int, delay: float) -> void:
	var cannon: bool = (_powers & Power.GENETIC) != 0 and randf() < 0.30 # 额外黄油也独立抽取变异。
	var time: float = 5.5 if _powers & Power.GAMBLER else 4.0 # 原黄油四秒。
	var damage: int = 1200 if cannon else shot.scaled_damage(roundi(40.0 * (1.0 + 0.4 * gambler_stacks))) # 炮弹固定爆伤，黄油享受出手前伤害。
	battle.launch(shot, CornBattle.Kind.COB if cannon else CornBattle.Kind.BUTTER, target, origin, aim, row,
		delay, damage, false, (_powers & Power.BUTTER_DAY) != 0, time)
	gambler_stacks = 0

## 赌徒层数只在出手改变时重画，用近根部的蓄力粒粒提示连投与清空。
func _draw_gambler() -> void:
	var visible_stacks: int = mini(7, gambler_stacks) # 显示容量只限制画布标记。
	for index: int in range(visible_stacks): # 弧形指示随原株一起移动。
		var orbit: Vector2 = Vector2.RIGHT.rotated(0.25 + index * 0.39) # 沿真实株脚布置，不遮脸或帽子。
		var point: Vector2 = orbit * Vector2(39, 14) + Vector2(0, -8) # 细碎金粒勾勒在草地上。
		body.draw_circle(point, 5.1, Color(0.32, 0.15, 0.07, 0.79), true, -1, true)
		body.draw_circle(point - Vector2(0.6, 0.8), 3.8, Color(1.0, 0.77, 0.22), true, -1, true)
		body.draw_circle(point - Vector2(1.3, 1.6), 1.45, Color(1.0, 0.99, 0.73), true, -1, true)
