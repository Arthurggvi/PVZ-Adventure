shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/ui/main_menu/wind_field.gdshaderinc"
// 前一级视口颜色，采样方式与全幅合成节点一致。
uniform sampler2D scene_color : filter_linear, repeat_disable;
uniform sampler2D canopy_weights : filter_linear, repeat_disable;
uniform sampler2D awning_premult : filter_linear, repeat_disable;
uniform sampler2D awning_light_uv : filter_nearest, repeat_disable;
uniform sampler2D awning_plate : filter_linear, repeat_disable;
uniform sampler2D awning_plate_uv : filter_nearest, repeat_disable;
uniform sampler2D awning_support : filter_nearest, repeat_disable;
uniform sampler2D master_color : filter_linear, repeat_disable;
uniform vec2 canvas_pixels = vec2(1672.0,941.0);
uniform bool canopy_enabled = true;
uniform vec2 canopy_amplitude = vec2(2.5,1.75);
uniform vec2 canopy_delay = vec2(0.0,0.85);
uniform float canopy_scale = 95.0;
uniform float canopy_cycles = 2.0;
uniform bool awning_enabled = true;
uniform float awning_amplitude = 1.35;
uniform float awning_delay = 1.4;
uniform float awning_cycles = 2.0;
uniform float awning_travel = 2.6;
uniform float awning_horizontal = 0.14;
uniform vec2 anchor_start = vec2(164.0,637.0);
uniform vec2 anchor_end = vec2(338.0,583.0);
uniform float cloth_depth = 72.0;
uniform float pin_band = 5.0;
uniform vec2 cloth_outward = vec2(44.0,53.0);
uniform float side_anchor_uv = 0.12;
vec3 wind_light_transfer(vec2 uv) {
    return texture(scene_color,uv).rgb/max(texture(master_color,uv).rgb,vec3(0.015));
}
void fragment() {
    vec4 original=texture(scene_color,UV);
    if (!wind_enabled || wind_strength<=0.0) {
        COLOR=original;
    } else {
        vec2 point=UV*canvas_pixels;
        vec2 foliage=texture(canopy_weights,UV).rg;
        vec4 result=original;
        if (canopy_enabled && max(foliage.r,foliage.g)>0.0) {
            float space=(point.x+point.y*0.32)/canopy_scale;
            float left=wind_signal(canopy_cycles,canopy_delay.x,space);
            float rear=wind_signal(canopy_cycles,canopy_delay.y,space);
            float offset=dot(foliage*canopy_amplitude,vec2(left,rear));
            result=texture(scene_color,UV-wind_direction*offset/canvas_pixels);
        }
        if (awning_enabled && awning_amplitude>0.0 && texture(awning_support,UV).r>0.0) {
            float line_y=anchor_start.y+(point.x-anchor_start.x)*(anchor_end.y-anchor_start.y)/(anchor_end.x-anchor_start.x);
            float depth=point.y-line_y;
            vec2 span=anchor_end-anchor_start;
            vec2 relative=point-anchor_start;
            float u=(relative.x*cloth_outward.y-relative.y*cloth_outward.x)/(span.x*cloth_outward.y-span.y*cloth_outward.x);
            float side=smoothstep(0.0,side_anchor_uv,u)*(1.0-smoothstep(1.0-side_anchor_uv,1.0,u));
            float weight=smoothstep(pin_band,cloth_depth,depth)*side;
            float travel=(point.x-anchor_start.x)/(anchor_end.x-anchor_start.x)*awning_travel;
            float flow=wind_signal(awning_cycles,awning_delay,travel)*awning_amplitude*weight;
            vec2 local_uv=UV-vec2(flow*awning_horizontal*wind_direction.x,flow)/canvas_pixels;
            vec4 guide=texture(awning_plate_uv,UV);
            vec3 under=texture(awning_plate,UV).rgb*wind_light_transfer(guide.rg);
            vec3 base=mix(original.rgb,under,guide.b);
            vec4 cloth=texture(awning_premult,local_uv);
            cloth.rgb*=wind_light_transfer(texture(awning_light_uv,local_uv).rg);
            result.rgb=mix(original.rgb,cloth.rgb+base*(1.0-cloth.a),side);
        }
        COLOR=vec4(clamp(result.rgb,0.0,1.0),original.a);
    }
}
