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
    var ciel := Sky.new()
    ciel.sky_material = ProceduralSkyMaterial.new()
    env.sky = ciel
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    var monde := WorldEnvironment.new()
    monde.environment = env
    add_child(monde)

func _creer_soleil() -> void:
    var soleil := DirectionalLight3D.new()
    soleil.rotation_degrees = Vector3(-50, 30, 0)
    soleil.shadow_enabled = true
    add_child(soleil)

func _creer_ile() -> void:
    var mer := MeshInstance3D.new()
    var plan := PlaneMesh.new()
    plan.size = Vector2(400, 400)
    mer.mesh = plan
    var mat_mer := StandardMaterial3D.new()
    mat_mer.albedo_color = Color(0.1, 0.35, 0.55)
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
    ile.material_override = mat_ile
    add_child(ile)

func _creer_camera() -> void:
    var camera := Camera3D.new()
    add_child(camera)
    camera.position = Vector3(0, 12, 16)
    camera.look_at(Vector3.ZERO)

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
