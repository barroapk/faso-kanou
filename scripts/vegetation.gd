extends Node3D

const NOMBRE := 100
const HAUTEUR_ARBRE := 7.0

var terrain
var rng := RandomNumberGenerator.new()

func _ready() -> void:
    rng.seed = 42
    var modele: PackedScene = load("res://assets/modeles/acacia.glb")
    var test: Node3D = modele.instantiate()
    add_child(test)
    var inverse := test.global_transform.affine_inverse()
    var parties := []
    var boite := AABB()
    var premier := true
    for m in test.find_children("*", "MeshInstance3D", true, false):
        var mi := m as MeshInstance3D
        var t := inverse * mi.global_transform
        parties.append([mi.mesh, t])
        var b := t * mi.get_aabb()
        boite = b if premier else boite.merge(b)
        premier = false
    test.queue_free()

    var echelle := HAUTEUR_ARBRE / boite.size.y
    var places: Array[Transform3D] = []
    var essais := 0
    while places.size() < NOMBRE and essais < NOMBRE * 40:
        essais += 1
        var x := rng.randf_range(-170.0, 170.0)
        var z := rng.randf_range(-170.0, 170.0)
        if Vector2(x, z).length() < 20.0:
            continue
        var h: float = terrain.hauteur(x, z)
        if h < 1.0 or h > 12.0:
            continue
        if terrain.dans_eau(x, z): continue
        var pente := absf(terrain.hauteur(x + 1.0, z) - h) + absf(terrain.hauteur(x, z + 1.0) - h)
        if pente > 1.2:
            continue
        if rng.randf() < terrain.desert(x, z) * 0.95:
            continue
        if rng.randf() > 0.3 + terrain.foret(x, z) * 0.7:
            continue
        var taille := echelle * rng.randf_range(0.7, 1.3)
        var base := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * taille)
        var pos := Vector3(x, h - boite.position.y * taille - 0.1, z)
        places.append(Transform3D(base, pos))

    for p in parties:
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.mesh = p[0]
        mm.instance_count = places.size()
        for i in places.size():
            mm.set_instance_transform(i, places[i] * p[1])
        var mmi := MultiMeshInstance3D.new()
        mmi.multimesh = mm
        add_child(mmi)
