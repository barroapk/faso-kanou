extends SceneTree

# Vérifie chef.gd (v0.3.3.1) : missions, vision, nombre de suivis, messages.
const CHEF = preload("res://scripts/core/chef.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const CONSEIL = preload("res://scripts/core/conseil.gd")

var ok := 0
var rate := 0
var messages: Array = []

func _p(r: String, type: String, rupture: float, niveau := 1) -> Dictionary:
    return {"ressource": r, "type": type, "niveau": niveau, "jours_rupture": rupture, "solutions": []}

func _notes(prev: float, gest: float) -> Dictionary:
    return {"prevoyance": prev, "gestion": gest, "intelligence": 50.0, "influence": 50.0, "loyaute": 50.0, "experience": 50.0}

func _initialize() -> void:
    _verifier("vision : prévoyance 0 -> 5 jours", CHEF.horizon(0) == 5.0)
    _verifier("vision : prévoyance 100 -> 45 jours", CHEF.horizon(100) == 45.0)
    _verifier("suivis : gestion 20 -> 1", CHEF.suivis_max(20) == 1)
    _verifier("suivis : gestion 50 -> 2", CHEF.suivis_max(50) == 2)
    _verifier("suivis : gestion 90 -> 3", CHEF.suivis_max(90) == 3)

    var c = CHEF.new()
    _verifier("refus : mission inconnue", c.definir_missions("armée", []) != "")
    _verifier("refus : 3 missions secondaires", c.definir_missions("eau", ["nourriture", "travail", "constructions"]) != "")
    _verifier("refus : mission en double", c.definir_missions("eau", ["eau"]) != "")
    _verifier("missions eau + nourriture acceptées", c.definir_missions("eau", ["nourriture"]) == "")

    c.analyser([_p("eau", "deficit", 10.0)], _notes(50, 50), 0)
    _verifier("pénurie d'eau dans 10 j vue par un chef prévoyant (vision 25 j)", c.alertes.size() == 1)
    c.analyser([_p("eau", "deficit", 10.0)], _notes(5, 50), 0)
    _verifier("la même pénurie n'est pas vue par un chef imprévoyant (vision 7 j)", c.alertes.size() == 0)
    c.analyser([_p("eau", "deficit", 3.0)], _notes(5, 50), 0)
    _verifier("mais il la voit quand elle est à 3 jours", c.alertes.size() == 1)
    c.analyser([_p("bois", "deficit", 2.0)], _notes(100, 100), 0)
    _verifier("bois hors de ses missions : aucune alerte", c.alertes.size() == 0)
    c.analyser([_p("nourriture", "deficit", 18.0)], _notes(50, 50), 0)
    _verifier("mission secondaire : vision réduite (25 x 0,75 = 18,75 j)", c.alertes.size() == 1)
    c.analyser([_p("nourriture", "deficit", 20.0)], _notes(50, 50), 0)
    _verifier("mission secondaire : 20 j hors de vue", c.alertes.size() == 0)

    c.definir_missions("eau", ["nourriture", "constructions"])
    var trois := [_p("bois", "deficit", 2.0), _p("nourriture", "deficit", 4.0), _p("eau", "deficit", 9.0)]
    c.analyser(trois, _notes(100, 20), 0)
    _verifier("gestion faible : un seul problème suivi", c.alertes.size() == 1)
    _verifier("entre urgences, la plus proche passe en premier (bois, 2 j)", c.alertes[0]["ressource"] == "bois")
    c.analyser(trois, _notes(100, 90), 0)
    _verifier("gestion forte : trois problèmes suivis", c.alertes.size() == 3)
    _verifier("puis nourriture (4 j), puis eau (9 j)", c.alertes[1]["ressource"] == "nourriture" and c.alertes[2]["ressource"] == "eau")
    c.analyser([_p("nourriture", "deficit", 20.0), _p("eau", "deficit", 25.0)], _notes(100, 20), 0)
    _verifier("sans urgence, la mission principale passe en premier", c.alertes[0]["ressource"] == "eau")

    # Avec les vrais modules : messages sans répétition et sauvegarde.
    var pop = POPULATION.new()
    var res = RESSOURCES.new()
    var cons = CONSTRUCTION.new()
    res.construction = cons
    pop.creer_clan_initial(0)
    cons.etat_initial()
    var conseil = CONSEIL.new()
    conseil.etat_initial(pop, 0)
    var b = BESOINS.new()
    b.mode = "conseil"
    var chef = CHEF.new()
    chef.definir_missions("eau", [])
    chef.evenement.connect(func(t): messages.append(t))
    pop.postes["porteur d'eau"] = 0
    res.stocks["eau"] = 400.0
    var postes_avant: Dictionary = pop.postes.duplicate()
    for mois in 3:
        b.mois_passe(pop, res, cons, 30 * (mois + 1), false, false)
        chef.revue(conseil, pop, b, 30 * (mois + 1))
    print("  messages : %s" % str(messages))
    _verifier("un seul message pour le même problème sur 3 mois", messages.size() == 1)
    _verifier("le chef n'a changé aucun poste", pop.postes == postes_avant)
    var copie = CHEF.new()
    copie.depuis_dict(JSON.parse_string(JSON.stringify(chef.vers_dict())))
    _verifier("sauvegarde relue identique", copie.principale == chef.principale and copie.secondaires == chef.secondaires and copie._deja_signale == chef._deja_signale)
    conseil.chef_id = -1
    chef.revue(conseil, pop, b, 120)
    _verifier("pas de chef : aucune alerte", chef.alertes.is_empty())
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])
