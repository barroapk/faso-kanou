extends Node3D

const ScriptCase = preload("res://scripts/case.gd")

var terrain
var noeuds := {}
var chantier: Node3D
var type_chantier := ""

func _ready() -> void:
    Civilisation.construction.evenement.connect(_sur_evenement)
    _synchroniser()

func _sur_evenement(_texte: String) -> void:
    _synchroniser()

func _position(i: int) -> Vector3:
    var anneau := i / 8
    var r := 9.0 + 5.0 * anneau
    var angle := TAU * float(i % 8) / 8.0 + 0.4 + anneau * 0.39
    var x := cos(angle) * r
    var z := sin(angle) * r
    return Vector3(x, terrain.hauteur(x, z) - 0.1, z)

func _synchroniser() -> void:
    var cons = Civilisation.construction
    for i in cons.batiments.size():
        var b: Dictionary = cons.batiments[i]
        if not noeuds.has(i):
            noeuds[i] = _creer(b["type"], i)
        var n: Node3D = noeuds[i]
        var taille := 1.0 + 0.15 * (int(b["niveau"]) - 1)
        var hauteur := taille if int(b["etat"]) > 0 else 0.35
        n.scale = Vector3(taille, hauteur, taille)
    if chantier:
        chantier.queue_free()
        chantier = null

func _creer(type: String, i: int) -> Node3D:
    var n: Node3D
    match type:
        "hutte":
            n = ScriptCase.new()
        "grenier":
            n = _grenier()
        "jarres":
            n = _jarres()
        _:
            n = _abri()
    add_child(n)
    n.position = _position(i)
    n.rotation.y = atan2(-n.position.x, -n.position.z)
    return n

func _process(_delta: float) -> void:
    var cons = Civilisation.construction
    if cons.chantiers.is_empty() or int(cons.chantiers[0]["index"]) >= 0:
        if chantier:
            chantier.queue_free()
            chantier = null
        return
    var c: Dictionary = cons.chantiers[0]
    if chantier == null or type_chantier != c["type"]:
        if chantier:
            chantier.queue_free()
        chantier = _creer(c["type"], cons.batiments.size())
        type_chantier = c["type"]
    var total := float(cons.definitions[c["type"]]["niveaux"][int(c["niveau"]) - 1]["travail"])
    var progres := clampf(1.0 - float(c["reste"]) / total, 0.05, 1.0)
    chantier.scale = Vector3(1.0, progres, 1.0)

func _mesh(forme: Mesh, couleur: Color, pos: Vector3) -> MeshInstance3D:
    var m := MeshInstance3D.new()
    m.mesh = forme
    var mat := StandardMaterial3D.new()
    mat.albedo_color = couleur
    mat.roughness = 1.0
    m.material_override = mat
    m.position = pos
    return m

func _grenier() -> Node3D:
    var n := Node3D.new()
    var bois := Color(0.35, 0.24, 0.14)
    for p in [Vector3(-0.6, 0.4, -0.6), Vector3(0.6, 0.4, -0.6), Vector3(-0.6, 0.4, 0.6), Vector3(0.6, 0.4, 0.6)]:
        var pied := CylinderMesh.new()
        pied.top_radius = 0.08
        pied.bottom_radius = 0.08
        pied.height = 0.8
        n.add_child(_mesh(pied, bois, p))
    var corps := CylinderMesh.new()
    corps.top_radius = 0.9
    corps.bottom_radius = 1.0
    corps.height = 1.4
    n.add_child(_mesh(corps, Color(0.6, 0.42, 0.26), Vector3(0, 1.5, 0)))
    var toit := CylinderMesh.new()
    toit.top_radius = 0.0
    toit.bottom_radius = 1.3
    toit.height = 1.2
    n.add_child(_mesh(toit, Color(0.72, 0.62, 0.4), Vector3(0, 2.8, 0)))
    return n

func _jarres() -> Node3D:
    var n := Node3D.new()
    for p in [Vector3(-0.45, 0.35, 0), Vector3(0.45, 0.35, 0), Vector3(0, 0.35, 0.5)]:
        var boule := SphereMesh.new()
        boule.radius = 0.35
        boule.height = 0.7
        n.add_child(_mesh(boule, Color(0.55, 0.3, 0.18), p))
    return n

func _abri() -> Node3D:
    var n := Node3D.new()
    var bois := Color(0.35, 0.24, 0.14)
    for p in [Vector3(-1.1, 0.8, -0.7), Vector3(1.1, 0.8, -0.7), Vector3(-1.1, 0.8, 0.7), Vector3(1.1, 0.8, 0.7)]:
        var poteau := CylinderMesh.new()
        poteau.top_radius = 0.07
        poteau.bottom_radius = 0.07
        poteau.height = 1.6
        n.add_child(_mesh(poteau, bois, p))
    var toit := BoxMesh.new()
    toit.size = Vector3(2.6, 0.15, 1.8)
    n.add_child(_mesh(toit, Color(0.72, 0.62, 0.4), Vector3(0, 1.65, 0)))
    for k in 5:
        var buche := CylinderMesh.new()
        buche.top_radius = 0.12
        buche.bottom_radius = 0.12
        buche.height = 1.9
        var m := _mesh(buche, Color(0.45, 0.3, 0.17), Vector3(0, 0.12 + 0.22 * (k % 3), -0.3 + 0.25 * k))
        m.rotation_degrees = Vector3(0, 0, 90)
        n.add_child(m)
    return n
