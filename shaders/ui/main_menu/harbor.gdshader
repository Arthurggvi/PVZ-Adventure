shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/ui/main_menu/water_surface.gdshaderinc"
#include "res://shaders/ui/main_menu/harbor_lighting.gdshaderinc"
#include "res://shaders/ui/main_menu/harbor_boat_motion.gdshaderinc"

// 全景绘制只负责海面补底、波纹和船接触亮边。
uniform sampler2D masks : filter_linear, repeat_disable;
uniform sampler2D clean_color : filter_linear, repeat_disable;
uniform sampler2D clean_light_uv : filter_nearest, repeat_disable;
uniform bool motion_enabled = true;
uniform bool water_enabled = true;
uniform bool contact_enabled = true;
uniform float water_displacement_px = 1.05;
uniform float water_glint = 0.035;
uniform vec2 wave_lengths = vec2(82.0,41.0);
uniform float water_time_gain = 1.0;
uniform float contact_width = 1.25;
uniform float contact_strength = 0.12;

void fragment() {
    vec4 original=texture(TEXTURE,UV);
    if (!motion_enabled) {
        COLOR=apply_entry_guide(original,UV);
    } else {
        vec2 point=UV*canvas_pixels;
        vec4 region=texture(masks,UV);
        float water=water_enabled?region.b:0.0;
        vec2 drift=water_surface_offset(point,wave_lengths);
        vec2 water_uv=UV+drift*water_displacement_px*water/canvas_pixels;
        // 静态轮廓先描边，补图随后填回被活动船移开的区域。
        vec4 guide=texture(clean_light_uv,water_uv);
        vec3 clean=texture(clean_color,water_uv).rgb*light_transfer(texture(TEXTURE,guide.rg).rgb,guide.rg);
        vec4 base=apply_entry_guide(texture(TEXTURE,water_uv),water_uv);
        vec3 result=mix(base.rgb,clean,guide.b);
        float shimmer=water_surface_shimmer(point);
        result*=1.0+water_glint*water*shimmer*water_time_gain;
        if (contact_enabled) {
            vec2 boat_uv=harbor_boat_uv(UV);
            float here=texture(boat_premult,boat_uv).a;
            float above=texture(boat_premult,boat_uv-vec2(0.0,contact_width)/canvas_pixels).a;
            float rim=max(above-here,0.0)*smoothstep(pivot.y-7.0,pivot.y+6.0,point.y-boat_heave_px());
            result*=1.0+rim*contact_strength*water_time_gain*region.b;
        }
        COLOR=vec4(clamp(result,0.0,1.0),original.a);
    }
}
