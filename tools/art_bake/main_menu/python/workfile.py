"""港口原生工作副本：保护原图、必要部件和原始坐标控制层；保存重开核对。"""
from pathlib import Path
import hashlib,json,os
import gi

gi.require_version('Gimp','3.0');gi.require_version('Gegl','0.4')
from gi.repository import Gimp,Gegl,Gio


def build(root: Path) -> None:
    manifest=json.loads((root/'config/pipeline.json').read_text(encoding='utf-8'))
    size=manifest['canvas'];rect=Gegl.Rectangle.new(0,0,size[0],size[1])
    assert hashlib.sha256((root/'master_original.png').read_bytes()).hexdigest()==manifest['master_sha256']
    def file(path):return Gio.File.new_for_path(str(path))
    def data(layer,fmt="R'G'B' u8"):
        return bytes(layer.get_buffer().get(rect,1.0,fmt,Gegl.AbyssPolicy.NONE))
    def load(image,path,name,parent=None,visible=True):
        layer=Gimp.file_load_layer(Gimp.RunMode.NONINTERACTIVE,image,file(path));assert layer is not None,str(path)
        image.insert_layer(layer,parent,0);layer.set_name(name);layer.set_visible(visible);return layer
    def group(image,name,visible=False):
        node=Gimp.GroupLayer.new(image,name);image.insert_layer(node,None,0);node.set_visible(visible);return node
    image=Gimp.file_load(Gimp.RunMode.NONINTERACTIVE,file(root/'master_original.png'));assert image is not None
    original=image.get_layers()[0];original.set_name('00_ORIGINAL_LOCKED_原始母图');original.set_visible(False)
    original.set_lock_content(True);original.set_lock_position(True);original_hash=hashlib.sha256(data(original)).hexdigest()
    load(image,root/'ground_finished.png','10_APPROVED_GROUND_保留既有地面',visible=False)
    layers=group(image,'20_HARBOR_PARTS_必要活动部件',False)
    load(image,root/'assets/clean_plate.png','01_CLEAN_PLATE_仅有限运动包络可见补底',layers)
    load(image,root/'assets/boat.png','02_BOAT_通道去底色_遮挡窄带补齐',layers)
    load(image,root/'assets/dock_foreground.png','03_DOCK_FOREGROUND_独立固定栏柱与栏绳',layers)
    controls=group(image,'30_HARBOR_MASKS_原图坐标控制',False);hashes={}
    for filename in ['boat_alpha.png','fixed_alpha.png','water_weight.png','motion_support.png']:
        layer=load(image,root/'assets'/filename,filename,controls)
        values=data(layer,"Y' u8");mask=layer.create_mask(Gimp.AddMaskType.BLACK);layer.add_mask(mask)
        mask.get_buffer().set(rect,'Y u8',values);layer.set_apply_mask(False)
        hashes[filename]=hashlib.sha256(values).hexdigest()
    if manifest.get('features',{}).get('wind',False):
        wind=group(image,'31_WIND_CONTROLS_树冠布料与固定端',False)
        for filename in ['canopy_left.png','canopy_rear.png','awning_alpha.png','awning_pin.png','flag_select.png','protected_anchors.png','wind_support.png']:
            layer=load(image,root/'wind_assets'/filename,filename,wind)
            values=data(layer,"Y' u8");mask=layer.create_mask(Gimp.AddMaskType.BLACK);layer.add_mask(mask)
            mask.get_buffer().set(rect,'Y u8',values);layer.set_apply_mask(False)
            hashes[filename]=hashlib.sha256(values).hexdigest()
        parts=group(image,'32_WIND_PARTS_原像素布料及有限补底',False)
        for filename in ['awning_plate.png','awning.png','flag.png']:
            load(image,root/'wind_assets'/filename,filename,parts)
    refs=group(image,'40_GPU_REFERENCES_真实动态静帧_非时间参数',True)
    for filename in ['day_disabled.png','day_phase_25.png','night_phase_25.png']:
        load(image,root/'renders'/filename,filename,refs,filename=='day_phase_25.png')
    ui=group(image,'50_UI_OCCUPANCY_独立界面占位',False)
    for filename in ['layer_profile_proposed.png','layer_console_proposed.png','layer_toolbar_expanded.png']:
        load(image,root/'ui'/filename,filename,ui)
    destination=root/manifest['workfile']
    assert Gimp.file_save(Gimp.RunMode.NONINTERACTIVE,image,file(destination),None)
    image.delete();reopened=Gimp.file_load(Gimp.RunMode.NONINTERACTIVE,file(destination));assert reopened is not None
    top=reopened.get_layers();orig=next(l for l in top if l.get_name().startswith('00_'));controls=next(l for l in top if l.get_name().startswith('30_'))
    check_groups=[node for node in top if node.get_name().startswith(('30_','31_'))]
    checks={layer.get_name():hashlib.sha256(data(layer.get_mask(),'Y u8')).hexdigest()==hashes[layer.get_name()] for node in check_groups for layer in node.get_children()}
    report={'source_pixels_unchanged':hashlib.sha256(data(orig)).hexdigest()==original_hash,'source_locked':orig.get_lock_content() and orig.get_lock_position(),
      'mask_checks':checks,'file_bytes':destination.stat().st_size,'canvas':size,
      'notes':'XCF is editing/inspection view; shaders and config own motion. Premultiplied layers and material lighting references remain separate float32 products. Manual edits do not reverse-sync.'}
    assert report['source_pixels_unchanged'] and report['source_locked'] and all(checks.values())
    reopened.delete();(root/'reports/workfile.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report),flush=True)


if __name__=='__main__':
    build(Path(os.environ['ARTCONTROL_RUN']))
