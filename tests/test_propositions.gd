extends SceneTree

# v0.3.3.2 : propositions du chef.
const CHEF = preload("res://scripts/core/chef.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const CONSEIL = preload("res://scripts/core/conseil.gd")

var ok := 0
var rate := 0
var pop
var res
var cons
var b
var conseil

func _monde() -> void:
    pop = POPULATION.new()
    res = RESSOURCES.new()
    cons = CONSTRUCTION.new()
    res.construction = cons
    pop.creer_clan_initial(0)
    cons.etat_initial()
    conseil = CONSEIL.new()
    conseil.etat_initial(pop, 0)
    b = BESOINS.new()
    b.mode = "conseil"

func _alerte_eau(intel: float, chef) -> Dictionary:
    b.actualiser(pop, res, cons, 5, false, false)
    var notes := {"prevoyance": 100.0, "gestion": 100.0, "intelligence": intel}
    chef.analyser(b.problemes, notes, 5)
    for a in chef.alertes:
        chef.proposer(a, b, intel)
        if a["ressource"] == "eau":
            return a
    return {}

func _initialize() -> void:
    _verifier("intelligence 20 -> 1 proposition max", CHEF.nb_propositions(20) == 1)
    _verifier("intelligence 50 -> 2", CHEF.nb_propositions(50) == 2)
    _verifier("intelligence 90 -> 3", CHEF.nb_propositions(90) == 3)

    # Pénurie d'eau grave : 0 porteur, 40 L, 1 adulte libre, 3 bâtisseurs
    # -> 2 solutions calculées (ouvrir un poste, transférer un bâtisseur).
    _monde()
    pop._ajouter("Seydou", "Ouédraogo", "H", 30, 1, "sans métier", 0)
    pop._ajouter("Noaga", "Kaboré", "H", 32, 2, "sans métier", 0)
    pop.postes = {"chasseur": 1, "cueilleur": 2, "porteur d'eau": 0, "bâtisseur": 3}
    pop.repartir(0)
    res.stocks["eau"] = 40.0
    var chef = CHEF.new()
    chef.definir_missions("eau", [])
    var a := _alerte_eau(90, chef)
    print("   solutions de besoins.gd : %d" % a["probleme"]["solutions"].size())
    for p in a["propositions"]:
        print("   - %s | coût : %s | effet : %s | risque : %s" % [p["solution"]["action"], p["cout"], p["effet"], p["risque"]])
    _verifier("chef intelligent (90) : autant de propositions que de solutions, pas plus", a["propositions"].size() == a["probleme"]["solutions"].size() and a["propositions"].size() <= 3)
    _verifier("chaque proposition a un coût, un effet et un risque", a["propositions"].all(func(p): return p["cout"] != "" and p["effet"] != "" and p["risque"] != ""))
    _verifier("ce cas a bien 2 solutions", a["probleme"]["solutions"].size() == 2)
    var chef_faible = CHEF.new()
    chef_faible.definir_missions("eau", [])
    var a2 := _alerte_eau(20, chef_faible)
    _verifier("chef peu intelligent (20) : une seule proposition", a2["propositions"].size() == 1)

    # Une seule solution existe : il n'en invente pas d'autre.
    _monde()
    res.stocks["eau"] = 600.0
    pop.postes["porteur d'eau"] = 3
    var chef3 = CHEF.new()
    chef3.definir_missions("eau", [])
    var a3 := _alerte_eau(100, chef3)
    print("   stockage : %s" % str(a3["propositions"].map(func(p): return p["solution"]["action"] + " " + p["cout"])))
    _verifier("une seule solution (construire des jarres) : une seule proposition", a3["propositions"].size() == 1 and a3["propositions"][0]["solution"]["action"] == "construire")
    _verifier("le coût affiche le bois nécessaire", a3["propositions"][0]["cout"].contains("30 kg de bois"))

    # Solution non faisable : pas proposée, la raison est donnée.
    res.stocks["bois"] = 10.0
    var a4 := _alerte_eau(100, chef3)
    print("   sans bois : propositions %d, raison : %s" % [a4["propositions"].size(), a4["sans_solution"]])
    _verifier("pas assez de bois : aucune proposition, raison expliquée", a4["propositions"].is_empty() and a4["sans_solution"].contains("matériaux"))

    # Appliquer : passe par besoins.appliquer().
    _monde()
    pop.postes["porteur d'eau"] = 0
    res.stocks["eau"] = 40.0
    var chef5 = CHEF.new()
    chef5.definir_missions("eau", [])
    var a5 := _alerte_eau(90, chef5)
    var avant: Dictionary = pop.postes.duplicate()
    _verifier("le chef seul n'a rien changé", pop.postes == avant)
    _verifier("Ignorer : rien ne change", chef5.ignorer(a5["cle"], 5) == "" and pop.postes == avant)
    var r := chef5.appliquer_proposition(a5["cle"], 0, b, 5)
    _verifier("Appliquer : poste de porteur d'eau ouvert", r == "" and int(pop.postes["porteur d'eau"]) == 1)
    _verifier("décisions notées (ignorée puis appliquée)", chef5.decisions.size() == 2 and chef5.decisions[1]["resultat"] == "appliquée")
    # Situation changée entre la proposition et la décision : refus expliqué.
    _monde()
    pop.postes["porteur d'eau"] = 0
    res.stocks["eau"] = 40.0
    chef5 = CHEF.new()
    chef5.definir_missions("eau", [])
    var a6 := _alerte_eau(90, chef5)
    var idx := -1
    for i in a6["propositions"].size():
        if a6["propositions"][i]["solution"]["action"] == "ouvrir":
            idx = i
    if idx >= 0:
        pop.postes["chasseur"] = int(pop.postes["chasseur"]) + 5
        var avant2: Dictionary = pop.postes.duplicate()
        var r2 := chef5.appliquer_proposition(a6["cle"], idx, b, 10)
        print("   refus : %s" % r2)
        _verifier("plus d'adulte libre au moment de décider : refus, rien ne change", r2 != "" and pop.postes == avant2)
    else:
        _verifier("seconde alerte avec proposition 'ouvrir'", false)
    print("   décisions : %s" % str(chef5.decisions))
    var lu = CHEF.new()
    lu.depuis_dict(JSON.parse_string(JSON.stringify(chef5.vers_dict())))
    _verifier("historique des décisions sauvegardé", lu.decisions == chef5.decisions and lu.decisions.size() == 1)
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])
