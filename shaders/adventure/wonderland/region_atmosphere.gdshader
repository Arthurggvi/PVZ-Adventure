shader_type canvas_item;
render_mode unshaded;
uniform sampler2D region_mask : filter_linear, repeat_disable;
uniform vec2 mask_origin_world;
uniform vec2 mask_extent_world;
uniform vec2 local_origin_world;
uniform vec2 local_extent_world;
uniform float effect_seconds = 0.0;
uniform float period_seconds = 18.0;
uniform float effect_strength = .1;
uniform float event_weight = 0.0;
uniform int style = 0;

void fragment() {
    vec2 world=local_origin_world+UV*local_extent_world;
    vec4 mask=texture(region_mask,(world-mask_origin_world)/mask_extent_world);
    float phase=effect_seconds*6.283185/max(period_seconds,1.0);
    float band=.5+.5*sin(world.y*.12+sin(world.x*.018-phase)*1.6-phase*.4);
    float cloud=.5+.5*sin(world.x*.016-phase*.7+sin(world.y*.035)*.7);
    vec3 tint=vec3(.65,.73,.72);
    float opacity=effect_strength*mask.r;
    if(style==0) {
        // 暖光调制混在既有动态地表之上，不重新采样静态原图。
        tint=mix(vec3(.06,.07,.085),vec3(.96,.69,.32),smoothstep(.2,.7,cloud));
        opacity*=.35+.4*cloud;
    } else if(style==1) {
        tint=vec3(.006,.009,.018);
        opacity*=event_weight;
    } else if(style==2) {
        tint=vec3(.57,.48,.69);
        opacity*=.65+.35*event_weight;
    } else {
        float wisps=pow(band,3.0)*(.25+.75*cloud);
        opacity*=wisps;
        if(style==4) { tint=vec3(.67,.76,.81); }
        if(style==5) { tint=vec3(.61,.46,.29); opacity*=pow(.5+.5*sin(phase),3.0); }
        if(style==6) { tint=vec3(.83,.89,.93); opacity*=pow(.5+.5*cos(phase),3.0); }
        if(style==7) { tint=vec3(.26,.25,.23); opacity*=.6+.4*cloud; }
    }
    COLOR=vec4(tint,opacity);
}
