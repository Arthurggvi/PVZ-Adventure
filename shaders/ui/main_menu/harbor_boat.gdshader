shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
#include "res://shaders/ui/main_menu/wind_field.gdshaderinc"
#include "res://shaders/ui/main_menu/harbor_lighting.gdshaderinc"
#include "res://shaders/ui/main_menu/harbor_boat_motion.gdshaderinc"

uniform sampler2D boat_without_flag : filter_linear, repeat_disable;
uniform sampler2D flag_premult : filter_linear, repeat_disable;
uniform bool flag_enabled = true;
uniform float flag_amplitude = 1.8;
uniform float flag_delay = 0.6;
uniform float flag_cycles = 4.0;
uniform float flag_travel = 4.5;
uniform float flag_root_x = 1589.0;
uniform float flag_tip_x = 1627.0;
uniform sampler2D boat_light_uv : filter_nearest, repeat_disable;
// 原画上的绘制范围，包含船体和旗帜的运动包络。
uniform vec4 region_uv;

void fragment() {
    vec2 boat_uv=harbor_boat_uv(harbor_scene_uv(UV,region_uv));
    vec2 hull_light_uv=texture(boat_light_uv,boat_uv).rg;
    vec3 hull_lighting=texture(TEXTURE,hull_light_uv).rgb;
    vec4 boat;
    if (wind_enabled && wind_strength>0.0 && flag_enabled && flag_amplitude>0.0) {
        // 先在船局部变形自由布面，再由已有boat_uv统一继承船体运动。
        float along=clamp((boat_uv.x*canvas_pixels.x-flag_root_x)/(flag_tip_x-flag_root_x),0.0,1.0);
        float flutter=wind_signal(flag_cycles,flag_delay,along*flag_travel)*flag_amplitude*along*along;
        vec2 flag_uv=boat_uv-vec2(0.0,flutter)/canvas_pixels;
        vec2 flag_light_uv=texture(boat_light_uv,flag_uv).rg;
        vec4 cloth=relit_part(texture(flag_premult,flag_uv),texture(TEXTURE,flag_light_uv).rgb,flag_light_uv);
        boat=relit_part(texture(boat_without_flag,boat_uv),hull_lighting,hull_light_uv);
        boat=apply_entry_guide(cloth,flag_uv)+apply_entry_guide(boat,boat_uv)*(1.0-cloth.a);
    } else {
        boat=relit_part(texture(boat_premult,boat_uv),hull_lighting,hull_light_uv);
        boat=apply_entry_guide(boat,boat_uv);
    }
    COLOR=boat;
}
