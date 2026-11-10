extends SceneTree

# Chemin complet du jeu : Civilisation -> chef -> besoins.appliquer().
const CIV = preload("res://scripts/core/civilisation.gd")

func _initialize() -> void:
    var c = CIV.new()
    c._nouvelle()
    c._brancher()
    c.besoins.mode = "conseil"
    c.chef.definir_missions("eau", [])
    c.population.postes["porteur d'eau"] = 0
    c.population.repartir(0)
    c.ressources.stocks["eau"] = 60.0
    for i in 5:
        c.temps._passer_un_jour()
    var a: Dictionary = c.chef.alertes[0] if c.chef.alertes.size() > 0 else {}
    print("alerte : %s, propositions : %d" % [a.get("cle", "aucune"), a.get("propositions", []).size()])
    var r: String = c.appliquer_proposition(a["cle"], 0)
    var porteurs: int = c.population.nombre("porteur d'eau")
    print("appliquer : '%s', porteurs d'eau au travail : %d" % [r, porteurs])
    print("CIV %s" % ("OK" if r == "" and porteurs == 1 else "RATÉ"))
    c.free()
    quit()
