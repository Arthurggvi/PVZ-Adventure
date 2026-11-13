shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/ui/main_menu/wind_field.gdshaderinc"
#include "res://shaders/ui/main_menu/water_surface.gdshaderinc"
// 前一级视口颜色，采样方式与全幅合成节点一致。
uniform sampler2D scene_color : filter_linear, repeat_disable;
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
// 复用悬停蒙版的绿通道内缘；强度由牌匾与焦点状态同步提供。
uniform sampler2D entry_guide_mask : filter_linear, repeat_disable;
uniform float entry_guide_strength = 0.0;
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
vec3 light_transfer(vec2 uv) {
    return texture(scene_color,uv).rgb/max(texture(master_color,uv).rgb,vec3(0.015));
}
// 在各部件局部坐标上描边，并保留其预乘透明度。
vec4 apply_entry_guide(vec4 part, vec2 uv) {
    if (entry_guide_strength > 0.0 && part.a > 0.0) {
        // 绿通道提供内缘，红通道把加宽的柔光限制在物件内。
        vec2 shape = texture(entry_guide_mask,uv).rg;
        if (shape.r > 0.0) {
            // 向内扩约两个原画像素，让缩放后的描边依然可见。
            vec2 spread = vec2(1.8,0.0) / canvas_pixels;
            float nearby = max(max(texture(entry_guide_mask,uv-spread.xy).g,texture(entry_guide_mask,uv+spread.xy).g),
                               max(texture(entry_guide_mask,uv-spread.yx).g,texture(entry_guide_mask,uv+spread.yx).g));
            float edge = min(1.0, max(1.5 * shape.g, 0.58 * nearby * shape.r));
            part.rgb = mix(part.rgb,vec3(1.0,0.81,0.31) * part.a,edge * entry_guide_strength);
        }
    }
    return part;
}
vec4 clean_scene(vec2 uv) {
    vec4 guide=texture(clean_light_uv,uv);
    vec3 patched=texture(clean_color,uv).rgb*light_transfer(guide.rg);
    // 补底区域原本是船的位置，先给静态码头描边，再由海面补底盖住原船位。
    vec4 base=apply_entry_guide(texture(scene_color,uv),uv);
    return vec4(mix(base.rgb,patched,guide.b),1.0);
}
vec4 relit_part(sampler2D part,sampler2D guide,vec2 uv) {
    vec4 pm=texture(part,uv);
    return vec4(pm.rgb*light_transfer(texture(guide,uv).rg),pm.a);
}
void fragment() {
    vec4 original=texture(scene_color,UV);
    if (!motion_enabled) {
        COLOR=apply_entry_guide(original,UV);
    } else {
        float angle=phase*6.28318530718+phase_offset;
        vec2 point=UV*canvas_pixels;
        vec4 region=texture(masks,UV);
        float water=water_enabled?region.b:0.0;
        vec2 drift=water_surface_offset(point,wave_lengths);
        vec2 water_uv=UV+drift*water_displacement_px*water/canvas_pixels;
        vec4 result=clean_scene(water_uv);
        float shimmer=water_surface_shimmer(point);
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
        vec4 boat=relit_part(boat_premult,boat_light_uv,boat_uv);
        if (wind_enabled && wind_strength>0.0 && flag_enabled && flag_amplitude>0.0) {
            // 先在船局部变形自由布面，再由已有boat_uv统一继承船体运动。
            float along=clamp((boat_uv.x*canvas_pixels.x-flag_root_x)/(flag_tip_x-flag_root_x),0.0,1.0);
            float flutter=wind_signal(flag_cycles,flag_delay,along*flag_travel)*flag_amplitude*along*along;
            vec2 flag_uv=boat_uv-vec2(0.0,flutter)/canvas_pixels;
            vec4 cloth=relit_part(flag_premult,boat_light_uv,flag_uv);
            boat=relit_part(boat_without_flag,boat_light_uv,boat_uv);
            boat=apply_entry_guide(cloth,flag_uv)+apply_entry_guide(boat,boat_uv)*(1.0-cloth.a);
        } else {
            boat=apply_entry_guide(boat,boat_uv);
        }
        result.rgb=boat.rgb+result.rgb*(1.0-boat.a);
        vec4 fixed=apply_entry_guide(relit_part(fixed_premult,fixed_light_uv,UV),UV);
        result.rgb=fixed.rgb+result.rgb*(1.0-fixed.a);
        COLOR=vec4(clamp(result.rgb,0.0,1.0),original.a);
    }
}
