## 保留原生孢子碰撞与外观，只补充距离伤害、实际击杀归属和命中负面效果。
extends BulletLinear000Base
class_name AdventurePuffProjectileEffects

## 发射所属战场，母株死亡不影响已发出的弹体。
var _game: MainGameManager
## 发射所属轮次，防止同场景下一轮收到旧弹体或晚到命中。
var _round_index: int = 0
## 不可变来源配方，用于直接击杀或中毒击杀后的繁殖。
var _profile: PlantSpawnProfile
## 每颗孢子独立保存的转职规则。
var _rules: Dictionary = {}
## 世界坐标出生点，命中距离与射程均使用同一坐标空间。
var _origin: Vector2
## 发射时冻结的真实列间距，单位像素。
var _cell_pitch: float = 1.0
## 来源植物实例身份，仅作为状态来源键，不保存植物引用。
var _source_id: int = 0
## 本次实际从存活变死亡的角色，伤害转移时可为保护者。
var _casualty: Character000Base

## [param game] 为所属战场；[param profile] 为不可变来源；[param rules] 为冻结事件。
## [param origin] 是世界出生点；[param cell_pitch] 是一格像素间距；[param source_id] 是来源身份。
## 在原生初始化和入树之前调用，不重复应用卡片伤害倍率。
func configure(game: MainGameManager, profile: PlantSpawnProfile, rules: Dictionary,
		origin: Vector2, cell_pitch: float, source_id: int) -> void:
	_game = game
	_round_index = game.curr_game_round
	_profile = profile
	_rules = rules.duplicate(true)
	_origin = origin
	_cell_pitch = maxf(1.0, cell_pitch)
	_source_id = source_id

## 延迟入树回调由弹体自己持有，不依赖已死亡的植物；失效时立即释放离树弹体。
func attach_to_battle() -> void:
	if get_parent() != null:
		return
	if not _battle_active() or not is_instance_valid(_game.bullets) \
			or _game.bullets.is_queued_for_deletion() or not _game.bullets.is_inside_tree():
		free()
		return
	_game.bullets.add_child(self)

## [param delta] 为本物理帧秒数；结算或换轮后先回收，再考虑移动和射程。
func _physics_process(delta: float) -> void:
	if not _battle_active():
		queue_free()
		return
	movement_component.physics_process_bullet_move(delta)
	if global_position.distance_to(_origin) > max_distance:
		queue_free()

## [param enemy] 为原生碰撞确认的目标；空值仍交给原版处理撞坡特效。
## 在正常扣血之前改本次攻值，之后恢复；同一弹仅在真实消耗命中次数时触发能力。
func attack_once(enemy: Character000Base):
	if not _battle_active():
		queue_free()
		return
	if is_queued_for_deletion() or (max_attack_num >= 0 and curr_attack_num >= max_attack_num):
		return
	if enemy != null and not _can_attack_character(enemy):
		return
	var previous_count: int = curr_attack_num # 用计数变化区分正常命中与僵王重复受击框。
	var original_damage: int = attack_value # 已包含发射时卡片和光环倍率的原始攻值。
	_casualty = null
	if enemy != null:
		attack_value = maxi(0, roundi(float(original_damage) * _distance_factor()))
	super(enemy)
	attack_value = original_damage
	if curr_attack_num == previous_count or not _battle_active():
		return
	if is_instance_valid(enemy) and enemy is ZB000Base and enemy.is_death:
		_casualty = enemy
	if is_instance_valid(_casualty) and _rules.has("puff_infection") and _profile != null:
		AdventurePuffPropagation.infect(_casualty, _profile)
	if is_instance_valid(enemy) and not enemy.is_death and not enemy.is_queued_for_deletion() \
			and not enemy.is_hypno and (enemy is Zombie000Base or enemy is ZB000Base):
		_apply_corpse_effect(enemy)

## [param zombie] 为直接碰撞目标；沿用原生背击真实伤害和受击闪白。
## 普通生命入口丢弃击杀返回值，此处直接保留同一生命组件返回的实际死亡角色。
func _attack_zombie(zombie: Zombie000Base):
	var mode: BulletRegistry.AttackMode = bullet_mode # 维持线性弹从背后绕过二类防具的规则。
	if direction.x < 0.0 and mode == BulletRegistry.AttackMode.Norm:
		mode = BulletRegistry.AttackMode.Real
	_casualty = (zombie.hp_component as HpComponentZombie).apply_hit(
		attack_value, mode, true, trigger_be_attack_sfx)
	if is_instance_valid(zombie) and is_instance_valid(zombie.body):
		zombie.body.body_light()

## 孢涌含边界：飞行距离不超过半格为二倍，超过半格但不超过一格为原伤，之外为半伤。
## 礼物只继承这份伤害档位，不再次增加亡语弹数。
func _distance_factor() -> float:
	if not _rules.has("puff_shotgun"):
		return 1.0
	var rule: Dictionary = _rules["puff_shotgun"] # 权威目录给定的距离档位。
	var distance: float = global_position.distance_to(_origin) / _cell_pitch # 本颗孢子的实际命中格距。
	if distance <= float(rule.get("point_blank_cells", 0.5)):
		return float(rule.get("point_blank_factor", 2.0))
	return float(rule.get("near_factor", 1.0)) if distance <= 1.0 else float(rule.get("far_factor", 0.5))

## 返回弹体仍处于原战场正式战斗中；结算或场景释放后停止附加效果。
func _battle_active() -> bool:
	return is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.get_tree().current_scene == _game \
		and _game.curr_game_round == _round_index \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## [param target] 已实际被孢子命中；格挡或护甲吸收不取消命中概率。
## 先判定百分之六十，再用一次权重抽签选择恰好一种状态。
func _apply_corpse_effect(target: Character000Base) -> void:
	if not _rules.has("puff_corpse"):
		return
	var rule: Dictionary = _rules["puff_corpse"] # 本次命中的概率、权重和状态数值。
	if randf() >= clampf(float(rule.get("chance", 0.6)), 0.0, 1.0):
		return
	var context: Dictionary = {} # 中毒归属绑定静态函数和配方，不绑定即将销毁的弹体。
	if _rules.has("puff_infection") and _profile != null:
		context["on_kill"] = AdventurePuffPropagation.infect.bind(_profile)
	match _weighted_index(rule):
		0:
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.POISON,
				_source_id, float(rule.get("poison_seconds", 5.0)), 0.0, context)
		1:
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.DEGRADATION,
				_source_id, float(rule.get("degradation", 0.05)), 0.0, {"stackable": true})
		2:
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.ICE_SLOW,
				_source_id, float(rule.get("slow_seconds", 5.0)))
		3:
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.STUN,
				_source_id, float(rule.get("stun_seconds", 0.5)))
		4:
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.CHARM, _source_id)

## [param rule] 的前五项依次为毒、劣化、寒冷、眩晕、魅惑；全零权重返回负一。
func _weighted_index(rule: Dictionary) -> int:
	var weights: Array = rule.get("weights", [2, 2, 2, 2, 1]) # 默认魅惑为其他每项的一半权重。
	var total: float = 0.0 # 所有合法权重之和。
	for index: int in range(mini(5, weights.size())): # 只枚举既定五种状态。
		total += maxf(0.0, float(weights[index]))
	if total <= 0.0:
		return -1
	var roll: float = randf() * total # 本次唯一的权重抽签。
	for index: int in range(mini(5, weights.size())): # 逐段扣除累计权重。
		roll -= maxf(0.0, float(weights[index]))
		if roll < 0.0:
			return index
	return -1
