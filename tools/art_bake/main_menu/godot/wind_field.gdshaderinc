// 两个材质共用的确定性风场；不读TIME，不随帧率改变节奏。
uniform bool wind_enabled = false;
uniform float wind_angle = 0.0;
uniform float wind_strength = 1.0;
uniform vec2 wind_direction = vec2(1.0,0.18);
uniform float gust_depth = 0.20;
uniform float gust_cycles = 1.0;
float wind_signal(float cycles,float delay,float space) {
    float gust=1.0-gust_depth*0.5+gust_depth*0.5*cos(wind_angle*gust_cycles);
    float wave=sin(wind_angle*cycles-delay-space);
    wave+=0.22*sin(wind_angle*(cycles+2.0)-delay*1.7-space*0.65);
    return wave*gust*wind_strength/1.22;
}
