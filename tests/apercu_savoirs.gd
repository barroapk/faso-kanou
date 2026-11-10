extends SceneTree
# Aperçu rapide : savoirs après 20 ans de partie (contrôle léger).
const CIV = preload("res://scripts/core/civilisation.gd")
func _initialize() -> void:
    var c = CIV.new()
    c._nouvelle()
    c._brancher()
    for i in 20 * 360:
        c.temps._passer_un_jour()
    for h in c.population.habitants:
        var l := []
        for s in h["savoirs"]:
            l.append("%s %.0f" % [s, h["savoirs"][s]])
        print("%s %s, %d ans, %s : %s" % [h["prenom"], h["nom"], c.population.age(h, c.temps.jour_total), h["metier"], ", ".join(l)])
    c.free()
    quit()
