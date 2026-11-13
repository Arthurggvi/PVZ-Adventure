shader_type canvas_item;
render_mode unshaded;
// 同一母图：地面改变在受光前混合；墙面/地面接收光与灯源光晕独立。
uniform sampler2D base_working : filter_nearest, repeat_disable;
uniform sampler2D ground_finished : filter_nearest, repeat_disable;
uniform sampler2D normal_data : filter_nearest, repeat_disable;
uniform sampler2D control_data : filter_nearest, repeat_disable;
uniform sampler2D environment_data : filter_nearest, repeat_disable;
uniform sampler2D spill_data : filter_nearest, repeat_disable;
uniform sampler2D local_receiver_data : filter_nearest, repeat_disable;
uniform sampler2D local_emission_data : filter_nearest, repeat_disable;
uniform sampler2D source_halo_data : filter_nearest, repeat_disable;
uniform sampler2D old_group_emission_data : filter_nearest, repeat_disable;
uniform bool enabled = true;
uniform float normal_strength = 1.0;
uniform float repair_mix = 1.0;
uniform float ground_strength = 1.0;
uniform float local_strength = 0.0;
uniform float halo_strength = 0.0;
uniform float legacy_spill_strength = 0.0;
uniform float emission_balance = 1.0;
uniform vec4 local_group_energy = vec4(1.0);
uniform vec4 emission_group_energy = vec4(1.0);
uniform vec4 halo_group_energy = vec4(1.0);
uniform vec3 local_color = vec3(1.0,0.66,0.33);
uniform vec3 halo_color = vec3(1.0,0.64,0.26);
uniform vec3 reference_light = vec3(-0.45,0.60,0.66);
uniform vec3 reference_ambient = vec3(0.76,0.78,0.80);
uniform vec3 reference_key = vec3(0.30,0.28,0.25);
uniform vec3 light_direction = vec3(-0.45,0.60,0.66);
uniform vec3 ambient_rgb = vec3(0.76,0.78,0.80);
uniform vec3 key_rgb = vec3(0.30,0.28,0.25);
uniform float window_energy = 0.0;
uniform float spill_energy = 0.0;
uniform float spill_scale = 0.22;
uniform vec3 window_color = vec3(1.0,0.49,0.11);
uniform vec3 spill_color = vec3(1.0,0.46,0.12);
uniform float saturation = 1.0;
uniform vec3 water_tint = vec3(1.0);
uniform vec3 distant_tint = vec3(1.0);
uniform float sky_mix = 0.0;
uniform vec3 sky_top = vec3(0.30,0.52,0.85);
uniform vec3 sky_horizon = vec3(0.60,0.76,0.92);
uniform vec3 cloud_color = vec3(0.87,0.93,1.0);
uniform float sky_height_uv = 0.1488;
// 地平线的宽幅散射光，只作用于已发布天空蒙版，不绘制额外日轮。
uniform float horizon_glow_strength = 0.0;
// 地平线散射光的显示色，由同一日周期提供。
uniform vec3 horizon_glow_color = vec3(1.0,0.82,0.57);
// 散射光中心的画布横坐标，0～1；与当日主光方向一起缓慢变化。
uniform float horizon_glow_x = 0.84;
// 远景与远海空气透视的混合量，不给近处建筑叠加雾幕。
uniform float distance_haze_strength = 0.0;
// 前景边缘的受光衰减；只压低反射底色，不遮暗后续叠加的窗灯。
uniform float foreground_shade_strength = 0.0;
vec3 to_linear(vec3 s) {
    return mix(s/12.92,pow((s+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),s));
}
vec3 to_srgb(vec3 l) {
    l=max(l,vec3(0.0));
    return mix(l*12.92,1.055*pow(l,vec3(1.0/2.4))-vec3(0.055),step(vec3(0.0031308),l));
}
void fragment() {
    vec4 original=texture(TEXTURE,UV);
    if (!enabled) {
        COLOR=original;
    } else {
        vec3 control=texture(control_data,UV).rgb;
        vec4 environment=texture(environment_data,UV);
        vec3 working=mix(texture(base_working,UV).rgb,texture(ground_finished,UV).rgb,ground_strength);
        vec3 painted=mix(original.rgb,working,repair_mix);
        vec3 normal=normalize(mix(vec3(0,0,1),normalize(texture(normal_data,UV).rgb*2.0-1.0),control.r*normal_strength));
        float incidence=max(dot(normal,normalize(light_direction)),0.0);
        float reference=max(dot(normal,normalize(reference_light)),0.0);
        vec3 baseline=max(reference_ambient+reference_key*reference,vec3(0.05));
        vec3 base_linear=to_linear(painted);
        vec3 lit=base_linear*(ambient_rgb+key_rgb*incidence)/baseline*control.g;
        float luma=dot(lit,vec3(0.2126,0.7152,0.0722));
        lit=mix(vec3(luma),lit,saturation);
        lit*=mix(vec3(1.0),water_tint,environment.g);
        lit*=mix(vec3(1.0),distant_tint,environment.b);
        // 远景蒙版包含图书馆边缘，纵向衰减让空气透视在地平线附近收束。
        float horizon_depth=1.0-smoothstep(0.10,0.29,UV.y); // 天空以外的远近分离权重。
        float far_sea=environment.g*smoothstep(0.76,0.82,UV.x); // 排除同通道中的研究室玻璃。
        float haze_mask=clamp(environment.b+far_sea*0.65,0.0,1.0)*horizon_depth; // 有界空气透视蒙版。
        lit=mix(lit,to_linear(sky_horizon),haze_mask*distance_haze_strength);
        float foreground=smoothstep(0.56,1.0,UV.y); // 只在前景渐入，保留中央广场的明暗结构。
        float side_weight=pow(clamp(abs(UV.x-0.52)/0.52,0.0,1.0),1.5); // 画面两侧略深，视线留在建筑入口。
        float land_weight=1.0-clamp(environment.r+environment.g+environment.b,0.0,1.0); // 天空与水域不受前景压暗。
        lit*=1.0-foreground_shade_strength*foreground*(0.35+0.65*side_weight)*land_weight;
        // 接收光乘以原表面颜色，保留材质纹理；位置/遮挡支持范围来自配置。
        float local_field=dot(texture(local_receiver_data,UV),local_group_energy);
        lit+=base_linear*local_color*local_field*local_strength;
        float grouped=dot(texture(local_emission_data,UV),emission_group_energy);
        float other=max(control.b-texture(old_group_emission_data,UV).r,0.0);
        float emission=mix(control.b,grouped+other,emission_balance);
        lit+=window_color*window_energy*emission;
        lit+=spill_color*spill_energy*texture(spill_data,UV).r*spill_scale*legacy_spill_strength;
        // 仅少量灯源光晕，不替代墙面与地面受光；可单独归零。
        lit+=halo_color*dot(texture(source_halo_data,UV),halo_group_energy)*halo_strength;
        vec3 result=to_srgb(lit);
        float altitude=clamp(UV.y/max(sky_height_uv,0.001),0.0,1.0);
        vec3 sky=mix(sky_top,sky_horizon,smoothstep(0.0,1.0,altitude));
        sky=mix(sky,cloud_color,environment.a*0.90);
        float glow_distance=(UV.x-horizon_glow_x)/0.31; // 无硬边的地平线散射宽度。
        float horizon_glow=exp(-glow_distance*glow_distance)*smoothstep(0.12,0.96,altitude); // 云层保留自身体积。
        sky=mix(sky,horizon_glow_color,horizon_glow*horizon_glow_strength*(1.0-environment.a*0.48));
        result=mix(result,sky,environment.r*sky_mix);
        COLOR=vec4(clamp(result,0.0,1.0),original.a);
    }
}
