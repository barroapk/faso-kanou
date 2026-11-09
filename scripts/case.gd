extends Node3D

func _ready() -> void:
    _creer_mur()
    _creer_toit()
    _creer_porte()

func _texture(a: Color, b: Color, frequence: float, relief: bool) -> NoiseTexture2D:
    var bruit := FastNoiseLite.new()
    bruit.frequency = frequence
    bruit.fractal_octaves = 4
    var tex := NoiseTexture2D.new()
    tex.width = 512
    tex.height = 512
    tex.seamless = true
    tex.noise = bruit
    if relief:
        tex.as_normal_map = true
        tex.bump_strength = 3.0
    else:
        var degrade := Gradient.new()
        degrade.set_color(0, a)
        degrade.set_color(1, b)
        tex.color_ramp = degrade
    return tex

func _creer_mur() -> void:
    var mur := MeshInstance3D.new()
    var forme := CylinderMesh.new()
    forme.top_radius = 1.5
    forme.bottom_radius = 1.6
    forme.height = 1.8
    mur.mesh = forme
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = _texture(Color(0.50, 0.32, 0.20), Color(0.72, 0.52, 0.34), 0.03, false)
    mat.normal_enabled = true
    mat.normal_texture = _texture(Color.BLACK, Color.WHITE, 0.03, true)
    mat.roughness = 1.0
    mat.uv1_scale = Vector3(3, 1, 1)
    mur.material_override = mat
    mur.position.y = 0.9
    add_child(mur)

func _creer_toit() -> void:
    var toit := MeshInstance3D.new()
    var forme := CylinderMesh.new()
    forme.top_radius = 0.0
    forme.bottom_radius = 2.1
    forme.height = 1.9
    toit.mesh = forme
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = _texture(Color(0.40, 0.31, 0.18), Color(0.80, 0.68, 0.44), 0.05, false)
    mat.normal_enabled = true
    mat.normal_texture = _texture(Color.BLACK, Color.WHITE, 0.05, true)
    mat.roughness = 1.0
    mat.uv1_scale = Vector3(16, 1, 1)
    toit.material_override = mat
    toit.position.y = 2.6
    add_child(toit)

    var pointe := MeshInstance3D.new()
    var baton := CylinderMesh.new()
    baton.top_radius = 0.04
    baton.bottom_radius = 0.06
    baton.height = 0.6
    pointe.mesh = baton
    var mat_bois := StandardMaterial3D.new()
    mat_bois.albedo_color = Color(0.30, 0.20, 0.12)
    pointe.material_override = mat_bois
    pointe.position.y = 3.7
    add_child(pointe)

func _creer_porte() -> void:
    var porte := MeshInstance3D.new()
    var forme := BoxMesh.new()
    forme.size = Vector3(0.7, 1.1, 0.2)
    porte.mesh = forme
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.08, 0.06, 0.05)
    porte.material_override = mat
    porte.position = Vector3(0, 0.55, 1.52)
    add_child(porte)
