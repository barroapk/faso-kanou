extends RefCounted

signal penurie(ressource)

const PRODUCTION := {
    "chasseur": {"nourriture": [3.0, 2.2]},
    "cueilleuse": {"nourriture": [2.0, 3.5]},
    "chef": {"nourriture": [0.5, 0.5]},
    "sans métier": {"nourriture": [0.8, 1.2]},
    "porteuse d'eau": {"eau": [50.0, 70.0]},
    "bâtisseur": {"bois": [12.0, 10.0]},
}
const CONSO_ADULTE := {"nourriture": 0.8, "eau": 5.0, "bois": 1.2}
const CONSO_ENFANT := {"nourriture": 0.5, "eau": 3.0, "bois": 0.6}
const UNITES := {"nourriture": "kg", "eau": "L", "bois": "kg"}

var stocks := {"nourriture": 400.0, "eau": 120.0, "bois": 100.0}
var bilan := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0}
var batiments := {"hutte": 4, "grenier": 0, "puits": 0}
var outils := 1.0
var faim := false
var soif := false

func capacite_eau() -> float:
    return 600.0 + 2000.0 * batiments["puits"]

func taux_pertes() -> float:
    return 0.0003 if batiments["grenier"] > 0 else 0.002

func jour_passe(population, jour: int, pluie: bool) -> void:
    var s := 1 if pluie else 0
    var variation := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0}
    for h in population.habitants:
        var p = PRODUCTION.get(h["metier"], {})
        var efficacite := (0.6 + float(h["competence"]) / 100.0 * 0.8) * outils
        for r in p:
            var q: float = p[r][s] * efficacite
            if r == "eau" and batiments["puits"] > 0:
                q *= 1.5
            variation[r] += q
        var enfant: bool = population.age(h, jour) < 14
        var conso: Dictionary = CONSO_ENFANT if enfant else CONSO_ADULTE
        for r in conso:
            variation[r] -= conso[r]
    if pluie:
        variation["eau"] += 20.0
    variation["nourriture"] -= stocks["nourriture"] * taux_pertes()
    for r in variation:
        stocks[r] += variation[r]
    bilan = variation
    var avait_faim := faim
    var avait_soif := soif
    faim = stocks["nourriture"] <= 0.0
    soif = stocks["eau"] <= 0.0
    for r in stocks:
        stocks[r] = maxf(stocks[r], 0.0)
    stocks["eau"] = minf(stocks["eau"], capacite_eau())
    if faim and not avait_faim:
        penurie.emit("nourriture")
    if soif and not avait_soif:
        penurie.emit("eau")

func texte() -> String:
    var morceaux: PackedStringArray = []
    for r in ["nourriture", "eau", "bois"]:
        var signe := "+" if bilan[r] >= 0.0 else ""
        morceaux.append("%s %d %s (%s%.1f/j)" % [r.capitalize(), int(stocks[r]), UNITES[r], signe, bilan[r]])
    return "   ".join(morceaux)

func vers_dict() -> Dictionary:
    return {"stocks": stocks, "batiments": batiments, "outils": outils, "faim": faim, "soif": soif}

func depuis_dict(d: Dictionary) -> void:
    var st: Dictionary = d.get("stocks", {})
    for r in stocks:
        stocks[r] = float(st.get(r, stocks[r]))
    var bt: Dictionary = d.get("batiments", {})
    for b in batiments:
        batiments[b] = int(bt.get(b, batiments[b]))
    outils = float(d.get("outils", 1.0))
    faim = bool(d.get("faim", false))
    soif = bool(d.get("soif", false))
