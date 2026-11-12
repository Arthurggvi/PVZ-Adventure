shader_type canvas_item;
render_mode unshaded;
// TEXTURE 为同一时段的实时受光结果；船体色彩、法线受光与窗灯一起采样。
uniform sampler2D masks : filter_linear, repeat_disable;
uniform sampler2D clean_lookup : filter_nearest, repeat_disable;
uniform sampler2D boat_lookup : filter_nearest, repeat_disable;
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
uniform vec2 contact_center = vec2(1567.0,419.0);
uniform vec2 contact_radii = vec2(85.0,10.5);
uniform float contact_width = 1.25;
uniform float contact_strength = 0.12;
vec4 clean_scene(sampler2D source, vec2 uv) {
    vec4 lookup=texture(clean_lookup,uv);
    return texture(source,mix(uv,lookup.rg,lookup.b));
}
void fragment() {
    vec4 untouched=texture(TEXTURE,UV);
    if (!motion_enabled) {
        COLOR=untouched;
    } else {
        float angle=phase*6.28318530718+phase_offset;
        vec2 point=UV*canvas_pixels;
        vec4 region=texture(masks,UV);
        float water=water_enabled?region.b:0.0;
        vec2 drift=vec2(sin(point.y/wave_lengths.x+angle),0.32*sin(point.x/wave_lengths.y-angle*2.0));
        vec2 surface_uv=UV+drift*water_displacement_px*water/canvas_pixels;
        vec4 result=clean_scene(TEXTURE,surface_uv);
        float shimmer=sin(point.x/37.0+point.y/9.0+angle*2.0)*sin(point.y/21.0-angle);
        result.rgb*=1.0+water_glint*water*shimmer*water_time_gain;
        vec2 displacement=boat_enabled?vec2(sway_px*sin(angle*2.0),heave_px*sin(angle)):vec2(0.0);
        float turn=boat_enabled?roll_radians*sin(angle):0.0;
        if (contact_enabled) {
            vec2 ring_center=contact_center+displacement;
            vec2 radii=contact_radii+vec2(2.0*(1.0+sin(angle)),0.8*(1.0+sin(angle)));
            float distance=abs(length((point-ring_center)/radii)-1.0)*radii.y;
            float band=1.0-smoothstep(0.0,contact_width,distance);
            band*=smoothstep(ring_center.y-4.0,ring_center.y+2.0,point.y)*region.b;
            result.rgb*=1.0+band*contact_strength*water_time_gain;
        }
        float c=cos(turn),s=sin(turn);
        mat2 inverse_rotation=mat2(vec2(c,-s),vec2(s,c));
        vec2 boat_point=inverse_rotation*(point-pivot-displacement)+pivot;
        vec2 boat_uv=boat_point/canvas_pixels;
        float alpha=texture(masks,boat_uv).r;
        vec4 boat_sample=texture(boat_lookup,boat_uv);
        vec4 boat=texture(TEXTURE,mix(boat_uv,boat_sample.rg,boat_sample.b));
        result=mix(result,boat,alpha);
        // 码头立柱与前方围栏最后回盖；它们不随船体摇动。
        result=mix(result,untouched,region.g);
        COLOR=vec4(clamp(result.rgb,0.0,1.0),untouched.a);
    }
}
