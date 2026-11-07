extends CanvasItem
class_name ZombieRow

@onready var zombie_create_position: Marker2D = $ZombieCreatePosition

## 当前行类型
@export var zombie_row_type:CharacterRegistry.ZombieRowType = CharacterRegistry.ZombieRowType.Land
## 是否有钉耙
@export var have_rake := false

## 判断 [param spawn_type] 能否出现在 [param row_type]；两栖类型兼容陆路和水路。
static func supports_spawn(spawn_type: CharacterRegistry.ZombieRowType,
		row_type: CharacterRegistry.ZombieRowType) -> bool:
	return (spawn_type == CharacterRegistry.ZombieRowType.Both
		or row_type == CharacterRegistry.ZombieRowType.Both
		or spawn_type == row_type)
