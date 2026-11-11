extends RefCounted

# Satisfaction et stabilité (v0.3.63) : MESURE SEULEMENT.
#  - Quatre indicateurs calculés sur les faits des 30 derniers jours (fenêtre glissante) :
#      nourriture : part du besoin alimentaire réellement couverte chaque jour (personnes-jours nourries) ;
#      eau        : part du besoin en eau réellement distribuée (stock vide = manque) ;
#      santé      : soins donnés / malades à soigner, les jours où il y avait des malades ;
#      salaires   : jours sans arriérés, un arriéré pesant d'autant plus qu'il représente de jours de salaires.
#    Un indicateur sans objet (aucun malade, aucun salaire public) est « indisponible », jamais pénalisé.
#  - Stabilité : elle bouge lentement, chaque mois, vers la situation des indicateurs (la pire
#    compte pour moitié). Elle baisse au plus de 4 points par mois et remonte au plus de 3.
#  - v0.3.66 : eau = 4e indicateur (part du besoin en eau réellement distribuée). Seul effet pratique
#    de la stabilité : production des métiers -0 à -10 % (voir facteur_productivite). Pas de bonus,
#    pas de migration, pas de contestation.

signal evenement(texte)

const FENETRE := 30
const MIN_JOURS := 5
const CLES := ["nourriture", "eau", "sante", "salaires"]
const NOMS := {"nourriture": "Nourriture", "eau": "Eau", "sante": "Santé", "salaires": "Salaires"}
const PENALITE_MAX := 0.10    # effet maximal de la stabilité sur le travail (à stabilité 0)
const BAISSE_MAX := 4.0
const HAUSSE_MAX := 3.0
const SEUIL_STABLE := 75.0
const SEUIL_FRAGILE := 50.0
const JOURS_ARRIERES_NULS := 10.0

var jours := {"nourriture": [], "eau": [], "sante": [], "salaires": []}
var stabilite := 100.0
var statut := "stable"

func _pousser(cle: String, v: float) -> void:
    var l: Array = jours[cle]
    l.append(v)
    while l.size() > FENETRE:
        l.pop_front()

# Chaque jour, après les soins. valeur = -1 : indicateur sans objet ce jour-là.
func jour(c, besoin_soins: float, soins: float) -> void:
    _pousser("nourriture", clampf(float(c.ressources.couverture_nourriture), 0.0, 1.0))
    _pousser("eau", clampf(float(c.ressources.couverture_eau), 0.0, 1.0))
    _pousser("sante", clampf(soins / besoin_soins, 0.0, 1.0) if besoin_soins > 0.0 else -1.0)
    var f = c.finances
    var sj: float = f.salaires_jour(c)
    if f.budget_actif(c) and (sj > 0.0001 or float(f.arrieres) > 0.0001):
        var j_dus: float = float(f.arrieres) / maxf(sj, 0.0001)
        _pousser("salaires", 1.0 - clampf(j_dus / JOURS_ARRIERES_NULS, 0.0, 1.0))
    else:
        _pousser("salaires", -1.0)

# 0 à 100, ou -1 s'il n'y a pas assez de jours concernés pour juger.
func valeur(cle: String) -> float:
    if not jours.has(cle):
        return -1.0
    var s := 0.0
    var n := 0
    for v in jours[cle]:
        if float(v) >= 0.0:
            s += float(v)
            n += 1
    if n < MIN_JOURS:
        return -1.0
    return 100.0 * s / float(n)

func _statut_de(s: float) -> String:
    if s >= SEUIL_STABLE:
        return "stable"
    return "fragile" if s >= SEUIL_FRAGILE else "instable"

func cible() -> float:
    var tot := 0.0
    var n := 0
    var pire := 100.0
    for k in CLES:
        var v := valeur(k)
        if v >= 0.0:
            tot += v
            n += 1
            pire = minf(pire, v)
    if n == 0:
        return -1.0    # aucune donnée : la stabilité ne bouge pas
    return 0.5 * tot / float(n) + 0.5 * pire

func plus_faible() -> String:
    var cle := ""
    var pire := 101.0
    for k in CLES:
        var v := valeur(k)
        if v >= 0.0 and v < pire:
            pire = v
            cle = k
    return cle

# Seul effet pratique de la stabilité : le travail des métiers. Aucun effet au-dessus de 75 %,
# pénalité progressive en dessous, au plus -10 % à 0 %. Jamais de bonus. Appliqué une seule fois
# (dans ressources.gd), sans toucher à l'impôt ni aux outils.
func facteur_productivite() -> float:
    if stabilite >= SEUIL_STABLE:
        return 1.0
    return 1.0 - PENALITE_MAX * (SEUIL_STABLE - stabilite) / SEUIL_STABLE

func mois_passe(_c, _jour: int) -> void:
    var cb := cible()
    if cb >= 0.0:
        stabilite += clampf(cb - stabilite, -BAISSE_MAX, HAUSSE_MAX)
    stabilite = clampf(stabilite, 0.0, 100.0)
    var nouveau := _statut_de(stabilite)
    if nouveau != statut:
        var ancien := statut
        statut = nouveau
        if nouveau == "stable":
            evenement.emit("Stabilité : le clan se rétablit (%d %%)." % int(round(stabilite)))
        elif ancien == "stable" or nouveau == "instable":
            var cause: String = plus_faible()
            evenement.emit("Stabilité : le clan devient %s (%d %%)%s." % [nouveau, int(round(stabilite)), (", surtout à cause de : " + NOMS[cause].to_lower()) if cause != "" else ""])

func etat() -> Dictionary:
    var v := {}
    for k in CLES:
        v[k] = valeur(k)
    return {"valeurs": v, "stabilite": stabilite, "statut": statut, "faible": plus_faible(), "facteur": facteur_productivite()}

func texte_valeur(k: String) -> String:
    var v := valeur(k)
    if v >= 0.0:
        return "%s %d %%" % [NOMS[k], int(round(v))]
    var raison := "pas assez de jours mesurés"
    if k == "sante":
        raison = "aucun malade récemment"
    elif k == "salaires":
        raison = "aucun salaire public"
    return "%s indisponible (%s)" % [NOMS[k], raison]

func vers_dict() -> Dictionary:
    return {"jours": jours, "stabilite": stabilite, "statut": statut}

func depuis_dict(d: Dictionary) -> void:
    jours = {"nourriture": [], "eau": [], "sante": [], "salaires": []}
    for k in CLES:
        for v in d.get("jours", {}).get(k, []):
            jours[k].append(float(v))
    stabilite = float(d.get("stabilite", 100.0))
    statut = str(d.get("statut", "stable"))
