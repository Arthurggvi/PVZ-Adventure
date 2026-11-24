## 复用逐帧动画组件，在咬合帧产生原生反馈，并把坠落表现留在所属战斗行。
extends ImportedZombieAnimator
class_name RocketImpPresentation

## 压缩帧 8 与素材的原始第 16 帧同在一倍速的 16/60 秒处。
const BITE_CONTACT_FRAME: int = 8
## 坠落节点只持有共享帧资源和死亡瞬间的绘制信息。
const DeathSprite = preload("res://scripts/character/zombie/rocket_imp/rocket_imp_death.gd")


## 展示实例启动默认待机；只有实战实例监听咬合帧、切换行动动画。
func _ready() -> void:
	super()
	if _zombie.character_init_type == Character000Base.E_CharacterInitType.IsNorm:
		_sprite.frame_changed.connect(_on_sprite_frame_changed)
	else:
		set_process(false)


## 将有效咬合转发到普通攻击反馈。植物扣血仍由物理攻击间隔结算。
func _on_sprite_frame_changed() -> void:
	if _sprite.animation != &"eat" or _sprite.frame != BITE_CONTACT_FRAME:
		return
	if _stopped or _zombie.is_death or not _zombie.is_attack or _zombie.is_action_suspended():
		return
	var attack: AttackComponentZombieNorm = _zombie.attack_component # 保存当前攻击入口及其索敌结果。
	if not attack.is_attack_res:
		return
	var target: Character000Base = attack.detect_component.enemy_can_be_attacked # 当前啃咬的活体。
	if is_instance_valid(target):
		if not target.is_death and not target.is_queued_for_deletion():
			attack.attack_once()
		return
	var brain: BrainOnZombieMode = attack.detect_component.brain # 我是僵尸模式的独立目标。
	if is_instance_valid(brain) and not brain.is_death and not brain.is_queued_for_deletion():
		attack.attack_once()


## 在原行中接管可见精灵的姿态和染色，随行及战局一同暂停和回收。
func handoff_death() -> void:
	var row := _zombie.get_parent() as CanvasItem # 兼容普通行和使用 Panel 的旧棋盘行。
	if row == null or row.is_queued_for_deletion() or not _sprite.is_visible_in_tree():
		return
	var falling := DeathSprite.new() # 不持有碰撞体、生命组件或原角色引用。
	falling.sprite_frames = _sprite.sprite_frames
	falling.animation = &"death"
	falling.transform = row.get_global_transform().affine_inverse() * _sprite.global_transform
	falling.z_index = _zombie.z_index + _zombie.body.z_index + _sprite.z_index
	falling.modulate = _zombie.modulate * _zombie.body.modulate * _sprite.modulate
	falling.self_modulate = _sprite.self_modulate
	falling.capture_entry_pose(_sprite)
	row.add_child(falling)
	_sprite.hide()
