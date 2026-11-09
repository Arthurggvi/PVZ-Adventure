extends Zombie000Base
class_name Zombie016Jackbox

@onready var bomb_component_jackbox: BombComponentJackbox = $BombComponentJackbox

@export_group("动画状态")
@export var is_pop:=false
## First animation blast is nonlethal from tier four onward.
var survive_first_explosion := false
var first_explosion_survived := false
signal signal_first_jackbox_blast_survived()

func ready_norm():
	super()
	## 罐子僵尸，直接爆炸
	if is_pot_zombie:
		_strigger_bomb()

## 初始化正常出战角色信号连接
func ready_norm_signal_connect():
	super()
	bomb_component_jackbox.signal_trigger_bomb.connect(_strigger_bomb)
	hp_component.signal_hp_component_death.connect(bomb_component_jackbox.disable_component.bind(ComponentNormBase.E_IsEnableFactor.Death))

	signal_update_speed.connect(bomb_component_jackbox.owner_update_speed)


## 触发爆炸
func _strigger_bomb():
	is_pop = true
	SoundManager.play_character_SFX(&"boing")
	_stop_sfx_enter()

## 失去铁器道具
func loss_iron_item():
	super()
	bomb_component_jackbox.disable_component(ComponentNormBase.E_IsEnableFactor.Lose)
	_stop_sfx_enter()

## Native pop animation calls bomb_once() before calling this method.
## Survive only that first scripted pop; real combat death still goes through
## the ordinary HP/death pipeline and triggers the second numeric blast.
func character_death_disappear():
	if survive_first_explosion and not first_explosion_survived \
			and is_pop and bomb_component_jackbox.is_bomb \
			and not hp_component.is_death:
		first_explosion_survived = true
		is_pop = false
		loss_iron_item()
		# This rig has three independent box parts outside IronNode.
		# Animation tracks drive self_modulate/visible; a permanent per-item
		# modulate alpha keeps the box hidden across subsequent walk/eat loops.
		for part_name: String in [
				"Zombie_jackbox_box", "Zombie_jackbox_box2",
				"Zombie_jackbox_handle", "Zombie_jackbox_clownneck1",
				"Zombie_jackbox_clownneck2", "Zombie_jackbox_clownneck3",
				"Zombie_jackbox_clownhead"]:
			var part: CanvasItem = get_node_or_null(
					"Body/BodyCorrect/" + part_name) as CanvasItem
			if part != null:
				part.modulate.a = 0.0
		var tree: AnimationTree = get_node_or_null("AnimationTree") as AnimationTree
		if tree != null:
			var playback: AnimationNodeStateMachinePlayback = tree.get(
					"parameters/StateMachine/playback") as AnimationNodeStateMachinePlayback
			if playback != null:
				playback.travel(&"Zombie_jackbox_walk")
		signal_first_jackbox_blast_survived.emit()
		return
	super.character_death_disappear()

func sfx_jack_suprise():
	SoundManager.play_character_SFX(&"jack_suprise")
