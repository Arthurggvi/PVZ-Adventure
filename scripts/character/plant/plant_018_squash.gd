extends Plant000Base
class_name Plant018Squash

## 落地时结算伤害的范围，与起跳前的索敌区域分开。
@onready var area_2d_squash_attack: Area2D = $Area2DSquashAttack
## 起跳前的目标检测，包含普通僵尸的跳跃状态规则。
@onready var detect_component: DetectComponentSquash = $DetectComponent

## 可以攻击的敌人状态
@export_flags("1 正常", "2 悬浮", "4 地刺", "8 低矮") var can_attack_plant_status:int = 13
## 允许落地攻击的普通僵尸状态；僵王按正常状态参与范围检测。
@export_flags("1 正常", "2 跳跃", "4 水下", "8 空中", "16 地下") var can_attack_zombie_status:int = 1
## 一次落地造成的穿透伤害，普通僵尸和僵王共用，默认 1800。
@export_range(0, 10000, 1, "or_greater") var attack_value: int = 1800

@export_group("动画状态")
## 是否已开始攻击，防止重复启动起跳动画。
@export var is_attack: bool = false
## 起跳动画的朝向，按目标受击点的左右位置决定。
@export var is_right:bool = true
## 目标失效后仍使用的起跳目标世界 X 坐标。
var target_x: float = 0.0
## 本次落地是否已结算；重复动画事件不能再次伤害同一批目标。
var _has_squashed: bool = false
## 战斗植株保存这张独立卡片的已选词条。
var _promotion_rules: Dictionary[String, Dictionary] = {}
## 无氧训练归属于出战卡 UID。
var _promotion_uid: String
## 这次种植扣取本株既有训练并给下一株加成。
var _record_training: bool = false
## 成功占格时冻结的本株伤害倍率。
var _training_multiplier: float = 1.0
## 落地未杀伤成功时，原生退场后由同一战场安排愤恨生成。
var _retry_battle: RepeaterShotContext

## 入树前冻结 [param uid] 及 [param events]，不读取战斗节点。
func configure_promotions(uid: String, events: Array[Dictionary]) -> void:
	_promotion_uid = uid
	for event: Dictionary in events: # 同种词条在合法转职链中最多出现一次。
		_promotion_rules[String(event["kind"])] = event.duplicate(true)

## [param origin] 区分实际新种植、愤恨生成和读档；失败的事务不增加训练。
func prepare_placement_action(origin: PlantCell.PlacementOrigin = PlantCell.PlacementOrigin.Player) -> bool:
	_record_training = _promotion_rules.has("squash_training") and origin in [
		PlantCell.PlacementOrigin.Player, PlantCell.PlacementOrigin.Spawned, PlantCell.PlacementOrigin.Transformation]
	return true

## 把上一株累计的倍率交给本株，随后为同 UID 的下一株增加训练。
func commit_placement_action() -> void:
	if not _record_training:
		return
	_record_training = false
	_training_multiplier = AdventureSquashAttack.take_training(_promotion_uid, _promotion_rules["squash_training"])

## [param base_damage] 先按星级、光环及状态结算，再应用本株已冻结的训练。
func promotion_damage(base_damage: int) -> int:
	return roundi(battle_damage(base_damage) * _training_multiplier)

## 保存已成功种下的这株训练结果，读档不会再累计一次。
func gat_save_game_data_plant() -> Dictionary:
	var data: Dictionary = super.gat_save_game_data_plant() # 保留原有占格及血量字段。
	if _training_multiplier > 1.0:
		data["squash_training_multiplier"] = _training_multiplier
	return data

## 将 [param data] 中本株已有的训练恢复给它，兼容未保存字段的旧存档。
func load_game_data_plant(data: Dictionary) -> void:
	super.load_game_data_plant(data)
	_training_multiplier = clampf(float(data.get("squash_training_multiplier", 1.0)), 1.0, 3.0)

## 只在正常完成压砸的原生退场后允许替身进入原格。
func character_death() -> void:
	var battle: RepeaterShotContext = _retry_battle if not is_death and is_can_death_language else null # 铲除不会触发这一递归。
	var home_id: StringName = plant_cell.cell_id if battle != null and is_instance_valid(plant_cell) else &""
	_retry_battle = null
	super()
	if home_id != &"":
		AdventureSquashAttack.enqueue_retry(battle, home_id, plant_spawn_profile, is_imitater_material)

## [param battle] 的这次攻击已实际结束且可重试，原株腾格时才调度。
func arm_resentment(battle: RepeaterShotContext) -> void:
	_retry_battle = battle

## 当前占格上的普通活动门禁也约束本株发出的转职攻击。
func _promotion_battle() -> RepeaterShotContext:
	if _promotion_rules.is_empty() or has_node(NodePath(AdventurePlantNullification.NODE_NAME)):
		return null
	return RepeaterShotContext.from_plant(self)

## 起跳前已锁定原格的落点，攻击过程中不接受换格。
func can_relocate() -> bool:
	return not is_attack

func ready_norm_signal_connect():
	super()
	detect_component.signal_can_attack.connect(attack_start)

## 开始攻击时保存目标位置；僵王取受击组件，普通僵尸保留影子落点。
func attack_start():
	if is_attack:
		return
	# 同步重查目标，避免沿用上一帧已失效的检测结果。
	var enemy: Character000Base = detect_component.update_first_enemy()
	if not is_instance_valid(enemy):
		return
	SoundManager.play_character_SFX("SquashHmm")
	is_attack = true
	target_x = _get_target_x(enemy)
	is_right = target_x > global_position.x
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)


## [param enemy] 已验证的攻击目标；返回世界 X，不改变倭瓜自身的行与地形高度。
func _get_target_x(enemy: Character000Base) -> float:
	if enemy is ZB000Base:
		return enemy.hurt_box_component.global_position.x
	return enemy.shadow.global_position.x

## 开始跳跃
func jump_up_start():
	if _promotion_rules.has("squash_king") and not _has_squashed:
		var battle: RepeaterShotContext = _promotion_battle() # 原生起跳 cue 冻结召唤来源和当前真实占格。
		if battle != null:
			_has_squashed = true
			AdventureSquashAttack.start_king(self, battle, _promotion_rules)
			character_death()
			return
	z_index += 50
	## 如果地形为睡莲或者水
	if plant_cell.curr_condition & 8 or  plant_cell.curr_condition & 16:
		shadow.visible = false

	# 起跳瞬间允许更新有效目标，目标消失则仍跳向此前保存的位置。
	var enemy: Character000Base = detect_component.update_first_enemy()
	# 只移动横坐标，纵向跳跃仍由动画控制。
	var tween:Tween = create_tween()
	if is_instance_valid(enemy):
		tween.tween_property(self, "global_position:x", _get_target_x(enemy) - 18, 0.1667).set_ease(Tween.EASE_IN)
	else:
		tween.tween_property(self, "global_position:x", target_x, 0.1667).set_ease(Tween.EASE_IN)

## 落地只结算一次；普通僵尸保持同行限制，僵王按实际区域和受击窗口结算。
func squash_all_area_zombie():
	if _has_squashed:
		return
	_has_squashed = true
	var battle: RepeaterShotContext = _promotion_battle() # 仅正式出战的已转职植株接管原生落地。
	if battle != null:
		AdventureSquashAttack.land(self, battle, _promotion_rules)
		return
	# 多个受击区域属于同一角色时只伤害一次。
	var seen_ids: Dictionary[int, bool] = {}
	# 当前落地区域，不使用起跳前的目标作为必中的依据。
	for area_reference: Variant in area_2d_squash_attack.get_overlapping_areas():
		if not is_instance_valid(area_reference):
			continue
		# 伤害回调可能释放后续区域，确认有效后才转换。
		var area := area_reference as Area2D
		# 非角色区域安全跳过，不强制转换成普通僵尸。
		var enemy := area.owner as Character000Base
		if not is_instance_valid(enemy) or enemy.is_death or enemy.is_queued_for_deletion():
			continue
		# 本次攻击已处理的角色编号。
		var instance_id: int = enemy.get_instance_id()
		if seen_ids.has(instance_id):
			continue
		seen_ids[instance_id] = true
		if enemy is ZB000Base or (enemy is EnemyStructureBase and enemy.lane == lane):
			if (can_attack_zombie_status & Zombie000Base.E_BeAttackStatusZombie.IsNorm) != 0:
				# 僵王伤害入口再次检查受击窗口，致死时保留状态机死亡演出。
				enemy.be_attacked_bullet(battle_damage(attack_value), BulletRegistry.AttackMode.Penetration, false, false)
		elif enemy is Zombie000Base and enemy.lane == lane:
			if (enemy.curr_be_attack_status & can_attack_zombie_status) != 0:
				enemy.be_squash(battle_damage(attack_value))

## 跳入水中判断
func judge_jump_pool():
	## 如果地形为睡莲或者水
	if plant_cell.curr_condition & 8 or  plant_cell.curr_condition & 16:
		## 水花
		var splash:Splash = SceneRegistry.SPLASH.instantiate()
		plant_cell.add_child(splash)
		splash.global_position = Vector2(global_position.x,plant_cell.global_position.y + plant_cell.size.y)
		splash.z_as_relative = z_as_relative
		splash.z_index = z_index
		character_death()
	else:
		SoundManager.play_character_SFX(&"gargantuar_thump")
