extends Node3D

var terrain
var vegetation
var soleil: DirectionalLight3D
var env: Environment
var materiau_sol: Material
var materiau_simple := StandardMaterial3D.new()
var etiquette_fps: Label
var echelles := [0.5, 0.7, 1.0]
var index_echelle := 1

func _ready() -> void:
    get_viewport().scaling_3d_scale = 0.7
    RenderingServer.directional_shadow_atlas_set_size(2048, true)
    _creer_ciel()
    _creer_soleil()
    _creer_mer()
    terrain = preload("res://scripts/terrain.gd").new()
    add_child(terrain)
    materiau_sol = terrain.material_override
    materiau_simple.albedo_color = Color(0.55, 0.5, 0.3)
    _creer_camera()
    var habitants_visibles = preload("res://scripts/monde/habitants_visibles.gd").new(); habitants_visibles.terrain = terrain; add_child(habitants_visibles)
    _creer_cases(4)
    _creer_vegetation()
    _creer_interface()
    add_child(preload("res://scripts/interface/bandeau.gd").new())

func _creer_ciel() -> void:
    env = Environment.new()
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
    env.fog_density = 0.0004
    env.fog_light_color = Color(0.95, 0.8, 0.65)
    var monde := WorldEnvironment.new()
    monde.environment = env
    add_child(monde)

func _creer_soleil() -> void:
    soleil = DirectionalLight3D.new()
    soleil.rotation_degrees = Vector3(-25, 60, 0)
    soleil.light_color = Color(1.0, 0.85, 0.65)
    soleil.light_energy = 1.3
    soleil.shadow_enabled = true
    soleil.directional_shadow_max_distance = 60.0
    soleil.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
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

func _creer_vegetation() -> void:
    vegetation = preload("res://scripts/vegetation.gd").new()
    vegetation.terrain = terrain
    add_child(vegetation)

func _creer_interface() -> void:
    var couche := CanvasLayer.new()
    add_child(couche)
    etiquette_fps = Label.new()
    etiquette_fps.position = Vector2(20, 20)
    etiquette_fps.add_theme_font_size_override("font_size", 36)
    couche.add_child(etiquette_fps)
    var boutons := VBoxContainer.new()
    boutons.position = Vector2(20, 80)
    couche.add_child(boutons)
    _ajouter_bouton(boutons, "Arbres", func(actif): vegetation.visible = actif)
    _ajouter_bouton(boutons, "Ombres", func(actif): soleil.shadow_enabled = actif)
    _ajouter_bouton(boutons, "Ciel HDR", _changer_ciel)
    _ajouter_bouton(boutons, "Sol réaliste", func(actif): terrain.material_override = materiau_sol if actif else materiau_simple)
    _ajouter_vitesse_test(boutons)
    _ajouter_bouton(boutons, "Nouvelle partie", func(_actif): Civilisation.nouvelle_partie())
    var res := Button.new()
    res.text = "Résolution 70%"
    res.add_theme_font_size_override("font_size", 32)
    res.pressed.connect(_changer_resolution.bind(res))
    boutons.add_child(res)

func _ajouter_bouton(parent: Control, texte: String, action: Callable) -> void:
    var b := Button.new()
    b.text = texte
    b.toggle_mode = true
    b.button_pressed = true
    b.add_theme_font_size_override("font_size", 32)
    b.toggled.connect(action)
    parent.add_child(b)

func _changer_ciel(actif: bool) -> void:
    if actif:
        env.background_mode = Environment.BG_SKY
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    else:
        env.background_mode = Environment.BG_COLOR
        env.background_color = Color(0.55, 0.7, 0.9)
        env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        env.ambient_light_color = Color(0.6, 0.6, 0.65)
        env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED

func _changer_resolution(bouton: Button) -> void:
    index_echelle = (index_echelle + 1) % echelles.size()
    get_viewport().scaling_3d_scale = echelles[index_echelle]
    bouton.text = "Résolution %d%%" % int(echelles[index_echelle] * 100)

func _process(_delta: float) -> void:
    etiquette_fps.text = "FPS : %d" % Engine.get_frames_per_second()

var bouton_vitesse: Button

func _ajouter_vitesse_test(parent: Control) -> void:
    bouton_vitesse = Button.new()
    bouton_vitesse.text = "Test : x1"
    bouton_vitesse.add_theme_font_size_override("font_size", 32)
    bouton_vitesse.pressed.connect(_vitesse_suivante)
    parent.add_child(bouton_vitesse)

func _vitesse_suivante() -> void:
    var paliers := [1, 3, 4, 5]
    var textes := ["x0", "x1", "x3", "x8", "x30", "x100"]
    var i := paliers.find(Civilisation.temps.vitesse)
    Civilisation.temps.vitesse = paliers[(i + 1) % paliers.size()]
    bouton_vitesse.text = "Test : " + textes[Civilisation.temps.vitesse]
