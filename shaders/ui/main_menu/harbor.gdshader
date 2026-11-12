shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/ui/main_menu/wind_field.gdshaderinc"
uniform sampler2D boat_without_flag : filter_linear, repeat_disable;
uniform sampler2D flag_premult : filter_linear, repeat_disable;
uniform bool flag_enabled = true;
uniform float flag_amplitude = 1.8;
uniform float flag_delay = 0.6;
uniform float flag_cycles = 4.0;
uniform float flag_travel = 4.5;
uniform float flag_root_x = 1589.0;
uniform float flag_tip_x = 1627.0;
// 真实预乘透明部件：海底补图→活动船→固定码头，颜色与alpha一起过滤。
uniform sampler2D masks : filter_linear, repeat_disable;
uniform sampler2D master_color : filter_linear, repeat_disable;
uniform sampler2D clean_color : filter_linear, repeat_disable;
uniform sampler2D clean_light_uv : filter_nearest, repeat_disable;
uniform sampler2D boat_premult : filter_linear, repeat_disable;
uniform sampler2D boat_light_uv : filter_nearest, repeat_disable;
uniform sampler2D fixed_premult : filter_linear, repeat_disable;
uniform sampler2D fixed_light_uv : filter_nearest, repeat_disable;
uniform vec2 canvas_pixels = vec2(1672.0,941.0);
uniform bool motion_enabled = true;
uniform bool boat_enabled = true;
uniform bool water_enabled = true;
uniform bool contact_enabled = true;
uniform float phase = 0.0;
uniform vec2 pivot = vec2(1568.0,403.0);
uniform float heave_px = 2.4;
uniform float sway_px = 0.35;
uniform float roll_radians = 0.002793;
uniform float phase_offset = 0.0;
uniform float water_displacement_px = 1.05;
uniform float water_glint = 0.035;
uniform vec2 wave_lengths = vec2(82.0,41.0);
uniform float water_time_gain = 1.0;
uniform float contact_width = 1.25;
uniform float contact_strength = 0.12;
vec3 light_transfer(sampler2D source,vec2 uv) {
    return texture(source,uv).rgb/max(texture(master_color,uv).rgb,vec3(0.015));
}
vec4 clean_scene(sampler2D source,vec2 uv) {
    vec4 guide=texture(clean_light_uv,uv);
    vec3 patched=texture(clean_color,uv).rgb*light_transfer(source,guide.rg);
    return vec4(mix(texture(source,uv).rgb,patched,guide.b),1.0);
}
vec4 relit_part(sampler2D source,sampler2D part,sampler2D guide,vec2 uv) {
    vec4 pm=texture(part,uv);
    return vec4(pm.rgb*light_transfer(source,texture(guide,uv).rg),pm.a);
}
void fragment() {
    vec4 original=texture(TEXTURE,UV);
    if (!motion_enabled) {
        COLOR=original;
    } else {
        float angle=phase*6.28318530718+phase_offset;
        vec2 point=UV*canvas_pixels;
        vec4 region=texture(masks,UV);
        float water=water_enabled?region.b:0.0;
        vec2 drift=vec2(sin(point.y/wave_lengths.x+angle),0.32*sin(point.x/wave_lengths.y-angle*2.0));
        vec2 water_uv=UV+drift*water_displacement_px*water/canvas_pixels;
        vec4 result=clean_scene(TEXTURE,water_uv);
        float shimmer=sin(point.x/37.0+point.y/9.0+angle*2.0)*sin(point.y/21.0-angle);
        result.rgb*=1.0+water_glint*water*shimmer*water_time_gain;
        vec2 displacement=boat_enabled?vec2(sway_px*sin(angle*2.0),heave_px*sin(angle)):vec2(0.0);
        float turn=boat_enabled?roll_radians*sin(angle):0.0;
        float cosine=cos(turn),sine=sin(turn);
        mat2 inverse_rotation=mat2(vec2(cosine,-sine),vec2(sine,cosine));
        vec2 boat_uv=(inverse_rotation*(point-pivot-displacement)+pivot)/canvas_pixels;
        if (contact_enabled) {
            float here=texture(boat_premult,boat_uv).a;
            float above=texture(boat_premult,boat_uv-vec2(0.0,contact_width)/canvas_pixels).a;
            float rim=max(above-here,0.0)*smoothstep(pivot.y-7.0,pivot.y+6.0,point.y-displacement.y);
            result.rgb*=1.0+rim*contact_strength*water_time_gain*region.b;
        }
        vec4 boat=relit_part(TEXTURE,boat_premult,boat_light_uv,boat_uv);
        if (wind_enabled && wind_strength>0.0 && flag_enabled && flag_amplitude>0.0) {
            // 先在船局部变形自由布面，再由已有boat_uv统一继承船体运动。
            float along=clamp((boat_uv.x*canvas_pixels.x-flag_root_x)/(flag_tip_x-flag_root_x),0.0,1.0);
            float flutter=wind_signal(flag_cycles,flag_delay,along*flag_travel)*flag_amplitude*along*along;
            vec2 flag_uv=boat_uv-vec2(0.0,flutter)/canvas_pixels;
            vec4 cloth=relit_part(TEXTURE,flag_premult,boat_light_uv,flag_uv);
            boat=relit_part(TEXTURE,boat_without_flag,boat_light_uv,boat_uv);
            boat=cloth+boat*(1.0-cloth.a);
        }
        result.rgb=boat.rgb+result.rgb*(1.0-boat.a);
        vec4 fixed=relit_part(TEXTURE,fixed_premult,fixed_light_uv,UV);
        result.rgb=fixed.rgb+result.rgb*(1.0-fixed.a);
        COLOR=vec4(clamp(result.rgb,0.0,1.0),original.a);
    }
}
