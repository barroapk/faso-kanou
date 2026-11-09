extends Node3D

var terrain

func _ready() -> void:
    _creer_ciel()
    _creer_soleil()
    _creer_mer()
    terrain = preload("res://scripts/terrain.gd").new()
    add_child(terrain)
    _creer_camera()
    _creer_habitants(10)
    _creer_cases(4)

func _creer_ciel() -> void:
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var mat_ciel := PanoramaSkyMaterial.new()
    mat_ciel.panorama = load("res://assets/ciel/kiara_8_sunset_4k.hdr")
    var ciel := Sky.new()
    ciel.sky_material = mat_ciel
    env.sky = ciel
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.fog_enabled = true
    env.fog_density = 0.0015
    env.fog_light_color = Color(0.95, 0.8, 0.65)
    var monde := WorldEnvironment.new()
    monde.environment = env
    add_child(monde)

func _creer_soleil() -> void:
    var soleil := DirectionalLight3D.new()
    soleil.rotation_degrees = Vector3(-25, 60, 0)
    soleil.light_color = Color(1.0, 0.85, 0.65)
    soleil.light_energy = 1.3
    soleil.shadow_enabled = true
    add_child(soleil)

func _creer_mer() -> void:
    var mer := MeshInstance3D.new()
    var plan := PlaneMesh.new()
    plan.size = Vector2(3000, 3000)
    mer.mesh = plan
    var mat_mer := StandardMaterial3D.new()
    mat_mer.albedo_color = Color(0.05, 0.3, 0.42)
    mat_mer.metallic = 0.3
    mat_mer.roughness = 0.1
    mer.material_override = mat_mer
    mer.position.y = -0.2
    add_child(mer)

func _creer_camera() -> void:
    var camera = preload("res://scripts/camera_strategie.gd").new()
    add_child(camera)

func _creer_habitants(nombre: int) -> void:
    for i in nombre:
        var habitant := MeshInstance3D.new()
        var corps := CapsuleMesh.new()
        corps.radius = 0.35
        corps.height = 1.7
        habitant.mesh = corps
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color(0.36, 0.22, 0.13)
        habitant.material_override = mat
        var angle := TAU * i / nombre
        var x := cos(angle) * 4
        var z := sin(angle) * 4
        habitant.position = Vector3(x, terrain.hauteur(x, z) + 0.85, z)
        add_child(habitant)

func _creer_cases(nombre: int) -> void:
    var ScriptCase = preload("res://scripts/case.gd")
    for i in nombre:
        var maison = ScriptCase.new()
        var angle := TAU * i / nombre + 0.4
        var x := cos(angle) * 9
        var z := sin(angle) * 9
        maison.position = Vector3(x, terrain.hauteur(x, z) - 0.1, z)
        maison.rotation.y = atan2(-x, -z)
        add_child(maison)
