extends SceneTree
# Contrôle léger : 5 ans de partie, comptabilité équilibrée, indicateurs, un troc.
const CIV = preload("res://scripts/core/civilisation.gd")
const ECONOMIE = preload("res://scripts/core/economie.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
func _initialize() -> void:
    var c = CIV.new()
    c._nouvelle()
    c._brancher()
    c.population.postes["bâtisseur"] = 0
    c.population.repartir(0)
    c.ressources.ajouter("argile", 20.0)
    for an in 5:
        if an == 1:
            print("canari : ", c.commander_recette("canari"))
        for j in 360:
            c.temps._passer_un_jour()
    var dernier: Dictionary = c.economie.journal[-1]
    print("Mois avec écart comptable : %d sur %d" % [c.economie.anomalies, 60])
    print("Dernier mois, écarts : ", dernier["ecarts"])
    for motif in dernier["flux"]:
        var l := []
        for r in dernier["flux"][motif]:
            l.append("%s %+.1f" % [r, dernier["flux"][motif][r]])
        print("  %-12s %s" % [motif, ", ".join(l)])
    var i: Dictionary = dernier["indicateurs"]
    print("Trésorerie %.0f | stocks %.0f | patrimoine %.0f | richesse %.0f | autonomie nourriture %.0f j, eau %.0f j | capacité %.1f/j" % [i["tresorerie"], i["stocks"], i["patrimoine"], i["richesse"], i["autonomie_nourriture"], i["autonomie_eau"], i["capacite_productive"]])
    # Troc entre deux clans : 10 kg de pulpe de baobab contre 4 kg d'os.
    var r2 = RESSOURCES.new()
    r2.construction = c.construction
    r2.ajouter("os_corne", 5.0)
    var e2 = ECONOMIE.new()
    var avant_a: float = c.ressources.quantite("os_corne")
    var res := ECONOMIE.echanger(c.economie, c.ressources, e2, r2, {"baobab_pulpe": 10.0}, {"os_corne": 4.0}, c.temps.jour_total, "T1")
    print("Troc : '%s' ; os du clan : %.1f -> %.1f ; transactions : %d et %d" % [res, avant_a, c.ressources.quantite("os_corne"), c.economie.transactions.size(), e2.transactions.size()])
    print("Troc impossible : ", ECONOMIE.echanger(c.economie, c.ressources, e2, r2, {"miel": 9999.0}, {}, 0, "T2"))
    c.free()
    quit()
