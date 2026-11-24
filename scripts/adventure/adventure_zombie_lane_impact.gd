## Reusable swept-lane plant impact: vehicles flatten; riders deal numeric damage.
## Traverse grid cells by actual terrain width rather than fixed sprite pixel sizes.
extends RefCounted
class_name AdventureZombieLaneImpact

## [param lane] 是扫掠所在行，[param before_x]、[param after_x] 是实际世界区间。
## [param damage] 用于非必杀扫掠，[param flatten] 标记碾压；[param impacted] 记录本次已击中实体。
## [param attacker] 提供反伤归属。返回此次新增命中的植物数量。
static func hit_plants(lane: int, before_x: float, after_x: float,
        damage: int, flatten: bool, impacted: Dictionary[int, bool], attacker: Character000Base = null) -> int:
    if not flatten and damage <= 0:
        return 0
    var game: MainGameManager = Global.main_game
    if not is_instance_valid(game) or not is_instance_valid(game.plant_cell_manager):
        return 0
    var rows: Array[Array] = game.plant_cell_manager.all_plant_cells
    if lane < 0 or lane >= rows.size():
        return 0
    var count := 0
    var crush: CombatHitScope = null # 扫掠真正命中植物时才创建归因。
    for entry: Variant in rows[lane]:
        var cell: PlantCell = entry as PlantCell
        if not is_instance_valid(cell):
            continue
        var center: float = cell.global_position.x + cell.size.x * 0.5
        if center < minf(before_x, after_x) - cell.size.x * 0.5 \
                or center > maxf(before_x, after_x) + cell.size.x * 0.5:
            continue
        for plant: Plant000Base in cell.living_plants(): # 不占种植位的伴生同样参与目标选择或伤害。
            if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion():
                continue
            var id: int = plant.get_instance_id()
            if impacted.has(id):
                if flatten:
                    plant.show_crush_contact()
                continue
            impacted[id] = true
            if flatten:
                if crush == null:
                    crush = CombatHitScope.for_plant_attack(attacker, CombatHitScope.PlantImpact.CRUSH)
                plant.be_hit_instantly(crush)
            else:
                plant.be_hit_from(damage, attacker, BulletRegistry.AttackMode.Penetration)
            count += 1
    return count
