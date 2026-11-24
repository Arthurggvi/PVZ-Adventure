shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/adventure/wonderland/region_surface.gdshaderinc"
#include "res://shaders/ui/main_menu/wind_field.gdshaderinc"

void fragment() {
    vec2 pixel = UV/TEXTURE_PIXEL_SIZE + tile_pixel_origin;
    if (outside_core(pixel)) { discard; }
    vec2 world = pixel/pixels_per_world;
    vec4 weights = local_mask(world);
    if (weights.r < 0.003) { discard; }
    float delay = dot(world,vec2(0.021,0.009));
    // 局部摆动消费区域周期，阵风仍使用菜单共用风场的十八秒参数。
    float phase = mod(effect_seconds,period_seconds)*6.28318530718/period_seconds;
    float gust = 1.0-gust_depth*0.5+gust_depth*0.5*cos(wind_angle*gust_cycles);
    float wave = (sin(phase-delay)+0.22*sin(phase*2.0-delay*1.7))*gust*wind_strength/1.22;
    vec2 displacement = vec2(wave,sin(phase-delay+0.7)*0.22);
    displacement *= amplitude_world*weights.g;
    vec3 shifted = texture(TEXTURE,UV-displacement*pixels_per_world*TEXTURE_PIXEL_SIZE).rgb;
    COLOR = vec4(shifted,weights.r*effect_strength);
}
