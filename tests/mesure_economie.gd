extends SceneTree

# Mesure de l'économie actuelle (sans rien changer aux règles).
# Simulation 100 ans, logement construit au besoin, postes gérés par besoins.gd (auto).
# Pour chaque jour : production réelle et consommation réelle par ressource.
# Marge = (production - consommation) / consommation, par taille de clan et par saison.
# Mesure aussi la part des adultes qu'il faudrait pour une marge de 20 %.
const TEMPS = preload("res://scripts/core/temps.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")

const TRANCHES := [[1, 14, "10-14"], [15, 24, "15-24"], [25, 49, "25-49"], [50, 9999, "50+"]]
const R := ["nourriture", "eau", "bois"]

var cumul := {}     # tranche|saison|ressource -> [prod, conso, jours]
var besoin := {}    # tranche|saison -> [part d'adultes nécessaire, jours]
var faim := 0
var soif := 0
var autonomie := {}   # tranche|ressource -> [somme jours, mesures, minimum]
var transition := {}  # ressource -> minimum d'autonomie dans les 60 premiers jours de saison sèche

func _initialize() -> void:
    for g in [2026, 1, 2, 3, 4, 5, 6, 7, 8, 9]:
        _simuler(g)
    print("=== Marge réelle = (production - consommation) / consommation ===")
    print("taille | saison | nourriture | eau | bois | adultes nécessaires pour 20 %% partout")
    for t in TRANCHES:
        for s in ["sèche", "pluies"]:
            var ligne := "%6s | %6s" % [t[2], s]
            var vide := true
            for r in R:
                var c: Array = cumul.get("%s|%s|%s" % [t[2], s, r], [0.0, 0.0, 0])
                if c[2] > 0:
                    vide = false
                    ligne += " | %+6.0f %%" % (100.0 * (c[0] - c[1]) / c[1])
                else:
                    ligne += " |    -   "
            var bz: Array = besoin.get("%s|%s" % [t[2], s], [0.0, 0])
            if not vide:
                ligne += " | %3.0f %% des adultes" % (100.0 * bz[0] / maxi(1, bz[1]))
                print(ligne)
    print("=== Autonomie (jours tenables sur les stocks) : moyenne / minimum ===")
    for t in TRANCHES:
        var l := "%6s" % t[2]
        for r in R:
            var a: Array = autonomie.get("%s|%s" % [t[2], r], [0.0, 0, 99999.0])
            if a[1] > 0:
                l += " | %s %4.0f j / %3.0f j" % [r, a[0] / a[1], a[2]]
        print(l)
    print("Début de saison sèche (60 premiers jours), autonomie minimale : nourriture %.0f j, eau %.0f j" % [transition.get("nourriture", -1.0), transition.get("eau", -1.0)])
    print("Jours de faim : %d, jours de soif : %d (10 simulations x 100 ans)" % [faim, soif])
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
    for an in 100:
        for j in 360:
            t.jour_total += 1
            var pluie: bool = t.saison_des_pluies()
            var chantier: bool = not cons.chantiers.is_empty()
            _mesurer(pop, res, t.jour_total, pluie, chantier)
            res.jour_passe(pop, t.jour_total, pluie, chantier)
            if res.faim: faim += 1
            if res.soif: soif += 1
            var w := 0.0
            for h in pop.habitants:
                if h["metier"] == "bâtisseur":
                    w += 0.6 + float(h["competence"]) / 100.0 * 0.8
            cons.jour_passe(w)
            pop.jour_passe(res.faim, res.soif)
            if t.jour_total % 30 == 0:
                var au: Dictionary = res.autonomie(pop, t.jour_total)
                var tr := _tranche(pop.habitants.size())
                for r in R:
                    var a: Array = autonomie.get("%s|%s" % [tr, r], [0.0, 0, 99999.0])
                    a[0] += minf(au[r], 9999.0)
                    a[1] += 1
                    a[2] = minf(a[2], au[r])
                    autonomie["%s|%s" % [tr, r]] = a
                var m: int = t.mois()
                if (m == 10 or m == 11) and an > 0:
                    for r in ["nourriture", "eau"]:
                        transition[r] = minf(transition.get(r, 99999.0), au[r])
                cons.mois_passe(res)
                pop.mois_passe(t.jour_total, res.stocks["nourriture"] > 100.0, int(cons.effet_total("logement")))
                b.mois_passe(pop, res, cons, t.jour_total, pluie, chantier)
                if cons.chantiers.is_empty():
                    for p in b.problemes:
                        if p["type"] == "logement" and p["solutions"].size() > 0:
                            b.appliquer(p["solutions"][0])
                pop.repartir(t.jour_total)
        if pop.habitants.is_empty():
            return

func _mesurer(pop, res, jour: int, pluie: bool, chantier: bool) -> void:
    var n: int = pop.habitants.size()
    if n == 0:
        return
    var s := 1 if pluie else 0
    var tr := _tranche(n)
    var sa := "pluies" if pluie else "sèche"
    var prod := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0}
    var conso := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0}
    var adultes := 0
    var comp := 0.0
    for h in pop.habitants:
        var enfant: bool = pop.age(h, jour) < 14
        var c: Dictionary = res.CONSO_ENFANT if enfant else res.CONSO_ADULTE
        for r in c:
            conso[r] += c[r]
        if not enfant and h["metier"] != "chef" and h["metier"] != "ancien":
            adultes += 1
            comp += float(h["competence"])
        if h["metier"] == "bâtisseur" and chantier:
            continue
        var p: Dictionary = res.PRODUCTION.get(h["metier"], {})
        var eff: float = (0.6 + float(h["competence"]) / 100.0 * 0.8) * res.outils
        for r in p:
            prod[r] += p[r][s] * eff
    if pluie:
        prod["eau"] += 20.0
    for r in R:
        var k := "%s|%s|%s" % [tr, sa, r]
        var c: Array = cumul.get(k, [0.0, 0.0, 0])
        c[0] += prod[r]
        c[1] += conso[r]
        c[2] += 1
        cumul[k] = c
    # Travailleurs nécessaires pour 20 % de marge, avec la compétence moyenne du clan.
    if adultes > 0:
        var eff_moy := 0.6 + comp / adultes / 100.0 * 0.8
        var meilleur_nourriture: float = maxf(res.PRODUCTION["chasseur"]["nourriture"][s], res.PRODUCTION["cueilleur"]["nourriture"][s]) * eff_moy
        var w: float = conso["nourriture"] * 1.2 / meilleur_nourriture
        w += conso["eau"] * 1.2 / (res.PRODUCTION["porteur d'eau"]["eau"][s] * eff_moy)
        w += conso["bois"] * 1.2 / (res.PRODUCTION["bâtisseur"]["bois"][s] * eff_moy)
        var k2 := "%s|%s" % [tr, sa]
        var bz: Array = besoin.get(k2, [0.0, 0])
        bz[0] += w / adultes
        bz[1] += 1
        besoin[k2] = bz
