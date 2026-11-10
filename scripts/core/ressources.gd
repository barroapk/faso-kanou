extends RefCounted

signal penurie(ressource)

const PRODUCTION := {
    "chasseur": {"nourriture": [3.0, 2.2]},
    "cueilleur": {"nourriture": [2.0, 3.5]},
    "chef": {"nourriture": [0.5, 0.5]},
    "sans métier": {"nourriture": [0.8, 1.2]},
    "porteur d'eau": {"eau": [50.0, 70.0]},
    "bâtisseur": {"bois": [12.0, 10.0]},
}
const CONSO_ADULTE := {"nourriture": 0.8, "eau": 5.0, "bois": 1.2}
const CONSO_ENFANT := {"nourriture": 0.5, "eau": 3.0, "bois": 0.6}
const BASE := {"nourriture": 300.0, "eau": 600.0, "bois": 500.0}
const UNITES := {"nourriture": "kg", "eau": "L", "bois": "kg"}
# Pertes de stockage par jour (part du stock).
const PERTES_NOURRITURE := 0.001        # sans grenier : environ 30 % par an
const PERTES_NOURRITURE_GRENIER := 0.0003
const EVAPORATION_EAU := 0.002          # jarres et canaris : 0,2 % par jour

var construction
var stocks := {"nourriture": 300.0, "eau": 120.0, "bois": 100.0}
var bilan := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0}
var outils := 1.0
var faim := false
var soif := false

func capacite(r: String) -> float:
    return BASE[r] + construction.effet_total("stock_" + r)

func taux_pertes() -> float:
    return PERTES_NOURRITURE_GRENIER if construction.effet_total("conservation") > 0.0 else PERTES_NOURRITURE

# Autonomie : nombre de jours que le clan peut tenir sur ses stocks,
# sans rien produire ni importer.
func autonomie(population, jour: int) -> Dictionary:
    var conso := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0}
    for h in population.habitants:
        var c: Dictionary = CONSO_ENFANT if population.age(h, jour) < 14 else CONSO_ADULTE
        for r in c:
            conso[r] += c[r]
    var a := {}
    for r in conso:
        a[r] = stocks[r] / conso[r] if conso[r] > 0.0 else 9999.0
    return a

func jour_passe(population, jour: int, pluie: bool, chantier_actif: bool) -> void:
    var s := 1 if pluie else 0
    var variation := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0}
    for h in population.habitants:
        var enfant: bool = population.age(h, jour) < 14
        var conso: Dictionary = CONSO_ENFANT if enfant else CONSO_ADULTE
        for r in conso:
            variation[r] -= conso[r]
        if h["metier"] == "bâtisseur" and chantier_actif:
            continue
        var p = PRODUCTION.get(h["metier"], {})
        var efficacite := (0.6 + float(h["competence"]) / 100.0 * 0.8) * outils
        for r in p:
            variation[r] += p[r][s] * efficacite
    if pluie:
        variation["eau"] += 20.0
    variation["nourriture"] -= stocks["nourriture"] * taux_pertes()
    variation["eau"] -= stocks["eau"] * EVAPORATION_EAU
    for r in variation:
        stocks[r] = clampf(stocks[r] + variation[r], 0.0, capacite(r))
    bilan = variation
    var avait_faim := faim
    var avait_soif := soif
    faim = stocks["nourriture"] <= 0.0
    soif = stocks["eau"] <= 0.0
    if faim and not avait_faim:
        penurie.emit("nourriture")
    if soif and not avait_soif:
        penurie.emit("eau")

func texte() -> String:
    var morceaux: PackedStringArray = []
    for r in ["nourriture", "eau", "bois"]:
        var etat := ""
        if stocks[r] >= capacite(r):
            etat = "plein"
        else:
            etat = "%s%.1f/j" % ["+" if bilan[r] >= 0.0 else "", bilan[r]]
        morceaux.append("%s %d/%d %s (%s)" % [r.capitalize(), int(stocks[r]), int(capacite(r)), UNITES[r], etat])
    return "   ".join(morceaux)

func vers_dict() -> Dictionary:
    return {"stocks": stocks, "outils": outils, "faim": faim, "soif": soif}

func depuis_dict(d: Dictionary) -> void:
    var st: Dictionary = d.get("stocks", {})
    for r in stocks:
        stocks[r] = float(st.get(r, stocks[r]))
    outils = float(d.get("outils", 1.0))
    faim = bool(d.get("faim", false))
    soif = bool(d.get("soif", false))
