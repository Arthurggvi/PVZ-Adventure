shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
#include "res://shaders/ui/main_menu/harbor_lighting.gdshaderinc"

uniform sampler2D fixed_premult : filter_linear, repeat_disable;
uniform sampler2D fixed_light_uv : filter_nearest, repeat_disable;
// 码头四边形的全景 UV 包络，限制固定前景的绘制范围。
uniform vec4 region_uv;

void fragment() {
    vec2 scene_uv=harbor_scene_uv(UV,region_uv);
    vec2 light_uv=texture(fixed_light_uv,scene_uv).rg;
    vec4 dock=relit_part(texture(fixed_premult,scene_uv),texture(TEXTURE,light_uv).rgb,light_uv);
    COLOR=apply_entry_guide(dock,scene_uv);
}
