## 边境雪山独立出怪：滑雪不占随机池战力；老妇人存活时延续末期自然波，数量减半。
extends Node
class_name SnowMountainWaveSupport

## 滑雪配额在满场时每隔若干游戏秒检查空位，绝不通过堆积协程阻塞自然刷新。
const DRAIN_SECONDS: float = 0.25
## 滑雪每次最多新建四只，避免一次补齐积压配额造成 Android 主线程卡顿。
const BONUS_BATCH_LIMIT: int = 4
## 妇人战期间自然增援的刷新周期。
const BOSS_WAVE_SECONDS: float = 22.0
## 妇人战自然刷怪占倒数第二波原始计划的比例。
const BOSS_WAVE_RATIO: float = 0.5
## 第四面旗帜的每行三阶滑雪僵尸，与该旗帜预排的猎人、穴居人相配。
const SKI_FLAG_WAVE: int = 40
## 阶段的自然波次管理器，不改变其进度条与旗帜身份。
var waves: ZombieWaveManager
## 唯一战场登记源，负责实际存活数和上限检查。
var zombies: ZombieManager
## 阶段快照，普通和噩梦的等阶来源均由此决定。
var phase: StagePhaseDefinition
## 尚未出生的滑雪名额，始终保留原始波次及固定行。
var _pending: Array[Dictionary] = []
## 同一个战场的随机流，不借用其他系统的随机池。
var _rng := RandomNumberGenerator.new()
## 待配额解除容量限制的累计游戏秒。
var _drain_clock: float = 0.0
## Boss 存活期间的专用末期自然波计时。
var _boss_timer: Timer

## [param wave_manager]、[param manager] 和 [param stage_phase] 均属于同一战场与阶段。
func setup(wave_manager: ZombieWaveManager, manager: ZombieManager,
        stage_phase: StagePhaseDefinition) -> void:
    waves = wave_manager
    zombies = manager
    phase = stage_phase
    _rng.randomize()

## 登记Boss时仍属同一会话；关闭处理器时统一拆除信号和定时器。
func _ready() -> void:
    _boss_timer = Timer.new()
    _boss_timer.wait_time = BOSS_WAVE_SECONDS
    _boss_timer.timeout.connect(_on_boss_wave)
    add_child(_boss_timer)
    zombies.boss_member_registered.connect(_on_boss_registered)
    set_process(false)

## 末期自然波使用已有注册与等阶计划，不占用后续旗帜进度。
func _on_boss_registered(member: ZB000Base) -> void:
    if phase.kind != StagePhaseDefinition.Kind.NIGHTMARE or not member is ZB006Cailleach \
            or waves.curr_wave + 1 != phase.wave_profile.wave_count:
        return
    member.signal_character_death.connect(_stop_boss_waves, CONNECT_ONE_SHOT)
    member.tree_exiting.connect(_stop_boss_waves, CONNECT_ONE_SHOT)
    _boss_timer.start()

## 每个实际自然波结束后，将本波保证配额交给独立的排队生成器。
func on_wave_started(wave_number: int) -> void:
    var profile: WaveProfile = phase.wave_profile # 已由入口验证的波次数据。
    if profile == null or profile.bonus_zombie_type == CharacterRegistry.ZombieType.Null:
        return
    _pending.clear() # 每波只兑现本波配额；清除旧波欠账，避免噩梦后期仍在补第一批滑雪。
    var fixed_count: int = zombies.all_zombie_rows.size() if wave_number == SKI_FLAG_WAVE else 0 # 固定行也计入本波滑雪配额。
    if fixed_count > 0:
        for lane: int in range(fixed_count): # 第四旗每条仍配置的行各有一只三阶滑雪。
            _enqueue(wave_number - 1, lane, &"elite")
    var progress: float = float(wave_number - 1) / float(maxi(1, profile.wave_count - 1)) # 零到一的递增进度。
    var count: int = roundi(lerpf(profile.bonus_first_wave_count,
            profile.bonus_final_wave_count, progress)) # 普通与噩梦同一套 1–12 配额。
    var band: WaveBandDefinition = AdventureWavePlanner.find_band(profile, wave_number) # 等阶与本波一致。
    for index: int in range(maxi(0, count - fixed_count)): # 预排六只优先占用本波配额，剩余名额独立抽阶。
        _enqueue(wave_number - 1, -1, _pick_tier(band.tier_weights))
    _drain_pending()

## 妇人在场期间复用倒数第二波的随机池，以其未减量计划的一半继续生成。
func _on_boss_wave() -> void:
    if not zombies.is_game_running() or waves.curr_wave + 1 != phase.wave_profile.wave_count \
            or zombies.get_living_boss_of_type(CharacterRegistry.ZombieBossType.ZB006Cailleach) == null:
        _stop_boss_waves()
        return
    var profile: WaveProfile = phase.wave_profile # 从完整配置而非另建的援军权重读取候选。
    var reference_wave: int = profile.wave_count - 1 # 第五旗之前的最后一波，没有旗帜预排。
    var creator: ZombieWaveCreateManager = waves.zombie_wave_create_manager # 自然出生与普通波共用入口。
    var budget: int = AdventureWavePlanner.wave_budget(profile, reference_wave, creator.zombie_multy) # 沿用自然波的战力预算。
    var planned: Array[Dictionary] = AdventureWavePlanner.build_unreduced_plan(profile, reference_wave,
            budget, profile.resolve_capacity(creator.max_zombies_per_wave),
            AdventureStageCatalog.tier_threat_costs(), _rng) # Boss 增援有独立的半量规则。
    var reduced: int = roundi(planned.size() * BOSS_WAVE_RATIO) # 按本次计划就近取整。
    var batch_started: int = Time.get_ticks_usec() # 单帧生成预算，超过上限让出下一帧。
    for index: int in range(reduced):
        if Time.get_ticks_usec() - batch_started >= 3500:
            await get_tree().process_frame
            if _boss_timer.is_stopped() or not zombies.is_game_running() \
                    or zombies.get_living_boss_of_type(CharacterRegistry.ZombieBossType.ZB006Cailleach) == null:
                return
            batch_started = Time.get_ticks_usec()
        if zombies.available_zombie_slots(1) == 0:
            break
        _spawn_entry(planned[index])
    var progress: float = float(reference_wave - 1) / float(maxi(1, profile.wave_count - 1))
    var normal_ski: int = roundi(lerpf(profile.bonus_first_wave_count,
            profile.bonus_final_wave_count, progress)) # 滑雪同样减半，仍不挤占常规权重。
    for index: int in range(roundi(normal_ski * BOSS_WAVE_RATIO)):
        _enqueue(waves.curr_wave, -1, _pick_tier(
                AdventureWavePlanner.find_band(profile, reference_wave).tier_weights), true)
    _drain_pending()

## 单个增援复用场景选行、自然刷新归属及等阶绑定；没有冰道时雪橇退化为普僵。
func _spawn_entry(entry: Dictionary) -> void:
    var kind: CharacterRegistry.ZombieType = entry["zombie_type"] # 本次从真实池选出的物种。
    var creator: ZombieWaveCreateManager = waves.zombie_wave_create_manager # 统一实例工厂。
    var choices: ZombieChooseRowSystem = creator.zombie_choose_row_system # 统一行平滑抽样。
    var ice_weights: Array[float] = [] # 非雪橇不限制冰道。
    if kind == CharacterRegistry.ZombieType.Z014Bobsled:
        ice_weights = creator._bobsled_ice_weights([])
        if not ice_weights.any(func(weight: float) -> bool: return weight > 0.0):
            kind = CharacterRegistry.ZombieType.Z001Norm # 维持总数而不强行在无冰地带放雪橇。
            ice_weights.clear()
    var row_type: CharacterRegistry.ZombieRowType = Global.character_registry.get_zombie_info(
            kind, CharacterRegistry.ZombieInfoAttribute.ZombieRowType) # 真实的地形资格。
    var lane: int = choices.select_spawn_row(row_type, ice_weights) # 完整遵循现有雪坡行算法。
    if lane >= 0:
        creator.wave_create_zombie(kind, lane, waves.curr_wave, Callable(), true,
                AdventureZombieTierBinding.new(entry["tier_id"]))

## 将 [param row] 固定行或 -1 随机行加入滑雪出怪队列；[param boss] 用于死亡时撤销增援。
func _enqueue(wave: int, row: int, tier: StringName, boss: bool = false) -> void:
    _pending.append({"wave": wave, "row": row, "tier": tier, "boss": boss})
    set_process(true)

## 仅补刷当前波未完成的滑雪名额；常规自然波生成期间暂停补刷，避免并发抢占生成时机。
func _process(delta: float) -> void:
    _drain_clock += delta
    if _drain_clock >= DRAIN_SECONDS and not waves.is_wave_spawning(waves.curr_wave + 1):
        _drain_clock = 0.0
        _drain_pending()

## 最大存活数是全局滑雪现存实例，不是本波计划数；满 12 只后绝不继续创建。
func _drain_pending() -> void:
    var profile: WaveProfile = phase.wave_profile # 额外配额由阶段配置声明。
    var alive: int = 0 # 跨全部出生波次统计真实存活的滑雪僵尸。
    for zombie: Zombie000Base in zombies.all_zombies_1d:
        if is_instance_valid(zombie) and not zombie.is_death and not zombie.is_hypno \
                and zombie.zombie_type == profile.bonus_zombie_type:
            alive += 1
    var creator: ZombieWaveCreateManager = waves.zombie_wave_create_manager # 共用自然出怪工厂。
    var created_this_batch: int = 0 # 单次补刷不超过可承受的实例创建量。
    while not _pending.is_empty() and alive < profile.bonus_live_cap \
            and created_this_batch < BONUS_BATCH_LIMIT \
            and zombies.is_game_running() and zombies.available_zombie_slots(1) > 0:
        var item: Dictionary = _pending[0] # 优先保留最早的固定行名额。
        var lane: int = int(item["row"]) # -1 时抽取实际存在的地形行。
        if lane < 0 or not zombies.is_lane_open(lane) \
                or not zombies.can_spawn_zombie_in_lane(profile.bonus_zombie_type, lane):
            var row_type: CharacterRegistry.ZombieRowType = Global.character_registry.get_zombie_info(
                    profile.bonus_zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieRowType)
            lane = creator.zombie_choose_row_system.select_spawn_row(row_type)
        if lane < 0:
            break
        var created: Zombie000Base = creator.wave_create_zombie(profile.bonus_zombie_type, lane,
                int(item["wave"]), Callable(), true, AdventureZombieTierBinding.new(item["tier"]))
        if not is_instance_valid(created):
            break
        _pending.pop_front()
        alive += 1
        created_this_batch += 1
    if _pending.is_empty():
        set_process(false)

## 返回是否还有已承诺、但被 12 只上限推迟出生的滑雪僵尸。
func has_pending() -> bool:
    return not _pending.is_empty()

## Boss 死亡或离场即撤销后续自然增援，保留先前正常波的未完成滑雪名额。
func _stop_boss_waves() -> void:
    if is_instance_valid(_boss_timer):
        _boss_timer.stop()
    for index: int in range(_pending.size() - 1, -1, -1): # 倒序清除仅由本次 Boss 周期出怪形成的配额。
        if _pending[index]["boss"]:
            _pending.remove_at(index)
    set_process(not _pending.is_empty())

## 阶段结算后不允许旧配额带入新的普通/噩梦阶段。
func clear() -> void:
    _pending.clear()
    _stop_boss_waves()

## 按波段现有的二三阶或三四阶权重抽取，不允许基础阶混入。
func _pick_tier(weights: Dictionary) -> StringName:
    var total: int = 0 # 只计算正权重等阶。
    for key: StringName in weights:
        total += maxi(0, int(weights[key]))
    if total <= 0:
        return &""
    var draw: int = _rng.randi_range(1, total) # 每次生成独立抽样。
    for key: StringName in weights:
        draw -= maxi(0, int(weights[key]))
        if draw <= 0:
            return key
    return &""
