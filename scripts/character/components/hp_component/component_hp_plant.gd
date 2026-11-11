## 植物专用生命组件：可消耗临时护甲与单次有效伤害上限。
## 护甲在固定格挡及百分比减伤之后吸收伤害；脚本强制死亡仍绕过护甲。
extends HpComponent
class_name HpComponentPlant

## 临时护甲池；所有植物均可被守护技能授予护甲。
var bonus_armor: int = 0
## 单次实际战斗伤害上限占最大生命的比例；0 表示不限制。
var max_single_hit_fraction: float = 0.0
## 护甲变化信号；与生命损失分开，不触发坚果破损外观。
signal bonus_armor_changed(amount: int)
## 护甲数值指示，仅存在护甲时显示，跟随生命值显示设置。
var _armor_label: Label

func _ready() -> void:
	super()
	_armor_label = Label.new()
	_armor_label.name = "BonusArmorLabel"
	_armor_label.position = Vector2(-30.0, 14.0)
	_armor_label.add_theme_color_override("font_color", Color(0.48, 0.94, 1.0))
	_armor_label.add_theme_font_size_override("font_size", 12)
	_armor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(%HpControl as Control).add_child(_armor_label)
	_update_armor_label()

## [param amount] 正数表示新授护甲；[param maximum] 可选总护甲上限，-1 无限。
## 返回实际增加的护甲，护甲上限不影响今后其他来源的授予规则。
func grant_bonus_armor(amount: int, maximum: int = -1) -> int:
	if amount <= 0 or is_death or owner_character.is_death:
		return 0
	var granted: int = amount if maximum < 0 else mini(amount, maxi(0, maximum - bonus_armor))
	if granted <= 0:
		return 0
	bonus_armor += granted
	bonus_armor_changed.emit(bonus_armor)
	_update_armor_label()
	return granted

## 护甲吸收经过原版减伤处理后的伤害，留下未吸收的部分交给生命池。
func absorb_temporary_armor(damage: int) -> int:
	if damage <= 0 or bonus_armor <= 0:
		return maxi(0, damage)
	var absorbed: int = mini(damage, bonus_armor)
	bonus_armor -= absorbed
	bonus_armor_changed.emit(bonus_armor)
	_update_armor_label()
	return damage - absorbed

## 临时护甲不参与血量百分比与自动回复，仅参与总血量查询。
func get_all_hp() -> int:
	return curr_hp + bonus_armor

## 所有前置减伤先结算，再施加单次上限，最后进入可消耗护甲。
func resolve_damage(damage: int) -> int:
	var resolved: int = super.resolve_damage(damage)
	if _bypass_damage_block or max_single_hit_fraction <= 0.0:
		return resolved
	return mini(resolved, maxi(1, ceili(float(max_hp) * max_single_hit_fraction)))

## 处决与铲除无视护甲池；当生命被强制清空时一并清除幽灵护甲。
func apply_unblocked_loss(amount: int,
		mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		drop: bool = true, sfx: bool = true, extra_drop: bool = true) -> void:
	if amount >= curr_hp and bonus_armor > 0:
		bonus_armor = 0
		bonus_armor_changed.emit(0)
		_update_armor_label()
	super.apply_unblocked_loss(amount, mode, drop, sfx, extra_drop)

func _update_armor_label() -> void:
	if is_instance_valid(_armor_label):
		_armor_label.visible = bonus_armor > 0
		_armor_label.text = "护甲 %d" % bonus_armor
