extends RefCounted

# Pression des difficultés (v0.3.17 E1).
# Le savoir naît des besoins : chaque mois, on mesure les vrais problèmes du
# clan (faim, soif, grain perdu, bois qui manque, outils usés, pertes en mer).
# La pression monte avec la souffrance et redescend lentement quand le problème
# est réglé (le clan garde la mémoire de ses crises).
# Un clan sans difficulté invente peu ; un clan en crise cherche des solutions.
# Mêmes règles pour le joueur et pour l'ordinateur.

signal evenement(texte)

const DOMAINES := ["nourriture", "eau", "conservation", "bois", "outils", "navigation"]
const NOMS := {"nourriture": "la nourriture", "eau": "l'eau", "conservation": "la conservation du grain",
    "bois": "le bois", "outils": "les outils", "navigation": "la navigation"}
const OUBLI_MOIS := 0.9        # la pression baisse de 10 % par mois sans nouveau problème
const MAX := 100.0
const SEUIL_ALERTE := 30.0
# Découverte -> domaine dont la pression la rend plus probable.
const DOMAINE_DECOUVERTE := {"agriculture": "nourriture", "elevage": "nourriture", "irrigation": "eau",
    "irrigation_amenagee": "eau", "charbonnage": "bois", "metallurgie": "outils", "acier": "outils", "tissage": ""}

var niveaux := {}              # domaine -> 0 à 100
var _alerte := {}              # domaine -> déjà annoncé

func _init() -> void:
    for d in DOMAINES:
        niveaux[d] = 0.0

func noter(domaine: String, points: float) -> void:
    niveaux[domaine] = clampf(float(niveaux.get(domaine, 0.0)) + points, 0.0, MAX)

# Chaque jour : faim et soif vécues.
func jour_passe(res) -> void:
    if res.faim:
        noter("nourriture", 1.0)
    if res.soif:
        noter("eau", 1.5)

# Chaque mois, AVANT la comptabilité (qui remet le journal à zéro).
func mois_passe(pop, res, equipement, jour: int) -> void:
    for d in DOMAINES:
        niveaux[d] = float(niveaux[d]) * OUBLI_MOIS
    var a: Dictionary = res.autonomie(pop, jour)
    if float(a.get("nourriture", 999.0)) < 15.0:
        noter("nourriture", 3.0)
    if float(a.get("eau", 999.0)) < 7.0:
        noter("eau", 3.0)
    if float(a.get("bois", 999.0)) < 10.0:
        noter("bois", 3.0)
    # Grain perdu (pourri ou sans place) : part de ce que le clan mange en un mois.
    var perdu := 0.0
    for motif in ["perte", "trop_plein"]:
        perdu -= float(res.flux.get(motif, {}).get("nourriture", 0.0))
    var conso_mois: float = maxf(1.0, res._conso_jour(pop, jour, "nourriture") * 30.0)
    noter("conservation", 20.0 * perdu / conso_mois)
    # Outils presque cassés.
    if equipement != null:
        var uses := 0
        for o in equipement.instances:
            if float(o["durabilite"]) < 0.15 * float(o["max"]):
                uses += 1
        noter("outils", 3.0 * uses)
    for d in DOMAINES:
        if float(niveaux[d]) >= SEUIL_ALERTE and not _alerte.get(d, false):
            _alerte[d] = true
            evenement.emit("Les difficultés avec %s poussent le clan à chercher des solutions." % NOMS[d])
        elif float(niveaux[d]) < SEUIL_ALERTE * 0.5:
            _alerte[d] = false

# Multiplie la chance d'une découverte : 0,3 sans difficulté, 1,3 vers 20,
# jusqu'à 4 en pleine crise.
func facteur(decouverte: String) -> float:
    var d: String = DOMAINE_DECOUVERTE.get(decouverte, "")
    if d == "":
        return 1.0
    return clampf(0.3 + float(niveaux.get(d, 0.0)) / 20.0, 0.3, 4.0)

func vers_dict() -> Dictionary:
    return {"niveaux": niveaux, "alerte": _alerte}

func depuis_dict(d: Dictionary) -> void:
    for k in d.get("niveaux", {}):
        niveaux[str(k)] = float(d["niveaux"][k])
    _alerte = d.get("alerte", {})
