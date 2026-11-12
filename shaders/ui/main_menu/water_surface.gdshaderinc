// 水面算法的唯一替换点。返回原图像素单位的有界位移/无量纲亮纹；不管理船或码头。
uniform int water_pattern = 0;
uniform float water_angle = 0.0;
uniform float water_transverse_ratio = 0.32;
uniform vec3 water_shimmer_scale = vec3(37.0,9.0,21.0);
uniform vec2 ripple_origin = vec2(1567.0,419.0);
uniform float ripple_spacing = 35.0;
uniform float ripple_cycles = 2.0;
vec2 water_surface_offset(vec2 point,vec2 lengths) {
    if (water_pattern==2) { return vec2(0.0); }
    if (water_pattern==1) {
        vec2 delta=point-ripple_origin;
        float wave=sin(length(delta)/ripple_spacing-water_angle*ripple_cycles);
        return delta/max(length(delta),1.0)*wave;
    }
    return vec2(sin(point.y/lengths.x+water_angle),water_transverse_ratio*sin(point.x/lengths.y-water_angle*2.0));
}
float water_surface_shimmer(vec2 point) {
    if (water_pattern==2) { return 0.0; }
    if (water_pattern==1) {
        return sin(length(point-ripple_origin)/ripple_spacing-water_angle*ripple_cycles);
    }
    return sin(point.x/water_shimmer_scale.x+point.y/water_shimmer_scale.y+water_angle*2.0)*sin(point.y/water_shimmer_scale.z-water_angle);
}
