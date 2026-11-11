extends RefCounted

# Impôt et réserve commune (v0.3.40b).
# Principes :
#  - base imposable = valeur RÉELLE de la production enregistrée du mois (en kg de mil)
#    moins la subsistance de toute la population (ce qu'elle a réellement consommé) ;
#    enfants et inactifs ne produisent rien : ils ne rapportent rien ;
#  - impôt = taux x base, prélevé EN NATURE sur les biens produits (jamais la
#    nourriture ni l'eau, jamais le bois sous 20 jours de réserve) ;
#  - aucune monnaie n'est créée : l'or et le troc viennent du commerce seulement ;
#  - la réserve commune est HORS des stocks (jamais comptée deux fois) ; sa valeur
#    entre dans la richesse ; chantiers et entretien y puisent d'abord ;
#  - taux de 0 à 30 % ; au-dessus de 10 %, le travail rend moins.

signal evenement(texte)

const TAUX_MAX := 0.30
const SANS_MALUS := 0.10
const INTOUCHABLES := ["nourriture", "eau", "plantes_medicinales"]
const MOTIFS_PRODUCTION := ["production", "extraction"]
const MOTIFS_DEPENSE := ["construction", "entretien"]
const RESERVE_BOIS_JOURS := 20.0
const JOURNAL_MAX := 24

var taux := 0.0
var caisse := {}
var journal: Array = []        # {jour, taux, base, du, recettes, depenses}
var total_recettes := {}
var total_depenses := {}
var _recettes := {}
var _depenses := {}

func regler(t: float) -> String:
    if t < 0.0 or t > TAUX_MAX + 0.0001:
        return "Taux impossible (0 à %d %%)." % int(TAUX_MAX * 100)
    taux = t
    return ""

# 1 jusqu'à 10 % ; 0,95 à 20 % ; 0,85 à 30 %.
func facteur_productivite() -> float:
    if taux <= SANS_MALUS:
        return 1.0
    if taux <= 0.20:
        return 1.0 - 0.5 * (taux - SANS_MALUS)
    return 0.95 - 1.0 * (taux - 0.20)

func quantite(id: String) -> float:
    return float(caisse.get(id, 0.0))

func valeur(eco) -> float:
    var t := 0.0
    for id in caisse:
        t += eco.valeur(id, float(caisse[id]))
    return t

# Chantiers et entretien : prend dans la réserve jusqu'à q, renvoie ce qui a été pris.
func depenser(id: String, q: float, motif: String) -> float:
    if not MOTIFS_DEPENSE.has(motif):
        return 0.0
    var pris := minf(q, quantite(id))
    if pris <= 0.000001:
        return 0.0
    caisse[id] = quantite(id) - pris
    if quantite(id) < 0.000001:
        caisse.erase(id)
    _depenses[motif] = _depenses.get(motif, {})
    _depenses[motif][id] = float(_depenses[motif].get(id, 0.0)) + pris
    total_depenses[id] = float(total_depenses.get(id, 0.0)) + pris
    return pris

func _val(eco, id: String, q: float) -> float:
    return q * (1.0 if id == "nourriture" else float(eco.valeurs.get(id, 0.0)))

func _prelevable(res, id: String) -> bool:
    if INTOUCHABLES.has(id) or bool(res.produits.get(id, {}).get("alimentaire", false)):
        return false
    return true

# À appeler AVANT economie.mois_passe (qui remet le flux du mois à zéro).
func mois_passe(res, pop, jour: int, eco) -> void:
    var prod := {}
    for m in MOTIFS_PRODUCTION:
        for id in res.flux.get(m, {}):
            var q := float(res.flux[m][id])
            if q > 0.0:
                prod[id] = float(prod.get(id, 0.0)) + q
    var v_prod := 0.0
    for id in prod:
        v_prod += _val(eco, id, float(prod[id]))
    var v_sub := 0.0
    for id in res.flux.get("consommation", {}):
        v_sub += _val(eco, id, maxf(0.0, -float(res.flux["consommation"][id])))
    var base := maxf(0.0, v_prod - v_sub)
    var du := taux * base
    if du > 0.0:
        var v_col := 0.0
        for id in prod:
            if _prelevable(res, id):
                v_col += _val(eco, id, float(prod[id]))
        var auto: Dictionary = res.autonomie(pop, jour)
        if v_col > 0.0:
            for id in prod:
                var vu := float(eco.valeurs.get(id, 0.0))
                if not _prelevable(res, id) or vu <= 0.0:
                    continue
                var q := du * (_val(eco, id, float(prod[id])) / v_col) / vu
                q = minf(q, float(prod[id]))
                if id == "bois":
                    var jours: float = float(auto["bois"])
                    var libre := float(res.stocks["bois"]) * (1.0 - RESERVE_BOIS_JOURS / jours) if jours > RESERVE_BOIS_JOURS else 0.0
                    q = minf(q, libre)
                q = minf(q, res.quantite(id))
                if q < 0.01:
                    continue
                if res.retirer(id, q, "impot"):
                    caisse[id] = quantite(id) + q
                    _recettes[id] = float(_recettes.get(id, 0.0)) + q
                    total_recettes[id] = float(total_recettes.get(id, 0.0)) + q
    journal.append({"jour": jour, "taux": taux, "base": base, "du": du, "recettes": _recettes.duplicate(), "depenses": _depenses.duplicate(true)})
    while journal.size() > JOURNAL_MAX:
        journal.pop_front()
    _recettes = {}
    _depenses = {}

func _liste(d: Dictionary) -> String:
    var l: PackedStringArray = []
    for id in d:
        l.append("%d %s" % [int(round(float(d[id]))), id])
    return ", ".join(l) if not l.is_empty() else "rien"

func texte() -> String:
    var s := "Impôt : %d %%. Production : %d %% de la normale. Réserve commune : %s." % [int(round(taux * 100.0)), int(round(facteur_productivite() * 100.0)), _liste(caisse)]
    if not journal.is_empty():
        var d: Dictionary = journal[journal.size() - 1]
        var dep := {}
        for m in d["depenses"]:
            for id in d["depenses"][m]:
                dep[id] = float(dep.get(id, 0.0)) + float(d["depenses"][m][id])
        s += " Dernier mois : surplus imposable %d kg de mil, reçu %s, dépensé %s." % [int(round(float(d.get("base", 0.0)))), _liste(d["recettes"]), _liste(dep)]
    return s

func vers_dict() -> Dictionary:
    return {"taux": taux, "caisse": caisse, "journal": journal, "tr": total_recettes, "td": total_depenses, "r": _recettes, "d": _depenses}

func depuis_dict(d: Dictionary) -> void:
    taux = float(d.get("taux", 0.0))
    caisse = {}
    for id in d.get("caisse", {}):
        caisse[str(id)] = float(d["caisse"][id])
    journal = d.get("journal", [])
    total_recettes = d.get("tr", {})
    total_depenses = d.get("td", {})
    _recettes = d.get("r", {})
    _depenses = d.get("d", {})
