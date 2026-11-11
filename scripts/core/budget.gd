extends RefCounted

# Budget du clan (v0.3.40) : une caisse commune alimentée par un impôt réglable.
# Règles :
#  - l'impôt ne crée rien : il TRANSFÈRE une part de la production du mois
#    (bois, pierre, argile) du stock vers la caisse ;
#  - la caisse est HORS des stocks : un kilo n'est jamais compté deux fois ;
#    elle ne sert ni à manger, ni à commercer, seulement aux travaux ;
#  - le bois n'est jamais prélevé sous 20 jours de réserve ;
#  - dépenses réelles : chantiers et entretien puisent d'abord dans la caisse.

signal evenement(texte)

const TAXABLES := ["bois", "pierre", "argile"]
const MOTIFS_PRODUCTION := ["production", "extraction"]
const MOTIFS_DEPENSE := ["construction", "entretien"]
const TAUX_MAX := 0.30
const RESERVE_BOIS_JOURS := 20.0
const JOURNAL_MAX := 24

var taux := 0.0
var caisse := {}
var journal: Array = []        # un résumé par mois : {jour, taux, recettes, depenses, caisse}
var total_recettes := {}
var total_depenses := {}
var _recettes := {}
var _depenses := {}

func regler(t: float) -> String:
    if t < 0.0 or t > TAUX_MAX + 0.0001:
        return "Taux impossible (0 à %d %%)." % int(TAUX_MAX * 100)
    taux = t
    return ""

func quantite(id: String) -> float:
    return float(caisse.get(id, 0.0))

func valeur(eco) -> float:
    var t := 0.0
    for id in caisse:
        t += eco.valeur(id, float(caisse[id]))
    return t

# Chantiers et entretien : prend dans la caisse jusqu'à q, renvoie ce qui a été pris.
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

# À appeler AVANT economie.mois_passe (qui remet le flux du mois à zéro).
func mois_passe(res, pop, jour: int) -> void:
    if taux > 0.0:
        var auto: Dictionary = res.autonomie(pop, jour)
        for id in TAXABLES:
            var prod := 0.0
            for m in MOTIFS_PRODUCTION:
                prod += float(res.flux.get(m, {}).get(id, 0.0))
            var q := prod * taux
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
    journal.append({"jour": jour, "taux": taux, "recettes": _recettes.duplicate(), "depenses": _depenses.duplicate(true), "caisse": caisse.duplicate()})
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
    var s := "Impôt : %d %% de la production de bois, pierre et argile. Caisse : %s." % [int(round(taux * 100.0)), _liste(caisse)]
    if not journal.is_empty():
        var d: Dictionary = journal[journal.size() - 1]
        var dep := {}
        for m in d["depenses"]:
            for id in d["depenses"][m]:
                dep[id] = float(dep.get(id, 0.0)) + float(d["depenses"][m][id])
        s += " Dernier mois : reçu %s, dépensé %s." % [_liste(d["recettes"]), _liste(dep)]
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
