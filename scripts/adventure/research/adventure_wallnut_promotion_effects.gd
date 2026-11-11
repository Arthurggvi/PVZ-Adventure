## 坚果墙转职的实例化生命周期技能：每株独立持有回复、护甲、亡语和守护进度。
## 无全局轮询；冻结卡片生成时附着在植物上，随植株死亡释放。
extends Node
class_name AdventureWallnutPromotionEffects

## 坚果保龄球弹体场景路径，在亡语触发时加载以避免与战斗脚本循环依赖。
const BOWLING_SCENE_PATH := "res://scenes/bullet/bullet_1001_bowling.tscn"
## 每次到达的固定逻辑秒间隔。
const TICK_SECONDS := 1.0

## 当前技能拥有者，仅在出战植物有效时读写。
var _plant: Plant000Base
## 从转职目录截取的事件集合，不依赖可变玩家背包。
var _rules: Dictionary = {}
## 未受伤害的累计时间，受实际本体扣血重置。
var _regen_elapsed: float = 0.0
## 未被攻击的累计时间，收到攻击即重置（即使伤害被护甲吸收）。
var _armor_elapsed: float = 0.0
## 守护尚未达到下一次触发阈值的实际生命损失。
var _guard_remainder: int = 0
## 保龄球亡语幂等标志，防止死亡与铲除的重入。
var _bowled: bool = false

## [param plant] 这株坚果；[param effects] 转职目录中已验证的非静态效果。
func configure(plant: Plant000Base, effects: Array[Dictionary]) -> void:
	_plant = plant
	for effect: Dictionary in effects:
		var kind: String = str(effect.get("kind", ""))
		if kind.begins_with("wallnut_"):
			_rules[kind] = effect.duplicate(true)

func _ready() -> void:
	if not is_instance_valid(_plant):
		push_error("坚果转职缺少有效植物")
		set_process(false)
		return
	var hp: HpComponentPlant = _plant.get_node_or_null("HpComponent") as HpComponentPlant
	if hp == null:
		push_error("坚果转职必须使用植物专用护甲生命组件")
		set_process(false)
		return
	hp.combat_attack_received.connect(_on_attacked)
	hp.combat_hp_damaged.connect(_on_hp_damage)
	if _rules.has("wallnut_bowling_on_death"):
		_plant.signal_character_death.connect(_on_death, CONNECT_ONE_SHOT)
	set_process(_rules.has("wallnut_regen") or _rules.has("wallnut_armor_growth"))

## 只根据本次实际攻击重置“脱战积甲”，护甲受击也算被攻击。
func _on_attacked(_amount: int) -> void:
	_armor_elapsed = 0.0

## [param amount] 已扣掉防具与护甲后的实际本体伤害，触发守护与回复计时重置。
func _on_hp_damage(amount: int) -> void:
	if amount <= 0:
		return
	_regen_elapsed = 0.0
	if not _rules.has("wallnut_guard") or not is_instance_valid(_plant):
		return
	if _plant.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	var rule: Dictionary = _rules["wallnut_guard"]
	var threshold: int = maxi(1, int(rule.get("health_per_trigger", 20)))
	_guard_remainder += amount
	var triggers: int = floori(float(_guard_remainder) / float(threshold))
	_guard_remainder %= threshold
	if triggers > 0:
		_grant_neighbors(triggers * maxi(0, int(rule.get("armor_per_trigger", 20))),
			maxi(0, int(rule.get("range", 2))))

## 按同排前后各 [param reach] 格分发可叠加护甲；同一植物只处理一次。
func _grant_neighbors(amount: int, reach: int) -> void:
	var game: MainGameManager = Global.main_game
	if amount <= 0 or not is_instance_valid(game) or not is_instance_valid(game.plant_cell_manager):
		return
	var rows: Array = game.plant_cell_manager.all_plant_cells
	if _plant.row_col.x < 0 or _plant.row_col.x >= rows.size():
		return
	var cells: Array = rows[_plant.row_col.x]
	var seen: Dictionary[int, bool] = {}
	for direction: int in [-1, 1]:
		for distance: int in range(1, reach + 1):
			var column: int = _plant.row_col.y + direction * distance
			if column < 0 or column >= cells.size():
				continue
			var cell: PlantCell = cells[column]
			for entry: Variant in cell.plant_in_cell.values():
				var candidate: Plant000Base = entry as Plant000Base
				if not is_instance_valid(candidate) or candidate.is_death \
						or candidate == _plant or seen.has(candidate.get_instance_id()):
					continue
				seen[candidate.get_instance_id()] = true
				var hp: HpComponentPlant = candidate.hp_component as HpComponentPlant
				if hp != null:
					hp.grant_bonus_armor(amount)

## 每株独立固定一秒积累；失去目标处理不影响不同植株的计时。
func _process(delta: float) -> void:
	if not is_instance_valid(_plant) or _plant.is_death:
		return
	var hp: HpComponentPlant = _plant.get_node_or_null("HpComponent") as HpComponentPlant
	if hp == null or hp.is_death:
		return
	if _rules.has("wallnut_regen"):
		var regen: Dictionary = _rules["wallnut_regen"]
		_regen_elapsed += delta
		while _regen_elapsed >= TICK_SECONDS:
			_regen_elapsed -= TICK_SECONDS
			hp.heal(maxi(1, ceili(float(hp.max_hp) * float(regen.get("per_second", 0.05)))))
	if _rules.has("wallnut_armor_growth"):
		var growth: Dictionary = _rules["wallnut_armor_growth"]
		_armor_elapsed += delta
		while _armor_elapsed >= TICK_SECONDS:
			_armor_elapsed -= TICK_SECONDS
			hp.grant_bonus_armor(int(growth.get("per_second", 100)),
				int(growth.get("cap", 1000)))

## “任何形式死亡”由角色既有死亡事件统一通知；直接生成原版滚动弹体。
func _on_death() -> void:
	if _bowled:
		return
	_bowled = true
	if not is_instance_valid(_plant) or not _plant.is_inside_tree():
		return
	var game: MainGameManager = Global.main_game
	if not is_instance_valid(game) or not is_instance_valid(game.bullets):
		return
	# 进入战斗后才加载弹体，此时场景依赖的脚本已完成初始化。
	var bowling_scene := load(BOWLING_SCENE_PATH) as PackedScene
	if bowling_scene == null:
		push_error("无法加载坚果保龄球场景")
		return
	var projectile: Bullet000NormBase = bowling_scene.instantiate() as Bullet000NormBase
	if projectile == null:
		push_error("坚果保龄球资源类型不匹配")
		return
	projectile.init_bullet({
		Bullet000NormBase.E_InitParasAttr.BulletLane: _plant.lane,
		Bullet000NormBase.E_InitParasAttr.Position: game.bullets.to_local(_plant.global_position),
	})
	game.bullets.add_child(projectile)
