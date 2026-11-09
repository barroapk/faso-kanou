extends Node3D

func _ready() -> void:
    _creer_ciel()
    _creer_soleil()
    _creer_ile()
    _creer_camera()
    _creer_habitants(10)

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

func _creer_ile() -> void:
    var mer := MeshInstance3D.new()
    var plan := PlaneMesh.new()
    plan.size = Vector2(400, 400)
    mer.mesh = plan
    var mat_mer := StandardMaterial3D.new()
    mat_mer.albedo_color = Color(0.05, 0.25, 0.4)
    mat_mer.metallic = 0.3
    mat_mer.roughness = 0.1
    mer.material_override = mat_mer
    mer.position.y = -0.2
    add_child(mer)

    var ile := MeshInstance3D.new()
    var forme := CylinderMesh.new()
    forme.top_radius = 40
    forme.bottom_radius = 45
    forme.height = 1.0
    ile.mesh = forme
    var mat_ile := StandardMaterial3D.new()
    mat_ile.albedo_color = Color(0.76, 0.6, 0.35)
    mat_ile.roughness = 1.0
    ile.material_override = mat_ile
    add_child(ile)

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
        habitant.position = Vector3(cos(angle) * 4, 1.35, sin(angle) * 4)
        add_child(habitant)
