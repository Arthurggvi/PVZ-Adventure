shader_type canvas_item;
render_mode unshaded;
uniform sampler2D region_mask : filter_linear, repeat_disable;
uniform vec2 mask_origin_world;
uniform vec2 mask_extent_world;
uniform int shape = 0;
varying vec2 world_position;
varying vec4 particle_color;
varying float foreground_layer;

void vertex() {
    world_position=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy;
    particle_color=COLOR;
    foreground_layer=INSTANCE_CUSTOM.r;
}

void fragment() {
    vec2 uv=(world_position-mask_origin_world)/mask_extent_world;
    if(any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0)))) { discard; }
    vec4 mask=texture(region_mask,uv);
    float coverage=mix(mask.g,mask.r,foreground_layer);
    vec2 q=(UV-.5)*2.0;
    float radius=length(q);
    if(shape==1) { radius=abs(q.x)+pow(abs(q.y),.7); }
    float alpha=1.0-smoothstep(.25,1.0,radius);
    COLOR=vec4(particle_color.rgb,particle_color.a*alpha*coverage);
}
