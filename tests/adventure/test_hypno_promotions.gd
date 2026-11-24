## 使用正式棋盘、卡片、受伤与僵尸登记回归魅惑菇转职。
extends Node

const HYPNO := CharacterRegistry.PlantType.P013HypnoShroom
const NORMAL := CharacterRegistry.ZombieType.Z001Norm
const CONE := CharacterRegistry.ZombieType.Z003Cone
const LibraryRules = preload("res://scripts/adventure/library/library_rules.gd")
const BOOKS := [
	["day_awake", "release"], ["splash", "remodel"], ["illusion", "madness"], ["malice", "infection"],
]

var _game: MainGameManager
var _card: Card
var _failures: int = 0

## 验收节点独立于当前战场，切换昼夜后继续运行。
func _ready() -> void:
	get_tree().current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

## 为 [param ok] 的可观察结果登记失败信息 [param message]。
func _check(ok: bool, message: String) -> bool:
	if not ok:
		_failures += 1
		printerr("HYPNO_FAIL ", message)
	return ok

## 验证真实局内入口，避免触碰正式存档。
func _run() -> void:
	if not _check(OS.get_user_data_dir().contains("hypno-audit"), "isolated user directory"):
		get_tree().quit(1)
		return
	Global.save_service.stop_autosave()
	_catalog()
	if await _open_board(true):
		await _daylight_illusion()
		await _wake_illusion()
		await _spores()
		await _infection()
		await _malice()
	if await _open_board(false):
		await _night_illusion()
		if OS.get_cmdline_user_args().has("--profile-infection"):
			await _infection_load()
	print("HYPNO_RESULT=", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)

## 研究室、图书馆和库存读取同一份四阶书目。
func _catalog() -> void:
	var card: PlantCardInstance = _record([])
	for tier: int in range(1, 5):
		var expected: Array[String] = []
		for suffix: String in BOOKS[tier - 1]:
			var id: String = "promotion_hypno_" + suffix
			expected.append(id)
			_check(ItemRegistry.has_item(id), "registered item " + id)
		var options: Array[String] = []
		for book: Dictionary in AdventurePromotionCatalog.options(card):
			options.append(book.id)
		_check(options == expected and LibraryRules.pool(tier, HYPNO) == expected, "research and library tier %d" % tier)
		card.set_promotion(tier, expected[0])
	_check(AdventurePromotionCatalog.next_tier(card) == 0, "promotion finishes at four tiers")

## [param day] 控制原生睡眠。禁止与本验证无关的自动出怪与天降阳光。
func _open_board(day: bool) -> bool:
	var level: ResourceLevelData = load("res://resources/level_date_resource/mode_adventure/adventure_03_pool.tres").duplicate(true)
	level.is_day = day
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_day_sun = false
	level.start_sun = 3000
	level.prechosen_cards = [ResourceCardReference.create(ResourceCardReference.CardType.Plant, HYPNO)]
	Global.game_para = level
	if not _check(get_tree().change_scene_to_file("res://scenes/main/MainGame02Back.tscn") == OK, "open real battle"):
		return false
	for _frame: int in range(360):
		await get_tree().physics_frame
		_game = Global.main_game
		if is_instance_valid(_game) and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
			var slots: CardSlotBattle = _game.card_manager.card_slot_battle
			if slots != null and not slots.curr_cards.is_empty() and slots.curr_cards[0].card_context == Card.CardContext.Battle:
				_card = slots.curr_cards[0]
				return true
	return _check(false, "battle card did not become ready")

## [param suffixes] 指定每一阶的选择，使用真实卡片快照。
func _record(suffixes: Array[String]) -> PlantCardInstance:
	var card := PlantCardInstance.new()
	card.uid = "PC000013"
	card.plant_type = HYPNO
	card.stars = 10
	for index: int in range(suffixes.size()):
		card.set_promotion(index + 1, "promotion_hypno_" + suffixes[index])
	return card

## 通过手持与卡槽事务在 [param cell] 种下具有 [param suffixes] 的魅惑菇。
func _plant(cell: PlantCell, suffixes: Array[String]) -> Plant013HypnoShroom:
	_card.plant_spawn_profile = PlantSpawnProfile.create(_record(suffixes).to_dict(), AdventureResearchBattleEffects.new())
	_card.set_card_cool_end()
	_card.judge_card_ready()
	_game.hand_manager._click_card(_card)
	var planted: bool = _game.hand_manager.hm_character.click_cell(cell)
	_game.hand_manager._cancel_selection()
	_check(planted, "card placement " + str(suffixes))
	return cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] as Plant013HypnoShroom

## [param row]、[param column] 均从零起算。
func _at(row: int, column: int) -> PlantCell:
	return _game.board.cell_at(Vector2i(row, column))

## 在 [param cell] 生成真实的 [param kind]，以 [param dx] 控制近远，同属 [param tier]。
func _spawn(cell: PlantCell, kind: CharacterRegistry.ZombieType = NORMAL, dx: float = 0.0,
		tier: StringName = &"") -> Zombie000Base:
	var manager: ZombieManager = _game.zombie_manager
	var row: ZombieRow = manager.all_zombie_rows[cell.combat_lane]
	var modifier: ZombieSpawnModifier = AdventureZombieTierBinding.new(tier) if not tier.is_empty() else null
	var zombie: Zombie000Base = manager.create_norm_zombie(kind, row, {
		Zombie000Base.E_ZInitAttr.Lane: cell.combat_lane,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType: cell.get_spawn_terrain_type(),
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
	}, cell.get_spawn_global_position() + Vector2(dx, 0.0), Callable(), modifier)
	if _check(is_instance_valid(zombie), "create zombie fixture"):
		zombie.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsDisable)
		zombie.drop_item_component.drop_coin_rate = 0.0
	return zombie

## 释放本用例的占格和敌人，留给原战场处理延迟释放。
func _clear() -> void:
	for zombie: Zombie000Base in _game.zombie_manager.all_zombies_1d.duplicate():
		if is_instance_valid(zombie):
			zombie.retire_from_battle()
	for cell: PlantCell in _game.board.cells():
		for plant: Plant000Base in cell.living_plants():
			plant.be_shovel_kill()
	await _frames(2)

## 等待固定 [param count] 帧，结束条件始终有界。
func _frames(count: int) -> void:
	for _frame: int in range(count):
		await get_tree().physics_frame

## 白昼耐性立即发动九宫格的一次魅惑，并减去三秒卡片冷却。
func _daylight_illusion() -> void:
	var inside: Zombie000Base = _spawn(_at(1, 4))
	var outside: Zombie000Base = _spawn(_at(1, 5))
	var mushroom: Plant013HypnoShroom = _plant(_at(0, 3), ["day_awake", "remodel", "illusion"])
	if mushroom != null:
		_check(not mushroom.is_sleeping and is_equal_approx(_card.cool_time, _card._registry_cooldown - 3.0), "daylight and cooldown")
		_check(inside.is_hypno and not outside.is_hypno, "daylight 3x3 includes diagonal and excludes outer column")
		_check(mushroom.sleep_component.has_awake_sources() == false, "daylight does not create temporary waking source")
	await _clear()

## 日眠分支等待原生唤醒；五阶满级仍获得独立三秒无敌。
func _wake_illusion() -> void:
	var inside: Zombie000Base = _spawn(_at(1, 4), CONE, 0.0, &"tier5")
	var max_hp: int = inside.hp_component.max_hp
	var outside: Zombie000Base = _spawn(_at(0, 5))
	var mushroom: Plant013HypnoShroom = _plant(_at(0, 3), ["release", "remodel", "illusion"])
	if mushroom != null:
		_check(mushroom.is_sleeping and not inside.is_hypno, "daytime mushroom waits while asleep")
		mushroom.sleep_component.wake_permanently()
		_check(inside.is_hypno and not outside.is_hypno, "native wake triggers exact 3x3")
		_check(inside.hp_component.is_damage_immune() and inside.hp_component.max_hp == max_hp, "max tier still gains immunity")
		await _frames(196)
		_check(not inside.hp_component.is_damage_immune(), "release invulnerability expires")
	await _clear()

## 孢子取清醒时真实死亡的最近四名。铲除和日眠死亡不发动。
func _spores() -> void:
	var targets: Array[Zombie000Base] = []
	for index: int in range(5):
		targets.append(_spawn(_at(0, 3 + index)))
	var immune: Zombie000Base = _spawn(_at(1, 3), CharacterRegistry.ZombieType.Z013Zamboni) # 冰道留在另一行，后续末列仍可种。
	var mushroom: Plant013HypnoShroom = _plant(_at(0, 3), ["day_awake", "splash"])
	if mushroom != null:
		mushroom.be_zombie_eat_once(targets[0])
		_check(not mushroom.is_death and not targets[0].is_hypno, "spores replaces ordinary bite charm")
		mushroom.be_zombie_eat(10000, targets[0])
		for index: int in range(targets.size()):
			_check(targets[index].is_hypno == (index < 4), "nearest four %d" % index)
		_check(not immune.is_hypno, "uncharmable nearby enemy does not use a spore slot")
	await _clear()
	var enemy: Zombie000Base = _spawn(_at(0, 3))
	mushroom = _plant(_at(0, 3), ["release", "splash"])
	if mushroom != null:
		mushroom.be_zombie_eat(10000, enemy)
		_check(not enemy.is_hypno, "asleep spores do not charm")
	await _frames(2)
	mushroom = _plant(_at(0, 3), ["day_awake", "splash"])
	if mushroom != null:
		mushroom.be_shovel_kill()
		_check(not enemy.is_hypno, "shoveling does not trigger a death effect")
	await _clear()

## 原生低伤和实际击杀走同一啃食入口，复制按实际死亡时间快照健康和状态。
func _infection() -> void:
	var source: Zombie000Base = _spawn(_at(0, 3), CONE)
	var old_hp: int = source.hp_component.max_hp
	var mushroom: Plant013HypnoShroom = _plant(_at(0, 3), ["release", "remodel", "madness", "infection"])
	if mushroom == null:
		return
	_check(mushroom.is_sleeping, "release branch remains asleep by day")
	mushroom.sleep_component.wake_permanently()
	var battle: RepeaterShotContext = RepeaterShotContext.from_plant(mushroom) # 原菇死亡后仍保留真实战局身份。
	mushroom.be_zombie_eat_once(source)
	if not _check(source.is_hypno and mushroom.is_death, "native bite still charms and consumes"):
		return
	var hp := source.hp_component as HpComponentZombie
	_check(source.adventure_tier_id == &"veteran" and hp.max_hp > old_hp, "release raises tier and stats")
	_check(hp.is_damage_immune(), "release starts immunity")
	var attack := source.attack_component as AttackComponentZombieNorm
	var bite: int = attack.curr_attack_value_per_min
	attack.signal_change_is_attack.emit(true)
	_check(is_equal_approx(source.action_rate(), 2.0) and attack.curr_attack_value_per_min == bite, "remodel doubles cadence without doubling each bite")
	attack.signal_change_is_attack.emit(false)
	_check(is_equal_approx(source.action_rate(), 1.0), "remodel preserves non-attack cadence")
	_check(source.has_node(NodePath(AdventureSunBeanEffect.NODE_NAME)), "remodel grants ally light")
	await _frames(88)
	hp.max_hp = 1000
	hp.death_hp = 0
	hp.curr_hp = 100
	hp.grant_bonus_armor(23)
	hp.apply_degradation(0.1)
	AdventureDeepCold.apply_to(source, battle, 1.7, 0.0, int(source.curr_be_attack_status))
	var enemy: Zombie000Base = _spawn(_at(1, 5))
	enemy.drop_item_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	# 先搜到会通过真实 20% 条件的种子，正式击杀前恢复同一个随机状态。
	var selected_seed: int = 0
	for candidate: int in range(100):
		seed(candidate)
		if randf() < 0.2:
			selected_seed = candidate
			break
	seed(selected_seed)
	enemy.be_zombie_eat(1, source)
	_check(_game.zombie_manager.all_zombies_be_hypno.size() == 1, "nonlethal bite cannot clone")
	seed(selected_seed)
	enemy.be_zombie_eat(10000, source)
	hp.curr_hp = 200
	await _frames(2)
	var allies: Array[Zombie000Base] = _game.zombie_manager.all_zombies_be_hypno
	if _check(allies.size() == 2, "real lethal bite yields one charm clone"):
		var clone: Zombie000Base = allies[1]
		var clone_hp := clone.hp_component as HpComponentZombie
		_check(clone_hp.curr_hp == 100 and clone_hp.max_hp == 1000 and clone_hp.bonus_armor == 23
			and clone_hp.curr_hp_armor1 == hp.curr_hp_armor1 and clone.adventure_tier_id == source.adventure_tier_id
			and not clone.participates_natural_refresh, "clone has frozen body/armor, tier and ally ownership")
		_check(clone_hp.is_damage_immune() and clone.has_node(NodePath(AdventureSunBeanEffect.NODE_NAME)), "active release and remodel light inherited")
		_check(clone_hp.outgoing_damage(100) == 252, "missing HP and degradation both inherited")
		_check(clone.influence_speed_factors.get(Character000Base.E_Influence_Speed_Factor.DeepColdSlow) == 0.5, "active deep cold inherited")
		await _frames(108)
		_check(clone.influence_speed_factors.get(Character000Base.E_Influence_Speed_Factor.DeepColdSlow) == 1.0, "cloned deep cold expires independently")
		_check(not hp.is_damage_immune() and not clone_hp.is_damage_immune(), "cloned immunity keeps remaining duration")
		_check(clone_hp.resolve_damage(100) == 22, "80% actual mitigation capped with inherited 10% vulnerability")
		clone_hp.curr_hp = 550
		_check(clone_hp.outgoing_damage(100) == 171 and clone_hp.resolve_damage(100) == 61, "heal recalculates damage and mitigation")
		clone_hp.clear_degradation()
		clone_hp.curr_hp = 199
		_check(clone_hp.resolve_damage(100) == 20, "80% actual mitigation even above native soft cap")
		clone.be_attacked_bullet(100, BulletRegistry.AttackMode.Real, false, false)
		_check(clone_hp.bonus_armor == 3 and clone_hp.curr_hp == 199, "real hit mitigated before armor routing")
		_check(hp.total_degradation_fraction() > 0.0, "clone modifiers are independent")
		var protected_enemy: Zombie000Base = _spawn(_at(1, 5)) # 本次真死者是接管伤害的其他僵尸。
		var protector: Zombie000Base = _spawn(_at(1, 5), CONE, 20.0)
		protector.drop_item_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
		var protected_hp := protected_enemy.hp_component as HpComponentZombie
		protected_hp.damage_transfer.set_source(protector.get_instance_id(), protector, 90.0)
		seed(selected_seed)
		protected_enemy.be_zombie_eat(10000, clone)
		await _frames(2)
		_check(not protected_enemy.is_death and (not is_instance_valid(protector) or protector.is_death)
			and allies.size() == 3, "clone inherits infection and transfers real kill credit")
	await _clear()

## 自然跨边缘后只爆炸一次，邻格和外圈仍使用真实棋盘。
func _malice() -> void:
	var cell: PlantCell = _at(0, 8)
	var source: Zombie000Base = _spawn(cell)
	var inside: Zombie000Base = _spawn(_at(1, 7))
	var outside: Zombie000Base = _spawn(_at(1, 6))
	var manager: ZombieManager = _game.zombie_manager # 出生与 Boss 血条登记走真实入口。
	var boss_point: Vector2 = manager.zombie_boss_root.to_local(_at(1, 8).get_spawn_global_position())
	var boss: ZB002BlackGeneral = manager.try_create_boss_from_card(CharacterRegistry.ZombieBossType.ZB002BlackGeneral, boss_point)
	await _frames(3) # 等待原生入场定位后再打开测试受击窗口。
	var boss_hp: int = 0 # 用同次爆炸前后的可观察本体差值验收。
	if _check(is_instance_valid(boss), "registered boss fixture"):
		boss.set_physics_process(false)
		boss.visual.player.pause()
		boss._set_invulnerable(false)
		boss.global_position = _at(1, 8).get_spawn_global_position()
		boss_hp = boss.hp_component.curr_hp
	var mushroom: Plant013HypnoShroom = _plant(cell, ["day_awake", "remodel", "madness", "malice"])
	if mushroom != null:
		mushroom.be_zombie_eat_once(source)
		var right: float = cell.get_global_rect().end.x
		var hp_before: int = outside.hp_component.curr_hp
		source.global_position.x = right + 1.0 # 直接从地块内跳过边界，特效不得误判为右行。
		await _frames(2)
		_check(is_instance_valid(inside) and not inside.is_death, "teleport does not trigger edge explosion")
		source.global_position.x = right - 1.0
		await _frames(2)
		_check(is_instance_valid(inside) and not inside.is_death, "not yet at right edge")
		source.move_component.update_move_mode(MoveComponent.E_MoveMode.Speed)
		source.move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsDisable)
		await _frames(24)
		_check(not is_instance_valid(inside) or inside.is_death, "right edge causes blast in neighboring row and column")
		_check(outside.hp_component.curr_hp == hp_before, "blast does not reach outside row cells")
		if is_instance_valid(boss):
			_check(boss_hp - boss.hp_component.curr_hp == 300, "boss takes exactly one 300-point hit")
		var late: Zombie000Base = _spawn(_at(1, 8))
		await _frames(8)
		_check(not late.is_death, "edge blast is single-use")
	if is_instance_valid(boss):
		boss.queue_free()
	await _clear()

## 夜战无需先睡醒，种下立即魅惑。
func _night_illusion() -> void:
	var target: Zombie000Base = _spawn(_at(1, 4))
	var mushroom: Plant013HypnoShroom = _plant(_at(0, 3), ["release", "remodel", "illusion"])
	if mushroom != null:
		_check(not mushroom.is_sleeping and target.is_hypno, "night planting immediately casts")
	await _clear()

## 可选性能侦察：让同一帧的真实击杀批量调度感染。计时覆盖结算及已推迟的角色生成。
func _infection_load() -> void:
	const KILLS: int = 96 # 限制验证中的生成规模，避免留下长时后台战局。
	var source: Zombie000Base = _spawn(_at(0, 3)) # 同一只原生友军做本次所有击杀。
	var mushroom: Plant013HypnoShroom = _plant(_at(0, 3), ["day_awake", "remodel", "madness", "infection"])
	if mushroom == null:
		return
	mushroom.be_zombie_eat_once(source)
	var enemies: Array[Zombie000Base] = [] # 测量从战斗命中开始，不含准备的敌人生成。
	for index: int in range(KILLS):
		var enemy: Zombie000Base = _spawn(_at(1, 6), NORMAL, float(index % 20))
		enemy.drop_item_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
		enemies.append(enemy)
	var expected: int = 0 # 使用每个种子的第一组真实随机值核对 20% 门槛。
	for index: int in range(KILLS):
		seed(index)
		expected += int(randf() < 0.2)
	var spawned_per_frame: Dictionary[int, int] = {} # 用真实僵尸发布信号记录每帧新增个体。
	var on_spawn: Callable = func(zombie: Zombie000Base) -> void:
		if zombie.is_hypno:
			var frame: int = Engine.get_process_frames()
			spawned_per_frame[frame] = spawned_per_frame.get(frame, 0) + 1
	var manager: ZombieManager = _game.zombie_manager
	manager.signal_zombie_created.connect(on_spawn)
	var started: int = Time.get_ticks_usec() # 从首个伤害结算开始计时。
	for index: int in range(KILLS):
		seed(index)
		enemies[index].be_zombie_eat(10000, source)
	var elapsed_hits: int = Time.get_ticks_usec() - started
	for _frame: int in range(KILLS): # 有界等待队列清空，超时仍报告已经生成的数量。
		if manager.all_zombies_be_hypno.size() - 1 >= expected:
			break
		await get_tree().process_frame
	manager.signal_zombie_created.disconnect(on_spawn)
	var copies: int = manager.all_zombies_be_hypno.size() - 1
	var peak: int = int(spawned_per_frame.values().max()) if not spawned_per_frame.is_empty() else 0
	_check(copies == expected and copies > 0, "burst infection emits exactly its successful rolls")
	_check(peak <= ZombieUpdateScheduler.MAX_DEFERRED_SPAWNS and spawned_per_frame.size() > 1, "burst is distributed across frames")
	print("HYPNO_LOAD kills=", KILLS, " copies=", copies, " frames=", spawned_per_frame.size(),
		" peak_copies_per_frame=", peak, " hit_us=", elapsed_hits, " elapsed_us=", Time.get_ticks_usec() - started)
	await _clear()
