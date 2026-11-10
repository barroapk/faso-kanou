extends SceneTree

# Partie complète de 6 ans via Civilisation, sauvegarde, relecture, comparaison.
const CIV = preload("res://scripts/core/civilisation.gd")

func _initialize() -> void:
    var a = CIV.new()
    a._nouvelle()
    a._brancher()
    for i in 6 * 360:
        a.temps._passer_un_jour()
    a.sauvegarder()
    var b = CIV.new()
    var lu: bool = b._charger(a.FICHIER)
    var ok: bool = lu and b.conseil.membres == a.conseil.membres and b.conseil.chef_id == a.conseil.chef_id and b.population.habitants.size() == a.population.habitants.size() and b.besoins.mode == a.besoins.mode and b.chef.principale == a.chef.principale and b.chef.secondaires == a.chef.secondaires
    print("habitants %d, conseil %s, chef %d" % [a.population.habitants.size(), str(a.conseil.membres), a.conseil.chef_id])
    print("RELECTURE %s" % ("OK" if ok else "RATÉE"))
    a.free()
    b.free()
    quit()
