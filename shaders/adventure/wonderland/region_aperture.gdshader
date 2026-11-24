shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/adventure/wonderland/region_surface.gdshaderinc"

void fragment() {
    vec2 pixel = UV/TEXTURE_PIXEL_SIZE+tile_pixel_origin;
    if (outside_core(pixel)) { discard; }
    vec2 world = pixel/pixels_per_world;
    vec4 weights = local_mask(world);
    if (weights.r < 0.003) { discard; }
    vec2 q = (world-center_world)/max(radii_world,vec2(1.0));
    float radius = length(q);
    float angle = atan(q.y,q.x);
    float phase = effect_seconds*6.283185/max(period_seconds,1.0);
    vec3 base = texture(TEXTURE,UV).rgb;
    vec3 result;
    if (style == 1) {
        // 中心一直近黑；暗橙吸积带只在孔口内部，金属框完全由原图保留。
        float ribbon = 0.5+0.5*sin(angle*3.0-radius*18.0-phase*2.0);
        float ring = exp(-pow((radius-.73)/.12,2.0))*(.22+.78*pow(ribbon,3.0));
        float core = smoothstep(.25,.9,radius);
        float breath = .9+.1*sin(phase);
        vec2 heat=vec2(sin(q.y*10.0+phase*2.0),cos(q.x*8.0-phase))*amplitude_world*.707*core*weights.r;
        base=texture(TEXTURE,UV+heat*pixels_per_world*TEXTURE_PIXEL_SIZE).rgb;
        result = base*(.14+.5*core);
        result += vec3(.62,.19,.045)*ring*(.25+event_weight*.15)*breath*effect_strength;
        result += vec3(.25,.09,.025)*weights.g*(.12+.04*sin(phase));
    } else {
        // 初代机器的孔内光膜和分段扫描；结构轮廓不参与扭曲。
        vec2 offset=vec2(sin(q.y*12.0-phase),cos(q.x*11.0+phase*.8))*amplitude_world*(.3+.7*event_weight);
        vec3 refracted=texture(TEXTURE,UV+offset*pixels_per_world*TEXTURE_PIXEL_SIZE).rgb;
        float segment=floor((angle+3.14159265)*12.0/6.283185);
        float sweep=pow(max(0.0,cos(segment*6.283185/12.0-phase)),8.0);
        float threads=pow(max(0.0,sin(q.y*19.0+sin(q.x*6.0-phase)*1.5-phase*2.0)),10.0);
        vec3 tint=mix(vec3(.28,.62,.64),vec3(.46,.34,.65),.5+.5*sin(q.y*4.0+phase*.5));
        result=mix(base,refracted,.4+event_weight*.3);
        result+=tint*(weights.g*(.18+.42*sweep)+threads*.08+event_weight*.12)*effect_strength;
        result=mix(result,tint*.55,event_weight*.12*(1.0-weights.g));
    }
    COLOR=vec4(result,weights.r);
}
