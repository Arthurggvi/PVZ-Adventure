"""拆分旧卡牌总览，并由总览顺序和单卡身份生成运行时轻量索引。

日常编辑单卡模板或总览顺序后运行本脚本；--check 只检查生成结果是否同步。
--split 仅用于将尚未拆分的旧 all_cards.tscn 迁移为逐卡资源，不覆盖已有模板。
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


# 所有路径均从本工具位置解析，不依赖调用者的工作目录。
ROOT = Path(__file__).resolve().parents[1]
OVERVIEW = ROOT / "scenes/autoload/all_cards.tscn"
TEMPLATES = ROOT / "scenes/ui/all_cards/templates"
MANIFEST = ROOT / "scripts/autoload/card_catalog_manifest.gd"
DIRECTORIES = ("PlantCards", "PlantCards2", "ZombieCards", "ZombieCards2", "BossCards")
# 文本场景各段的头部均独占一行；属性数组中的方括号不影响分段。
SECTION = re.compile(r"(?=^\[(?:gd_scene|ext_resource|sub_resource|node|connection|editable)\b)", re.M)
REFERENCE = re.compile(r'(ExtResource|SubResource)\("([^"\n]+)"\)')


def sections(text: str) -> list[str]:
    """返回保留原属性文本的场景段，便于无损搬移美术节点。"""
    return [part.rstrip() + "\n\n" for part in SECTION.split(text) if part.strip()]


def attribute(section: str, name: str) -> str:
    """读取段头的字符串属性；缺失时返回空串。"""
    match = re.search(rf'\b{re.escape(name)}="([^"]*)"', section.splitlines()[0])
    return match.group(1) if match else ""


def resources(parts: list[str]) -> dict[tuple[str, str], str]:
    """建立资源声明索引，用于计算节点真正引用的传递依赖。"""
    result = {}
    for part in parts:
        if part.startswith("[ext_resource "):
            result[("ExtResource", attribute(part, "id"))] = part
        elif part.startswith("[sub_resource "):
            result[("SubResource", attribute(part, "id"))] = part
    return result


def closure(parts: list[str], source: dict[tuple[str, str], str]) -> list[str]:
    """只保留节点及子资源实际引用的声明，并保持原文件的声明顺序。"""
    needed = set(REFERENCE.findall("".join(parts)))
    pending = list(needed)
    while pending:
        key = pending.pop()
        if key not in source:
            raise ValueError(f"场景引用了未声明资源：{key}")
        for dependency in REFERENCE.findall(source[key].split("\n", 1)[1]):
            if dependency not in needed:
                needed.add(dependency)
                pending.append(dependency)
    return [part for key, part in source.items() if key in needed]


def identity(root: str, source: dict[tuple[str, str], str]) -> tuple[int, int]:
    """从卡牌根节点引用的 ResourceCardReference 读取唯一身份。"""
    match = re.search(r'^card_reference = SubResource\("([^"]+)"\)', root, re.M)
    if not match:
        raise ValueError("卡牌模板缺少根节点 card_reference")
    reference = source[("SubResource", match.group(1))]
    kind = re.search(r"^card_type = (\d+)$", reference, re.M)
    content = re.search(r"^content_id = (\d+)$", reference, re.M)
    if not kind or not content or "is_imitater = true" in reference:
        raise ValueError("源模板必须声明无模仿修饰的完整身份")
    return int(kind.group(1)), int(content.group(1))


def split_legacy() -> None:
    """把原目录中的每棵 Card 子树独立保存，总览只保留布局和实例引用。"""
    parts = sections(OVERVIEW.read_text(encoding="utf-8"))
    source = resources(parts)
    roots = [part for part in parts if part.startswith("[node ")
             and 'instance=ExtResource("2_5pqky")' in part]
    if not roots:
        raise ValueError("总览已经拆分，或不是已知的旧目录格式")
    outputs = {}
    replacements = {}
    removed = set()
    new_resources = []
    for root in roots:
        kind, content = identity(root, source)
        relative = f"scenes/ui/all_cards/templates/card_{kind}_{content}.tscn"
        target = ROOT / relative
        if target.exists():
            raise ValueError(f"拒绝覆盖已有模板：{target}")
        parent = attribute(root, "parent")
        name = attribute(root, "name")
        original_path = name if parent == "." else f"{parent}/{name}"
        subtree = [part for part in parts if part == root or (part.startswith("[node ")
                   and (attribute(part, "parent") == original_path
                        or attribute(part, "parent").startswith(original_path + "/")))]
        rewritten = []
        for part in subtree:
            if part == root:
                part = re.sub(r' parent="[^"]*"', "", part, count=1)
            else:
                local_parent = attribute(part, "parent")[len(original_path):].lstrip("/") or "."
                part = re.sub(r' parent="[^"]*"', f' parent="{local_parent}"', part, count=1)
            rewritten.append(part)
        dependencies = closure(rewritten, source)
        outputs[target] = ('[gd_scene format=3]\n\n' + "".join(dependencies + rewritten)).rstrip() + "\n"
        identifier = f"template_{kind}_{content}"
        new_resources.append(f'[ext_resource type="PackedScene" path="res://{relative}" id="{identifier}"]\n\n')
        # 布局属性由独立模板继承，根实例仍保留原名称、父级与唯一标识。
        header = re.sub(r'instance=ExtResource\("2_5pqky"\)', f'instance=ExtResource("{identifier}")', root.splitlines()[0])
        replacements[root] = header + "\n\n"
        removed.update(subtree[1:])
        removed.update(part for part in parts if part.startswith("[editable ")
                       and (attribute(part, "path") == original_path
                            or attribute(part, "path").startswith(original_path + "/")))
    remaining = [replacements.get(part, part) for part in parts
                 if part not in removed and not part.startswith(("[gd_scene ", "[ext_resource ", "[sub_resource "))]
    # 替换后的模板依赖由新声明提供；其余依赖仅属于总览自身。
    source.update(resources(new_resources))
    overview = (parts[0] + "".join(closure(remaining, source) + remaining)).rstrip() + "\n"
    TEMPLATES.mkdir(parents=True, exist_ok=True)
    for path, text in outputs.items():
        path.write_text(text, encoding="utf-8", newline="\n")
    OVERVIEW.write_text(overview, encoding="utf-8", newline="\n")
    print(f"已拆分 {len(outputs)} 棵卡牌子树；总览保持原布局与顺序")


def generate() -> str:
    """总览唯一决定目录成员与排序，单卡根身份唯一决定查询键。"""
    parts = sections(OVERVIEW.read_text(encoding="utf-8"))
    source = resources(parts)
    entries = []
    known = set()
    for directory in DIRECTORIES:
        for part in parts:
            if not part.startswith("[node ") or attribute(part, "parent") != directory:
                continue
            instance = re.search(r'instance=ExtResource\("([^"]+)"\)', part.splitlines()[0])
            if not instance:
                continue  # 非卡牌占位节点不加入运行时索引。
            if re.search(r"^card_reference =", part, re.M):
                raise ValueError("总览不得覆盖卡牌身份；请编辑独立模板后重新生成索引")
            path = attribute(source[("ExtResource", instance.group(1))], "path")
            template_parts = sections((ROOT / path.removeprefix("res://")).read_text(encoding="utf-8"))
            template_root = next(value for value in template_parts if value.startswith("[node "))
            key = identity(template_root, resources(template_parts))
            if key in known:
                raise ValueError(f"总览存在重复卡牌身份：{key}")
            known.add(key)
            entries.append((key, path))
    if not entries:
        raise ValueError("总览未注册任何独立卡牌模板")
    rows = [f'\tVector2i({kind}, {content}): "{path}",' for (kind, content), path in entries]
    return ("## 由 tools/card_catalog.py 根据编辑器总览和单卡身份生成；请勿手动维护第二份目录。\n"
            "## 只有身份和字符串路径，导入本脚本不会加载卡面、角色或纹理。\n"
            "extends RefCounted\n\n"
            "## 按编辑器分类容器顺序保存的模板路径；模仿卡复用目标植物身份。\n"
            "const PATHS: Dictionary[Vector2i, String] = {\n" + "\n".join(rows) + "\n}\n")


def main() -> None:
    """执行一次迁移、生成或只读一致性检查。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--split", action="store_true", help="仅迁移尚未拆分的旧目录")
    parser.add_argument("--check", action="store_true", help="只检查索引是否与权威场景一致")
    args = parser.parse_args()
    if args.split and args.check:
        parser.error("--split 与 --check 不能同时使用")
    if args.split:
        split_legacy()
    generated = generate()
    if args.check:
        if not MANIFEST.exists() or MANIFEST.read_text(encoding="utf-8") != generated:
            raise SystemExit("卡牌索引已过期：请运行 python tools/card_catalog.py")
        print("卡牌索引与总览顺序、单卡身份一致")
    else:
        MANIFEST.write_text(generated, encoding="utf-8", newline="\n")
        print(f"已生成 {MANIFEST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
