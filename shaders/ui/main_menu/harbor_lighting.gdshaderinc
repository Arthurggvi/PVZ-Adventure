// 海面补图、船和码头从同一张实时受光纹理取光。
uniform sampler2D master_color : filter_linear, repeat_disable;
// 复用悬停蒙版的绿通道内缘；强度由牌匾与焦点状态同步提供。
uniform sampler2D entry_guide_mask : filter_linear, repeat_disable;
uniform float entry_guide_strength = 0.0;
uniform vec2 canvas_pixels = vec2(1672.0,941.0);
vec3 light_transfer(vec3 lighting,vec2 uv) {
    return lighting/max(texture(master_color,uv).rgb,vec3(0.015));
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
vec4 relit_part(vec4 part,vec3 lighting,vec2 light_uv) {
    return vec4(part.rgb*light_transfer(lighting,light_uv),part.a);
}
// 局部绘制四边形的 UV 换回全景坐标，三层使用同一套母图与蒙版。
vec2 harbor_scene_uv(vec2 local_uv, vec4 region_uv) {
    return region_uv.xy + local_uv * region_uv.zw;
}
