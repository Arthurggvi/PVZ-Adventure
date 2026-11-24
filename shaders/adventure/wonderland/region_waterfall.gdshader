shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/adventure/wonderland/region_surface.gdshaderinc"

void fragment() {
    vec2 pixel = UV/TEXTURE_PIXEL_SIZE+tile_pixel_origin;
    if (outside_core(pixel)) { discard; }
    vec2 world = pixel/pixels_per_world;
    vec4 weights = local_mask(world);
    if (weights.r < 0.003) { discard; }
    float phase = effect_seconds*6.283185/max(period_seconds,1.0);
    float fall = sin(weights.b*19.0-phase*3.0 + sin(world.x*1.4)*0.4);
    float detail = sin(weights.b*41.0-phase*5.0+world.x*0.9);
    vec2 offset = vec2(0.08*sin(phase+world.y),fall*0.5)*amplitude_world*weights.g;
    vec3 base = texture(TEXTURE,UV-offset*pixels_per_world*TEXTURE_PIXEL_SIZE).rgb;
    float streak = pow(max(0.0,fall*.68+detail*.32),4.0);
    vec3 water = base*(0.97+fall*.025) + vec3(.52,.68,.74)*streak*effect_strength*.32;
    COLOR=vec4(water,weights.r);
}
