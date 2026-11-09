extends RefCounted

signal penurie(ressource)

const PRODUCTION := {
    "chasseur": {"nourriture": [4.0, 3.0]},
    "cueilleuse": {"nourriture": [1.8, 3.0]},
    "chef": {"nourriture": [0.5, 0.5]},
    "sans métier": {"nourriture": [1.0, 1.5]},
    "porteuse d'eau": {"eau": [12.0, 15.0]},
    "bâtisseur": {"bois": [3.0, 3.0]},
}

var stocks := {"nourriture": 300.0, "eau": 100.0, "bois": 50.0}
var bilan := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0}
var faim := false
var soif := false

func jour_passe(population, jour: int, pluie: bool) -> void:
    var s := 1 if pluie else 0
    var variation := {"nourriture": 0.0, "eau": 0.0, "bois": 0.0}
    for h in population.habitants:
        var p = PRODUCTION.get(h["metier"], {})
        for r in p:
            variation[r] += p[r][s]
        var enfant: bool = population.age(h, jour) < 14
        variation["nourriture"] -= 0.6 if enfant else 1.0
        variation["eau"] -= 0.6 if enfant else 1.0
        variation["bois"] -= 0.2
    if pluie:
        variation["eau"] += 4.0
    for r in variation:
        stocks[r] += variation[r]
    bilan = variation
    var avait_faim := faim
    var avait_soif := soif
    faim = stocks["nourriture"] <= 0.0
    soif = stocks["eau"] <= 0.0
    for r in stocks:
        stocks[r] = maxf(stocks[r], 0.0)
    stocks["eau"] = minf(stocks["eau"], 300.0)
    if faim and not avait_faim:
        penurie.emit("nourriture")
    if soif and not avait_soif:
        penurie.emit("eau")

func texte() -> String:
    var morceaux: PackedStringArray = []
    for r in ["nourriture", "eau", "bois"]:
        var signe := "+" if bilan[r] >= 0.0 else ""
        morceaux.append("%s %d (%s%.1f/j)" % [r.capitalize(), int(stocks[r]), signe, bilan[r]])
    return "   ".join(morceaux)

func vers_dict() -> Dictionary:
    return {"stocks": stocks, "faim": faim, "soif": soif}

func depuis_dict(d: Dictionary) -> void:
    var st: Dictionary = d.get("stocks", {})
    for r in stocks:
        stocks[r] = float(st.get(r, stocks[r]))
    faim = bool(d.get("faim", false))
    soif = bool(d.get("soif", false))
