extends Node3D

const NOMBRE := 100
const HAUTEUR_ARBRE := 7.0

var terrain
var rng := RandomNumberGenerator.new()

func _ready() -> void:
    rng.seed = 42
    var modele: PackedScene = load("res://assets/modeles/acacia.glb")
    var boite := _mesurer(modele)
    var echelle := HAUTEUR_ARBRE / boite.size.y
    var places := 0
    var essais := 0
    while places < NOMBRE and essais < NOMBRE * 40:
        essais += 1
        var x := rng.randf_range(-170.0, 170.0)
        var z := rng.randf_range(-170.0, 170.0)
        if Vector2(x, z).length() < 20.0:
            continue
        var h: float = terrain.hauteur(x, z)
        if h < 1.0 or h > 12.0:
            continue
        var pente := absf(terrain.hauteur(x + 1.0, z) - h) + absf(terrain.hauteur(x, z + 1.0) - h)
        if pente > 1.2:
            continue
        if rng.randf() < terrain.desert(x, z) * 0.95:
            continue
        if rng.randf() > 0.3 + terrain.foret(x, z) * 0.7:
            continue
        var arbre: Node3D = modele.instantiate()
        var taille := echelle * rng.randf_range(0.7, 1.3)
        arbre.scale = Vector3.ONE * taille
        arbre.rotation.y = rng.randf() * TAU
        arbre.position = Vector3(x, h - boite.position.y * taille - 0.1, z)
        add_child(arbre)
        places += 1

func _mesurer(modele: PackedScene) -> AABB:
    var test: Node3D = modele.instantiate()
    add_child(test)
    var boite := AABB()
    var premier := true
    for m in test.find_children("*", "MeshInstance3D", true, false):
        var mi := m as MeshInstance3D
        var b := test.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
        boite = b if premier else boite.merge(b)
        premier = false
    test.queue_free()
    return boite
