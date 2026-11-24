## 西瓜转职可以在原生攻击到期和甩篮动作之间插入固定时长的蓄力。
extends AttackComponentBulletPultBase
class_name AttackComponentBulletMelon

## 由转职西瓜接收原计时器到期；普通西瓜不安装。
var prepare_volley: Callable

## _on 仍由场景里的原生 SpeedTimer 调用。转职前保留基类的原动作。
func _on_bullet_attack_cd_timer_timeout() -> void:
	if prepare_volley.is_valid():
		prepare_volley.call()
	else:
		super()

## 主株确认 [param target] 后，冻结原生瞄准锚点并播放完整的甩篮动作。
func play_melon_windup(target: Character000Base) -> void:
	last_target_enemy = target
	last_target_enemy_global_pos = target.hurt_box_component.global_position
	_aimed_lane = target.lane if target.lane >= 0 else owner.lane
	animation_tree.set(attack_para, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
