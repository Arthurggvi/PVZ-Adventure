extends Node2D
class_name BlackGeneralVisual
## Pure visual adapter: no HP, reward, spawn, or damage responsibilities.
## Original football's individual upper/lower leg and foot transform trajectories
## are baked into AnimationPlayer resource tracks. Phase changes swap textures only.
signal flag_raised
signal teleport_disappeared
signal teleport_appeared
@onready var player: AnimationPlayer = $AnimationPlayer
@onready var _parts: Node2D = $Body/BodyCorrect
var _phase2 := false
const P2_DIR := "res://assets/adventure/zombies/black_general/parts/phase2/"
const BASE_DIR := "res://assets/adventure/zombies/black_general/parts/armor/"
const MAP := {
 "Zombie_football_upperbody": "chest", "Zombie_football_upperbody2": "abdomen",
 "Zombie_football_lowerbody": "waist", "Zombie_football_leftarm_upper": "shoulder_l",
 "Zombie_football_rightarm_upper": "shoulder_r", "Zombie_football_leftarm_lower": "forearm_l",
 "Zombie_football_rightarm_lower": "forearm_r"
}
func _ready() -> void:
 set_phase2(false)
func play_action(action: StringName) -> void:
 if not player.has_animation(action):
  push_error("BlackGeneralVisual: missing action %s" % action)
  return
 $Body.modulate.a = 1.0
 player.play(action)
func set_phase2(enabled: bool) -> void:
 _phase2 = enabled
 for native: String in MAP:
  var key: String = MAP[native]
  var spr: Sprite2D = _parts.get_node(native + "_Art") as Sprite2D
  spr.texture = load((P2_DIR if enabled else BASE_DIR) + key + ".png")
 for n: String in ["Zombie_football_leftleg_upper","Zombie_football_rightleg_upper",
                   "Zombie_football_leftleg_lower","Zombie_football_rightleg_lower"]:
  var suffix := "_phase2" if enabled else ""
  var texture_path := "res://assets/adventure/zombies/black_general/generated_native/" + n + suffix + ".png"
  (_parts.get_node(n) as Sprite2D).texture = load(texture_path)
 (_parts.get_node("Zombie_football_helmet_Art") as Sprite2D).texture = load(P2_DIR + "helmet_full.png" if enabled else BASE_DIR + "helmet.png")
 (_parts.get_node("Anim_head1_Art") as Sprite2D).texture = load((P2_DIR if enabled else BASE_DIR) + "head.png")
 # Single black-smoke layer behind the character; no orbiting flame fragments.
 var smoke: AnimatedSprite2D = _parts.get_node("Zombie_football_upperbody/BlackSmokeBack") as AnimatedSprite2D
 smoke.visible = enabled
 if enabled:
  smoke.play(&"loop")
 else:
  smoke.stop()
func _emit_flag_raised() -> void:
 flag_raised.emit()
func _emit_teleport_disappeared() -> void:
 teleport_disappeared.emit()
func _emit_teleport_appeared() -> void:
 teleport_appeared.emit()
