extends SceneTree

# Plusieurs problèmes urgents dépassent la capacité du chef.
const CHEF = preload("res://scripts/core/chef.gd")

var ok := 0
var rate := 0

func _p(r: String, type: String, rupture: float) -> Dictionary:
    return {"ressource": r, "type": type, "niveau": 2, "jours_rupture": rupture, "solutions": []}

func _notes(prev: float, gest: float) -> Dictionary:
    return {"prevoyance": prev, "gestion": gest}

func _initialize() -> void:
    var c = CHEF.new()
    c.definir_missions("nourriture", ["eau", "constructions"])
    # Cas A : 3 urgences, 1 seule place.
    var urgences := [_p("eau", "deficit", 2.0), _p("bois", "deficit", 4.0), _p("nourriture", "deficit", 6.0)]
    c.analyser(urgences, _notes(100, 20), 0)
    print("A : alertes %s, manquées %d" % [str(c.alertes.map(func(a): return a["ressource"])), c.manquees])
    _verifier("A : une seule alerte (capacité 1)", c.alertes.size() == 1)
    _verifier("A : 2 urgences manquées comptées", c.manquees == 2)
    # Cas B : la mission principale n'a qu'un petit souci (marge),
    # une mission secondaire a une pénurie dans 2 jours.
    var c2 = CHEF.new()
    c2.definir_missions("nourriture", ["eau"])
    c2.analyser([_p("nourriture", "marge", -1.0), _p("eau", "deficit", 2.0)], _notes(100, 20), 0)
    print("B : alerte retenue : %s" % str(c2.alertes.map(func(a): return a["ressource"] + " " + a["type"])))
    _verifier("B : l'urgence passe avant un petit souci de la mission principale", c2.alertes.size() == 1 and c2.alertes[0]["type"] == "deficit")
    # Cas C : même urgence revue 6 fois (30 jours) -> comptée une seule fois.
    var c3 = CHEF.new()
    c3.definir_missions("nourriture", ["eau", "constructions"])
    for i in 6:
        c3.analyser(urgences, _notes(100, 20), i * 5)
    _verifier("C : chaque urgence manquée comptée une seule fois", c3.manquees == 2)
    # Cas E : urgence à 8 jours invisible pour un chef imprévoyant (vision 7 j) :
    # comptée manquée, mais il ne se dit pas débordé (il ne la voit pas).
    var c4 = CHEF.new()
    c4.definir_missions("eau", [])
    c4.analyser([_p("eau", "deficit", 8.0)], _notes(5, 20), 0)
    _verifier("E : urgence non vue -> manquée 1, débordé 0", c4.manquees == 1 and c4.debordes == 0)
    # Cas D : avec les vrais modules, message "débordé" une seule fois.
    var pop = load("res://scripts/core/population.gd").new()
    var res = load("res://scripts/core/ressources.gd").new()
    var cons = load("res://scripts/core/construction.gd").new()
    res.construction = cons
    pop.creer_clan_initial(0)
    cons.etat_initial()
    var conseil = load("res://scripts/core/conseil.gd").new()
    conseil.etat_initial(pop, 0)
    for h in pop.habitants:
        if int(h["id"]) == conseil.chef_id:
            h["vivacite"] = 35
            h["caractere"] = "impulsif"
    var b = load("res://scripts/core/besoins.gd").new()
    b.mode = "conseil"
    var chef = CHEF.new()
    chef.definir_missions("eau", ["nourriture", "constructions"])
    var msgs := []
    chef.evenement.connect(func(t): msgs.append(t))
    pop.postes = {"chasseur": 0, "cueilleur": 0, "porteur d'eau": 0, "bâtisseur": 5}
    res.stocks["eau"] = 40.0
    res.stocks["nourriture"] = 20.0
    res.stocks["bois"] = 5.0
    for i in 4:
        b.actualiser(pop, res, cons, 5 * (i + 1), false, true)
        chef.revue(conseil, pop, b, 5 * (i + 1))
    print("D : gestion du chef %d, messages %s" % [conseil.notes(conseil.habitant(pop, conseil.chef_id), pop, 20)["gestion"], str(msgs)])
    var nb := 0
    for t in msgs:
        if t.contains("débordé"):
            nb += 1
    _verifier("D : le chef dit une seule fois qu'il est débordé", nb == 1)
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])
