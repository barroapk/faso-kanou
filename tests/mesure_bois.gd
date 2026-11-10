extends SceneTree

# Mesure du bois (sans rien changer aux règles), 10 simulations x 100 ans,
# logement construit au besoin. Quatre flux séparés, par taille de clan et saison :
#   production (bâtisseurs), consommation humaine, entretien des bâtiments,
#   construction (bois investi dans le patrimoine).
# Plus : capacité, autonomie, jours à 0, entretiens impayés, ruines.
const TEMPS = preload("res://scripts/core/temps.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")

const TRANCHES := [[1, 14, "10-14"], [15, 24, "15-24"], [25, 49, "25-49"], [50, 9999, "50+"]]
var f := {}   # tranche|saison -> {prod, humain, entretien, construction, jours, cap, stock, zero, chantier}
var impayes := 0
var ruines := 0
var eteints := 0
var batisseurs := {}

func _initialize() -> void:
    for g in [2026, 1, 2, 3, 4, 5, 6, 7, 8, 9]:
        _simuler(g)
    print("=== Bois, en kg par jour (moyennes) ===")
    print("taille | saison | production | humains | entretien | construction | solde | stock moyen / capacité | jours à 0 | jours de chantier")
    for t in TRANCHES:
        for s in ["sèche", "pluies"]:
            var k := "%s|%s" % [t[2], s]
            if not f.has(k):
                continue
            var x: Dictionary = f[k]
            var j: float = x["jours"]
            var solde: float = (x["prod"] - x["humain"] - x["entretien"] - x["construction"]) / j
            print("%6s | %6s | %10.1f | %7.1f | %9.1f | %12.1f | %+5.1f | %5.0f / %5.0f | %4.1f %% | %4.0f %%" % [t[2], s, x["prod"] / j, x["humain"] / j, x["entretien"] / j, x["construction"] / j, solde, x["stock"] / j, x["cap"] / j, 100.0 * x["zero"] / j, 100.0 * x["chantier"] / j])
    for t in TRANCHES:
        var b: Array = batisseurs.get(t[2], [0.0, 0.0, 0])
        if b[2] > 0:
            print("%6s : %.1f bâtisseurs en moyenne pour %.0f habitants" % [t[2], b[0] / b[2], b[1] / b[2]])
    print("Entretiens impayés (bâtiment x mois) : %d, bâtiments tombés en ruine : %d, clans éteints : %d" % [impayes, ruines, eteints])
    quit()

func _tranche(n: int) -> String:
    for t in TRANCHES:
        if n >= t[0] and n <= t[1]:
            return t[2]
    return "?"

func _simuler(graine: int) -> void:
    var t = TEMPS.new()
    var pop = POPULATION.new()
    var res = RESSOURCES.new()
    var cons = CONSTRUCTION.new()
    res.construction = cons
    var b = BESOINS.new()
    pop.creer_clan_initial(0, graine)
    cons.etat_initial()
    cons.evenement.connect(func(x): if x.begins_with("En ruine"): ruines += 1)
    var construction_mois := 0.0
    var entretien_mois := 0.0
    for an in 100:
        for j in 360:
            t.jour_total += 1
            var pluie: bool = t.saison_des_pluies()
            var chantier: bool = not cons.chantiers.is_empty()
            var n: int = pop.habitants.size()
            var k := "%s|%s" % [_tranche(n), "pluies" if pluie else "sèche"]
            var x: Dictionary = f.get(k, {"prod": 0.0, "humain": 0.0, "entretien": 0.0, "construction": 0.0, "jours": 0.0, "cap": 0.0, "stock": 0.0, "zero": 0.0, "chantier": 0.0})
            var prod := 0.0
            var humain := 0.0
            var nb_bat := 0
            for h in pop.habitants:
                humain += (res.CONSO_ENFANT if pop.age(h, t.jour_total) < 14 else res.CONSO_ADULTE)["bois"]
                if h["metier"] == "bâtisseur":
                    nb_bat += 1
                    if not chantier:
                        prod += res.PRODUCTION["bâtisseur"]["bois"][1 if pluie else 0] * (0.6 + float(h["competence"]) / 100.0 * 0.8) * res.outils
            x["prod"] += prod
            x["humain"] += humain
            x["entretien"] += entretien_mois / 30.0
            x["construction"] += construction_mois / 30.0
            x["jours"] += 1.0
            x["cap"] += res.capacite("bois")
            x["stock"] += res.stocks["bois"]
            if res.stocks["bois"] <= 0.0:
                x["zero"] += 1.0
            if chantier:
                x["chantier"] += 1.0
            f[k] = x
            var bt: Array = batisseurs.get(_tranche(n), [0.0, 0.0, 0])
            bt[0] += nb_bat
            bt[1] += n
            bt[2] += 1
            batisseurs[_tranche(n)] = bt
            res.jour_passe(pop, t.jour_total, pluie, chantier)
            var w := 0.0
            for h in pop.habitants:
                if h["metier"] == "bâtisseur":
                    w += 0.6 + float(h["competence"]) / 100.0 * 0.8
            cons.jour_passe(w)
            pop.jour_passe(res.faim, res.soif)
            if t.jour_total % 30 == 0:
                var avant: float = res.stocks["bois"]
                cons.mois_passe(res)
                entretien_mois = avant - res.stocks["bois"]
                for bat in cons.batiments:
                    var ent: Dictionary = cons._niveau(bat["type"], int(bat["niveau"]))["entretien"]
                    if not cons.peut_payer(ent, res) and int(bat["etat"]) < 100:
                        pass
                pop.mois_passe(t.jour_total, res.stocks["nourriture"] > 100.0, int(cons.effet_total("logement")))
                b.mois_passe(pop, res, cons, t.jour_total, pluie, chantier)
                construction_mois = 0.0
                if cons.chantiers.is_empty():
                    for p in b.problemes:
                        if p["type"] == "logement" and p["solutions"].size() > 0:
                            var av: float = res.stocks["bois"]
                            b.appliquer(p["solutions"][0])
                            construction_mois += av - res.stocks["bois"]
                pop.repartir(t.jour_total)
                for bat in cons.batiments:
                    if int(bat["etat"]) < 100:
                        impayes += 1
        if pop.habitants.is_empty():
            eteints += 1
            return
