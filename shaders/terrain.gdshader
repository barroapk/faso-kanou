shader_type spatial;

uniform sampler2D herbe_couleur : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D herbe_relief : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roche_couleur : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D roche_relief : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 sable : source_color = vec3(0.80, 0.70, 0.50);
uniform vec3 laterite : source_color = vec3(0.62, 0.34, 0.20);

varying vec3 pos_monde;
varying vec3 normale_monde;

void vertex() {
    pos_monde = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    normale_monde = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    float pente = 1.0 - normale_monde.y;
    float roche = max(smoothstep(0.12, 0.30, pente), smoothstep(9.0, 12.0, pos_monde.y));

    vec3 herbe = texture(herbe_couleur, UV).rgb;
    vec3 pierre = texture(roche_couleur, UV * 0.5).rgb;
    vec3 c = mix(herbe, pierre, roche);

    float grain = dot(herbe, vec3(0.333));
    float lat = smoothstep(3.0, 6.0, pos_monde.y) * (1.0 - roche);
    c = mix(c, laterite * (0.5 + grain), lat * 0.6);

    float plage = 1.0 - smoothstep(0.1, 0.8, pos_monde.y);
    c = mix(c, sable * (0.7 + 0.6 * grain), plage);

    ALBEDO = c;
    NORMAL_MAP = mix(texture(herbe_relief, UV).rgb, texture(roche_relief, UV * 0.5).rgb, roche);
    ROUGHNESS = 1.0;
}
