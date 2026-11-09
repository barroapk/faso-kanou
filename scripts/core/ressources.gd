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
const UNITES := {"nourriture": "kg", "eau": "L", "bois": "kg"}

var stocks := {"nourriture": 300.0, "eau": 120.0, "bois": 100.0}
var bilan := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0}
var batiments := {"hutte": 4, "grenier": 0, "jarres": 0, "puits": 0, "abri_bois": 0}
var outils := 1.0
var faim := false
var soif := false

func capacite(r: String) -> float:
    match r:
        "nourriture":
            return 300.0 + 1000.0 * batiments["grenier"]
        "eau":
            return 600.0 + 200.0 * batiments["jarres"] + 2000.0 * batiments["puits"]
        "bois":
            return 500.0 + 2000.0 * batiments["abri_bois"]
    return 0.0

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
