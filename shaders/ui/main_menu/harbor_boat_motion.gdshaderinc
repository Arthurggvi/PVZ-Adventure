// 船与海面接触亮纹共享同一逆变换，旗帜在船的局部坐标中形变。
uniform sampler2D boat_premult : filter_linear, repeat_disable;
uniform bool boat_enabled = true;
uniform float phase = 0.0;
uniform vec2 pivot = vec2(1568.0,403.0);
uniform float heave_px = 2.4;
uniform float sway_px = 0.35;
uniform float roll_radians = 0.002793;
uniform float phase_offset = 0.0;

// 接触亮边按同一相位平移垂直阈值。
float boat_heave_px() {
    return boat_enabled ? heave_px * sin(phase*6.28318530718+phase_offset) : 0.0;
}

vec2 harbor_boat_uv(vec2 uv) {
    float angle=phase*6.28318530718+phase_offset;
    vec2 point=uv*canvas_pixels;
    vec2 displacement=boat_enabled?vec2(sway_px*sin(angle*2.0),boat_heave_px()):vec2(0.0);
    float turn=boat_enabled?roll_radians*sin(angle):0.0;
    float cosine=cos(turn),sine=sin(turn);
    mat2 inverse_rotation=mat2(vec2(cosine,-sine),vec2(sine,cosine));
    return (inverse_rotation*(point-pivot-displacement)+pivot)/canvas_pixels;
}
