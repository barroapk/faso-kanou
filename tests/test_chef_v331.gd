extends SceneTree

# Validation des alertes v0.3.3.1 (5 cas demandés par l'analyste).
const CHEF = preload("res://scripts/core/chef.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const CONSEIL = preload("res://scripts/core/conseil.gd")

var ok := 0
var rate := 0

func _p(r: String, rupture: float) -> Dictionary:
    return {"ressource": r, "type": "deficit", "niveau": 2, "jours_rupture": rupture, "solutions": []}

func _n(prev: float, gest: float) -> Dictionary:
    return {"prevoyance": prev, "gestion": gest}

class FauxBesoins:
    var problemes: Array = []

func _initialize() -> void:
    var c = CHEF.new()
    c.definir_missions("nourriture", ["eau", "constructions"])
    var trois := [_p("nourriture", 6.0), _p("bois", 4.0), _p("eau", 2.0)]
    # 1
    c.analyser(trois, _n(100, 20), 0)
    _verifier("1. trois urgences, une place : la plus urgente (eau, 2 j) est suivie", c.alertes.size() == 1 and c.alertes[0]["ressource"] == "eau")
    # 2
    var c2 = CHEF.new()
    c2.definir_missions("eau", [])
    for i in 6:
        c2.analyser([_p("eau", 8.0)], _n(0, 20), i * 5)
    _verifier("2. même urgence manquée pendant 6 revues : comptée 1 fois", c2.manquees == 1)
    # 3
    c2.analyser([], _n(0, 20), 30)
    c2.analyser([_p("eau", 8.0)], _n(0, 20), 35)
    _verifier("3. l'urgence disparaît puis revient : comptée à nouveau (2)", c2.manquees == 2)
    # 4 et 5 : avec revue() et de vrais habitants
    var pop = POPULATION.new()
    pop.creer_clan_initial(0)
    var conseil = CONSEIL.new()
    conseil.etat_initial(pop, 0)
    var b := FauxBesoins.new()
    b.problemes = [_p("nourriture", 6.0), _p("bois", 4.0), _p("eau", 2.0), _p("eau", 3.0)]
    b.problemes[3]["type"] = "deficit"
    b.problemes[3]["ressource"] = "eau"
    b.problemes = [_p("nourriture", 6.0), _p("bois", 4.0), _p("eau", 2.0)]
    var chef = CHEF.new()
    chef.definir_missions("nourriture", ["eau", "constructions"])
    var msgs := []
    chef.evenement.connect(func(t): msgs.append(t))
    for i in 4:
        chef.revue(conseil, pop, b, 5 * (i + 1))
    var deb := msgs.filter(func(t): return t.contains("débordé"))
    print("   gestion du chef : %d, messages : %s" % [conseil.notes(conseil.habitant(pop, conseil.chef_id), pop, 0)["gestion"], str(msgs)])
    _verifier("4. urgences en trop sur 4 revues : un seul message débordé", deb.size() == 1)
    # 5 : sauvegarde pendant le débordement, rechargement, nouvelle revue
    var lu = CHEF.new()
    lu.depuis_dict(JSON.parse_string(JSON.stringify(chef.vers_dict())))
    var avant_m: int = chef.manquees
    _verifier("5c. compteurs relus identiques", lu.manquees == chef.manquees and lu.hors_mission == chef.hors_mission and lu._manques == chef._manques)
    var msgs2 := []
    lu.evenement.connect(func(t): msgs2.append(t))
    lu.revue(conseil, pop, b, 25)
    print("   après rechargement : %s" % str(msgs2))
    _verifier("5a. après rechargement : pas de message débordé injustifié", msgs2.filter(func(t): return t.contains("débordé")).is_empty())
    _verifier("5b. après rechargement : pas d'alerte répétée", msgs2.is_empty())
    _verifier("5d. après rechargement : la même urgence n'est pas recomptée", lu.manquees == avant_m)
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])
