extends SceneTree

# v0.3.10 : outils et équipements.
const EQUIPEMENT = preload("res://scripts/core/equipement.gd")
const RECETTES = preload("res://scripts/core/recettes.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const TEMPS = preload("res://scripts/core/temps.gd")

var ok := 0
var rate := 0
var pop
var res
var cons
var rec
var eq
var raisons_refus := {}
var fabriques := 0

func _monde() -> void:
    pop = POPULATION.new()
    res = RESSOURCES.new()
    cons = CONSTRUCTION.new()
    res.construction = cons
    eq = EQUIPEMENT.new()
    res.equipement = eq
    rec = RECETTES.new()
    pop.creer_clan_initial(0)
    cons.etat_initial()

func _initialize() -> void:
    _monde()
    var familles := {}
    for id in eq.definitions:
        familles[eq.definitions[id]["famille"]] = true
    _verifier("%d outils, familles : %s" % [eq.definitions.size(), ", ".join(familles.keys())], ["agricole", "forestier", "construction", "minier", "artisanal"].all(func(f): return familles.has(f)))
    var sans_recette := []
    for id in eq.definitions:
        var d: Dictionary = eq.definitions[id]
        if not rec.definitions.has(d["recette"]):
            sans_recette.append(id)
        if d["reparation"] != "" and not rec.definitions.has(d["reparation"]):
            sans_recette.append(id + " (réparation)")
    _verifier("chaque outil a sa recette de fabrication et de réparation", sans_recette.is_empty())
    _verifier("départ : 1 hache de pierre, 1 arc, 1 lance, et rien d'autre (%d outils)" % eq.instances.size(), eq.instances.size() == 3 and eq.nombre("hache_pierre") == 1 and eq.nombre("houe_fer") == 0)
    # Attribution limitée par le stock
    for h in pop.habitants:
        if h["metier"] == "cueilleur" or h["metier"] == "sans métier":
            h["metier"] = "chasseur"
    eq.jour_passe(pop, false)
    var bonus := []
    for h in pop.habitants:
        if h["metier"] == "chasseur":
            bonus.append(float(h.get("bonus_outil", 1.0)))
    bonus.sort()
    bonus.reverse()
    print("   %d chasseurs, outils reçus : %s" % [bonus.size(), str(bonus)])
    _verifier("pas d'outil pour tout le monde : l'arc (x1,3) puis la lance (x1,15), les autres sans", bonus[0] == 1.3 and bonus[1] == 1.15 and bonus.slice(2).all(func(b): return b == 1.0))
    # Effet sur la production
    _monde()
    var chasseur: Dictionary = {}
    for h in pop.habitants:
        if h["metier"] == "chasseur":
            chasseur = h
    # Le gibier frais est mangé le jour même : on mesure la chasse par ses os (5 % du gibier).
    var g0: float = res.quantite("os_corne")
    res.jour_passe(pop, 0, false, false)
    var sans: float = (res.quantite("os_corne") - g0) / 0.05
    _monde()
    eq.jour_passe(pop, false)
    g0 = res.quantite("os_corne")
    res.jour_passe(pop, 0, false, false)
    var avec: float = (res.quantite("os_corne") - g0) / 0.05
    _verifier("avec l'arc, le chasseur rapporte 30 %% de gibier en plus (%.2f -> %.2f kg)" % [sans, avec], absf(avec / sans - 1.3) < 0.02)
    # Usure et casse
    _monde()
    var messages := []
    eq.evenement.connect(func(t): messages.append(t))
    for i in 150:
        eq.jour_passe(pop, false)
    _verifier("l'arc s'use : cassé après 150 jours d'utilisation, message envoyé (%s)" % " / ".join(messages), eq.nombre("arc") == 0 and messages.any(func(m): return m.contains("arc")))
    # Réparation
    _monde()
    pop.postes["bâtisseur"] = 0
    pop.repartir(0)
    for o in eq.instances:
        if o["id"] == "lance":
            o["durabilite"] = 50.0   # usée par 150 jours de chasse
    res.ajouter("pierre", 5.0)
    var bois0: float = res.stocks["bois"]
    var pierre0: float = res.quantite("pierre")
    _verifier("réparation de la lance lancée (usée)", rec.commander("reparation_lance", pop, res, cons, 60) == "")
    _verifier("matières de réparation retirées (bois -0,6)", absf(res.stocks["bois"] - (bois0 - 0.6)) < 0.0001)
    for i in 2:
        rec.jour_passe(pop, res, 61 + i)
    var lance: Dictionary = eq.instances.filter(func(o): return o["id"] == "lance")[0]
    _verifier("lance réparée : solidité %.0f / %.0f (durée de vie maximale -10 %%)" % [lance["durabilite"], lance["max"]], absf(float(lance["max"]) - 180.0) < 0.001 and float(lance["durabilite"]) == float(lance["max"]))
    _verifier("réparation impossible sans outil usé (hache neuve non utilisée ? %s)" % rec.commander("reparation_meule", pop, res, cons, 63), rec.commander("reparation_meule", pop, res, cons, 63) != "")
    # Remplacement : fabriquer une hache de pierre
    var h0: int = eq.nombre("hache_pierre")
    _verifier("fabrication d'une hache de pierre lancée", rec.commander("hache_pierre", pop, res, cons, 63) == "")
    for i in 3:
        rec.jour_passe(pop, res, 64 + i)
    _verifier("nouvelle hache dans l'inventaire du clan", eq.nombre("hache_pierre") == h0 + 1)
    # Une personne = une seule commande à la fois
    _monde()
    pop.postes["bâtisseur"] = 0
    pop.repartir(0)
    res.ajouter("argile", 20.0)
    rec.commander("canari", pop, res, cons, 0)
    rec.commander("canari", pop, res, cons, 0)
    var libres: int = pop.habitants.filter(func(h): return h["metier"] == "sans métier" and pop.age(h, 0) >= 14).size()
    var jours := 0
    var max_occupes := 0
    while rec.commandes.size() > 0 and jours < 20:
        rec.jour_passe(pop, res, jours)
        max_occupes = maxi(max_occupes, pop.habitants.filter(func(h): return h.get("occupe", false)).size())
        jours += 1
    _verifier("%d adulte libre, 2 canaris de 2 jours : %d jours (pas deux travaux à la fois)" % [libres, jours], libres == 1 and jours == 4 and max_occupes == 1)
    # Sauvegarde
    var eq2 = EQUIPEMENT.new()
    eq2.depuis_dict(JSON.parse_string(JSON.stringify(eq.vers_dict())))
    _verifier("sauvegarde : outils, solidité et priorités relus", eq2.instances == eq.instances and eq2.priorites == eq.priorites)
    var vieux = EQUIPEMENT.new()
    vieux.depuis_dict({})
    _verifier("ancienne sauvegarde : seulement l'équipement de départ", vieux.instances.size() == 3)
    # 10 simulations x 100 ans : entretien, abandon, sans outils
    for scenario in ["entretien", "abandon", "sans outils"]:
        _simulations(scenario)
    print("RÉSULTAT : %d réussis, %d ratés" % [ok, rate])
    quit()

func _simulations(scenario: String) -> void:
    var faim := 0
    var eteints := 0
    var utilises := 0
    var casses := 0
    var reparations := 0
    fabriques = 0
    raisons_refus = {}
    var bois_prod := 0.0
    var gibier := 0.0
    var refus := {}
    var jours_outil_chasse := 0
    var pop_fin := 0
    var os_total := 0.0
    for g in [2026, 1, 2, 3, 4, 5, 6, 7, 8, 9]:
        var t = TEMPS.new()
        _monde()
        pop.creer_clan_initial(0, g)
        if scenario == "sans outils":
            eq.instances = []
        var b = BESOINS.new()
        rec.evenement.connect(_compter_fabrication)
        for an in 100:
            for j in 360:
                t.jour_total += 1
                var pluie: bool = t.saison_des_pluies()
                var chantier: bool = not cons.chantiers.is_empty()
                rec.jour_passe(pop, res, t.jour_total)
                eq.jour_passe(pop, chantier)
                for h in pop.habitants:
                    if h["metier"] == "chasseur" and float(h.get("bonus_outil", 1.0)) > 1.0:
                        jours_outil_chasse += 1
                var bois_av: float = res.stocks["bois"]
                var gib_av: float = res.aliments.get("gibier", 0.0)
                res.jour_passe(pop, t.jour_total, pluie, chantier)
                gibier += maxf(0.0, res.aliments.get("gibier", 0.0) - gib_av)
                if res.faim: faim += 1
                var w := 0.0
                for h in pop.habitants:
                    if h["metier"] == "bâtisseur":
                        w += (0.6 + float(h["competence"]) / 100.0 * 0.8) * float(h.get("bonus_outil", 1.0))
                cons.jour_passe(w)
                pop.jour_passe(res.faim, res.soif, res.jours_sans_sel)
                if t.jour_total % 30 == 0:
                    cons.mois_passe(res)
                    pop.mois_passe(t.jour_total, res.stocks["nourriture"] > 100.0, int(cons.effet_total("logement")))
                    b.mois_passe(pop, res, cons, t.jour_total, pluie, chantier)
                    if cons.chantiers.is_empty():
                        for p in b.problemes:
                            if p["type"] == "logement" and p["solutions"].size() > 0:
                                b.appliquer(p["solutions"][0])
                    if scenario == "entretien":
                        _entretenir(t.jour_total)
                    pop.repartir(t.jour_total)
            if pop.habitants.is_empty():
                eteints += 1
                break
        pop_fin += pop.habitants.size()
        os_total += res.quantite("os_corne")
        utilises += eq.jours_utilises
        casses += eq.casses
        reparations += eq.reparations
    print("   %-11s : %5d jours d'outil par clan, %4d cassés, %4d réparations, %3d outils fabriqués, jours de chasse avec outil %d, faim %d j, éteints %d/10, population finale moyenne %.0f" % [scenario, utilises / 10, casses, reparations, fabriques, jours_outil_chasse / 10, faim, eteints, pop_fin / 10.0])
    if not raisons_refus.is_empty():
        print("     refus les plus fréquents : %s" % str(raisons_refus))
    if scenario == "entretien":
        _verifier("entretien : outils réparés et remplacés, jamais de faim, aucun clan éteint", reparations > 0 and fabriques > 0 and faim == 0 and eteints == 0)
    if scenario == "abandon":
        _verifier("abandon : les outils cassent et ne sont pas remplacés (%d cassés)" % casses, casses >= 30 and eteints == 0)

# Joueur simple : il ramasse la pierre s'il en manque, répare quand un outil
# est à moins de 30 %, remplace ce qui a cassé.
func _entretenir(jour: int) -> void:
    for id in eq.depart:
        if res.quantite("pierre") < 5.0:
            _cmd("ramasser_pierre", jour)
        if eq.nombre(id) < int(eq.depart[id]):
            _cmd(eq.definitions[id]["recette"], jour)
        elif eq.etat_moyen(id) < 0.3 and eq.a_reparer(id):
            _cmd(eq.definitions[id]["reparation"], jour)

func _cmd(id: String, jour: int) -> void:
    var r: String = rec.commander(id, pop, res, cons, jour)
    if r != "":
        raisons_refus[r] = int(raisons_refus.get(r, 0)) + 1

func _verifier(nom: String, condition: bool) -> void:
    if condition:
        ok += 1
    else:
        rate += 1
    print("%s %s" % ["OK  " if condition else "RATÉ", nom])

func _compter_fabrication(x: String) -> void:
    if x.begins_with("Fabrication terminée") and not x.contains("Réparer") and not x.contains("Ramasser"):
        fabriques += 1
