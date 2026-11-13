"""把原版 6.1.1 PAM 的无损解码数据转换成 Godot 分层动画。

从仓库任意目录执行本文件即可重建本体和电球场景。仅需 Python 标准库；
原始 PNG、PAM、逐字段解码 JSON 和来源记录均保留，不重新绘制或修改颜色。
"""
from pathlib import Path
import copy
import json

# 当前工具目录、游戏根目录和原版分组资源索引。
ROOT = Path(__file__).resolve().parent
GAME = ROOT.parents[2]
REGIONS = {item['id']: item for item in json.loads((ROOT/'source/regions.json').read_text())['resources'] if 'aw' in item}
# 原植物注册表指定的芦苇命中依赖，作为此植物独立可提交的资源保存。
REGIONS.update({item['id']: item for item in json.loads((ROOT/'source/hit_regions.json').read_text())['resources'] if 'aw' in item})
# 每个原图集父资源的生产纹理路径，颜色与原 PTX 一致。
ATLASES = {'ATLASIMAGE_ATLAS_PLANTELECTRICPEASHOOTER_1536_00': 'electric_peashooter_atlas.png',
           'ATLASIMAGE_ATLAS_PLANTLIGHTNINGREEDHIT_1536_00': 'electric_peashooter_hit_atlas.png'}
# 二维仿射单位变换，以 a、c、b、d、x、y 顺序保存。
IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def multiply(left, right):
    """按原 PAM 次序组合两个仿射变换，保留偏斜和非均匀缩放。"""
    # 父、子变换的矩阵与平移分量。
    a, c, b, d, x, y = left
    e, g, f, h, u, v = right
    return (a*e+c*f, a*g+c*h, b*e+d*f, b*g+d*h, a*u+c*v+x, b*u+d*v+y)


def snapshots(frames):
    """重建 PAM 保留式显示列表；未更新部件持续显示，删除指令才移除。"""
    # 当前存活实例与各帧快照。
    active, result = {}, []
    # 每帧依次执行移除、新建和变换；标签标识独立动作。
    for removed, added, moved, label, _stop, _commands in frames:
        if label:
            active = {}
        # 原实例编号，删除后不继承旧颜色或姿态。
        for index in removed:
            active.pop(index, None)
        # 新建实例的引用类型、资源编号及加色标志。
        for index, resource, is_sprite, additive, _start, _name, _speed in added:
            active[index] = {'resource': resource, 'sub': is_sprite, 'add': additive,
                             'matrix': IDENTITY, 'color': (1, 1, 1, 1)}
        # 此帧更新的完整仿射姿态与可选颜色乘数。
        for index, transform, color, _source, _child in moved:
            active[index]['matrix'] = tuple(transform)
            if color is not None:
                active[index]['color'] = tuple(color)
        result.append(copy.deepcopy(active))
    return result


def decode(name, pivot):
    """把指定 PAM 的所有动作展平为有序图层；pivot 是脚底或球心的源坐标。"""
    # 原帧率、图像锚点、子符号和主时间轴。
    info, images, symbols, main = json.loads((ROOT/'source'/f'{name}.json').read_text())
    assert all(len(symbol[3]) == 1 for symbol in symbols), '本资源子符号应为静态姿态'
    # 原版所有子符号均只有一帧，展开不需要重采样。
    children = [snapshots(symbol[3])[0] for symbol in symbols]

    def flatten(state, parent, tint=(1, 1, 1, 1), additive=False):
        """按照 PAM 图层顺序展开图片，叠乘父级姿态与颜色。"""
        # 原实例编号只决定绘制顺序，不用作跨动作节点身份。
        for _index, instance in sorted(state.items()):
            # 当前实例的世界变换、颜色、资源编号及混合模式。
            transform = multiply(parent, instance['matrix'])
            color = tuple(a*b for a, b in zip(tint, instance['color']))
            resource = instance['resource']
            blend = additive or instance['add']
            if instance['sub']:
                # _custom 是未装备的装扮插槽；原版基础植物不显示装扮。
                if symbols[resource][0] != '_custom':
                    yield from flatten(children[resource], transform, color, blend)
            else:
                # 原图的尺寸和锚点，把 1536 图集映射回 PAM 作者坐标。
                image, width, height, anchor = images[resource]
                region = REGIONS[image]
                raster = (width/region['aw'], 0, 0, height/region['ah'], 0, 0)
                yield image, multiply(multiply(transform, anchor), raster), color, blend

    # 源坐标到 Godot 脚底/球心坐标的平移，0.7 显示比例在 Rig 统一应用。
    origin = (1, 0, 0, 1, -pivot[0], -pivot[1])
    frames = [list(flatten(state, origin)) for state in snapshots(main[3])]
    # 动作标签以及原始帧号，保留 stop 帧。
    labels = [(index, frame[3]) for index, frame in enumerate(main[3]) if frame[3]]
    actions = {label: frames[start:(labels[position+1][0] if position+1 < len(labels) else len(frames))]
               for position, (start, label) in enumerate(labels)}
    return info[0], actions


def number(value):
    """以足够精度输出 Godot 浮点字面量，避免负零和科学计数差异。"""
    return f'{value:.8f}'.rstrip('0').rstrip('.') if abs(value) > 0.000000005 else '0'


def transform_text(matrix):
    """转换为 Godot Transform2D 的列向量参数次序。"""
    # PAM 的行序分量改成 Godot 的列序分量。
    a, c, b, d, x, y = matrix
    return 'Transform2D('+', '.join(number(value) for value in (a, b, c, d, x, y))+')'


def write_scene(filename, root_name, actions, fps, autoplay=''):
    """为各原动作生成离散帧轨道，确保切换动作时不会残留隐藏部件。"""
    # 所有动作共享一张原版图集；图集区域按资源名稳定排序。
    images = sorted({item[0] for frames in actions.values() for frame in frames for item in frame})
    texture_ids = {name: f'Texture_{index:03d}' for index, name in enumerate(images)}
    # 最大同时绘制层数，节点序号对应当帧绘制顺序。
    layer_count = max(len(frame) for frames in actions.values() for frame in frames)
    lines = ['[gd_scene format=3]', '']
    # 此场景实际引用的原图集，避免让普通电球额外加载命中图集。
    for parent in sorted({REGIONS[name]['parent'] for name in images}):
        lines += [f'[ext_resource type="Texture2D" path="res://assets/adventure/plants/electric_peashooter/{ATLASES[parent]}" id="{parent}"]', '']
    # 原图集中的无损区域引用。
    for name in images:
        region = REGIONS[name]
        lines += [f'[sub_resource type="AtlasTexture" id="{texture_ids[name]}"]', f'atlas = ExtResource("{region["parent"]}")',
                  'region = Rect2('+', '.join(str(region[key]) for key in ('ax','ay','aw','ah'))+')', 'filter_clip = true', '']
    # 原 PAM 暂无加色图层；显式断言，防止未来源更新时悄悄改变混合方式。
    assert not any(item[3] for frames in actions.values() for frame in frames for item in frame)
    # 各动作逐帧值轨道，所有姿态保持原 30fps，不做补间。
    for name, frames in actions.items():
        lines += [f'[sub_resource type="Animation" id="Animation_{name}"]', f'resource_name = "{name}"',
                  f'length = {number(len(frames)/fps)}', f'step = {number(1/fps)}']
        if name.startswith('idle') or name.startswith('projectile'):
            lines.append('loop_mode = 1')
        # 当前动作轨道序号。
        track = 0
        # 每层都在零时刻写入完整初态，动作切换时可以安全复用节点。
        for layer in range(layer_count):
            # 图层的可见性、贴图、变换与原版颜色四类属性。
            properties = {'visible': [], 'texture': [], 'transform': [], 'self_modulate': []}
            # 当前帧中的可选图层条目；不存在则隐藏并恢复默认状态。
            for frame in frames:
                item = frame[layer] if layer < len(frame) else None
                properties['visible'].append('true' if item else 'false')
                properties['texture'].append(f'SubResource("{texture_ids[item[0]]}")' if item else 'null')
                properties['transform'].append(transform_text(item[1] if item else IDENTITY))
                properties['self_modulate'].append('Color('+', '.join(number(value) for value in (item[2] if item else (1,1,1,1)))+')')
            # 连续相同值只保留首次关键帧，降低资源体积。
            for prop, values in properties.items():
                changed = [index for index, value in enumerate(values) if index == 0 or value != values[index-1]]
                lines += [f'tracks/{track}/type = "value"', f'tracks/{track}/path = NodePath("Rig/Layer{layer:02d}:{prop}")',
                          f'tracks/{track}/interp = 0', f'tracks/{track}/loop_wrap = false', f'tracks/{track}/keys = {{',
                          '"times": PackedFloat32Array('+', '.join(number(index/fps) for index in changed)+'),',
                          '"transitions": PackedFloat32Array('+', '.join('1' for _index in changed)+'),',
                          '"update": 1,', '"values": ['+', '.join(values[index] for index in changed)+']', '}']
                track += 1
        lines.append('')
    lines += ['[sub_resource type="AnimationLibrary" id="library"]', '_data = {',
              ',\n'.join(f'&"{name}": SubResource("Animation_{name}")' for name in actions), '}', '',
              f'[node name="{root_name}" type="Node2D"]', '', '[node name="Rig" type="Node2D" parent="."]', 'scale = Vector2(0.7, 0.7)', '']
    # 默认显示首个动作的首帧，编辑器和无处理预览也能显示原图。
    first = next(iter(actions.values()))[0]
    for layer in range(layer_count):
        lines += [f'[node name="Layer{layer:02d}" type="Sprite2D" parent="Rig"]', 'centered = false']
        if layer < len(first):
            item = first[layer]
            lines += [f'texture = SubResource("{texture_ids[item[0]]}")', 'transform = '+transform_text(item[1]),
                      'self_modulate = Color('+', '.join(number(value) for value in item[2])+')']
        else:
            lines.append('visible = false')
        lines.append('')
    lines += ['[node name="AnimationPlayer" type="AnimationPlayer" parent="."]', 'libraries = {&"": SubResource("library")}']
    if autoplay:
        lines.append(f'autoplay = "{autoplay}"')
    # 写入独立场景，不触碰植物注册、碰撞或运行时脚本。
    destination = GAME/'scenes/character/plant'/filename
    destination.write_text('\n'.join(lines)+'\n', encoding='utf-8')
    print(destination.name, len(actions), 'actions', layer_count, 'layers')


def write_audio_randomizers():
    """复现 Wwise 各实际随机容器的 avoidRepeat=1，不把并行音层混成一个池。"""
    # 每个独立原随机容器的名字和素材数；idle 第九音为另外固定播放的一层。
    counts = {'idle': 8, 'attack_start': 3, 'attack_fire_body': 3,
              'attack_fire_zap': 3, 'bolt_fire': 3}
    # 所有组均保持原样本音高，组间相对音量由运行时事件处理。
    for name, count in counts.items():
        lines = ['[gd_resource type="AudioStreamRandomizer" format=3]', '']
        # 池中的原始 WAV，不连续重复由 Godot 的 PLAYBACK_RANDOM_NO_REPEATS（0）实现。
        for index in range(1, count+1):
            lines.append(f'[ext_resource type="AudioStream" path="res://assets/adventure/plants/electric_peashooter/audio/{name}_{index}.wav" id="{index}"]')
        lines += ['', '[resource]', 'playback_mode = 0', f'streams_count = {count}']
        for index in range(count):
            lines.append(f'stream_{index}/stream = ExtResource("{index+1}")')
        # 仅更新本植物的自有音频资源。
        destination = GAME/'assets/adventure/plants/electric_peashooter/audio'/f'{name}.tres'
        destination.write_text('\n'.join(lines)+'\n', encoding='utf-8')


if __name__ == '__main__':
    # 本体以脚底对齐项目坐标，电球和爆炸以原球心对齐。
    fps, body = decode('ELECTRIC_PEASHOOTER', (200, 240))
    write_scene('electric_peashooter_visual.tscn', 'ElectricPeashooterVisual', body, fps, 'idle')
    fps, balls = decode('ELECTRIC_PEASHOOTER_ELECTROBALL', (195, 195))
    _fps, impacts = decode('ELECTRIC_PEASHOOTER_ELECTROBALL_EFFECTS', (195, 195))
    # 项目动画名与原标签的一一映射，普通穿透球不播放 impact。
    effects = {'projectile': balls['animation'], 'projectile2': balls['animation2'],
               'projectile3': balls['animation3'], 'plantfood_sub': balls['animation5'],
               'plantfood_projectile': balls['animation6'], 'impact': impacts['animation'],
               'plantfood_impact': impacts['animation2'], 'plantfood_sub_impact': impacts['animation3']}
    write_scene('electric_peashooter_effects.tscn', 'ElectricPeashooterEffects', effects, fps)
    # 普通放电使用电豌豆专属电弧，受击使用注册表明确依赖的芦苇闪电。
    _fps, hits = decode('LIGHTNINGREED_HIT', (195, 195))
    bolts = {'bolt': impacts['animation'], 'hit': hits['idle'], 'hit2': hits['idle2'],
             'hit3': hits['idle3'], 'hit4': hits['idle4']}
    write_scene('electric_peashooter_bolt.tscn', 'ElectricPeashooterBolt', bolts, fps)
    write_audio_randomizers()
