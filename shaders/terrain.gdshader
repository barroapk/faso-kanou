shader_type spatial;

uniform sampler2D herbe_couleur : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D herbe_relief : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roche_couleur : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roche_relief : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 sable : source_color = vec3(0.82, 0.70, 0.48);
uniform vec3 laterite : source_color = vec3(0.62, 0.34, 0.20);

varying vec3 pos_monde;
varying vec3 normale_monde;
varying vec4 biome;

void vertex() {
    pos_monde = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    normale_monde = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    biome = COLOR;
}

void fragment() {
    vec3 herbe = texture(herbe_couleur, UV).rgb;
    float grain = dot(herbe, vec3(0.333));

    vec3 sol = herbe * vec3(1.1, 1.0, 0.8);
    sol = mix(sol, herbe * vec3(0.35, 0.65, 0.25), biome.y);
    sol = mix(sol, sable * (0.75 + 0.5 * grain), biome.x);
    sol = mix(sol, sol * vec3(0.55, 0.85, 0.40), biome.z * 0.7);
    sol *= 0.82 + 0.36 * biome.w;

    float lat = smoothstep(14.0, 30.0, pos_monde.y) * (1.0 - biome.x) * (1.0 - biome.y);
    sol = mix(sol, laterite * (0.5 + grain), lat * 0.6);

    float pente = 1.0 - normale_monde.y;
    float roche = max(smoothstep(0.12, 0.30, pente), smoothstep(75.0, 100.0, pos_monde.y));
    vec3 c = mix(sol, texture(roche_couleur, UV * 0.5).rgb, roche);

    float plage = 1.0 - smoothstep(0.0, 0.8, pos_monde.y);
    c = mix(c, sable * (0.7 + 0.6 * grain), plage);

    ALBEDO = c;
    NORMAL_MAP = mix(texture(herbe_relief, UV).rgb, texture(roche_relief, UV * 0.5).rgb, roche);
    ROUGHNESS = 1.0;
}
