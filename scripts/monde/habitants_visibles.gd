extends Node3D

const MAX_VISIBLES := 100

var terrain
var corps := {}

func _ready() -> void:
    Civilisation.population.naissance.connect(_sur_changement)
    Civilisation.population.deces.connect(_sur_changement)
    Civilisation.population.entree.connect(_sur_changement)
    Civilisation.population.sortie.connect(_sur_changement)
    _synchroniser()

func _sur_changement(_h) -> void:
    _synchroniser()

func _synchroniser() -> void:
    var pop = Civilisation.population
    var jour: int = Civilisation.temps.jour_total
    var presents := {}
    var i := 0
    for h in pop.habitants:
        if i >= MAX_VISIBLES:
            break
        var id: int = h["id"]
        presents[id] = true
        if not corps.has(id):
            corps[id] = _creer_corps(h, pop.age(h, jour) < 14)
        _placer(corps[id], i)
        i += 1
    for id in corps.keys():
        if not presents.has(id):
            corps[id].queue_free()
            corps.erase(id)

func _creer_corps(h: Dictionary, enfant: bool) -> MeshInstance3D:
    var m := MeshInstance3D.new()
    var forme := CapsuleMesh.new()
    forme.radius = 0.25 if enfant else 0.35
    forme.height = 1.1 if enfant else 1.7
    m.mesh = forme
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.42, 0.25, 0.15) if h["sexe"] == "F" else Color(0.36, 0.22, 0.13)
    m.material_override = mat
    add_child(m)
    return m

func _placer(m: MeshInstance3D, i: int) -> void:
    var r := 2.0 + 0.25 * i
    var angle := i * 2.4
    var x := cos(angle) * r
    var z := sin(angle) * r
    var forme: CapsuleMesh = m.mesh
    m.position = Vector3(x, terrain.hauteur(x, z) + forme.height / 2.0, z)
