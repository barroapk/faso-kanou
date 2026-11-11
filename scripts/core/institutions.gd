extends RefCounted

# Institutions du clan (v0.3.60) : MESURE SEULEMENT, aucun effet sur le jeu.
# Pour chaque secteur (santé, défense, finances), quatre valeurs indépendantes :
#  - CAPACITÉ (0-100) : savoir-faire accumulé. Elle ne monte que par du travail réellement fait
#    (soins donnés, raids menés ou subis, budget réellement tenu) et de moins en moins vite en
#    haut. Négligence : après 3 mois sans aucune activité (12 pour la défense, où les raids sont
#    rares), elle baisse de 0,5 point par mois.
#  - PERFORMANCE (0-100) : efficacité réelle du moment. Elle rejoint progressivement une cible
#    qui dépend de la capacité, des moyens et de la compétence du responsable : changer de
#    responsable la modifie, sans effacer la capacité.
#  - COMPÉTENCE DU RESPONSABLE : lue sur le titulaire nommé (savoir du secteur, ou gestion).
#    Sans titulaire : compétence de coutume.
#  - MOYENS (0-100) : lus sur les systèmes existants (effectifs, plantes, armes, réserve), jamais recalculés ailleurs.
# Rien de tout cela ne change la santé, la défense ou les finances : ce sont des indicateurs.

signal evenement(texte)

const SECTEURS := ["sante", "defense", "finances"]
const NOMS := {"sante": "Santé", "defense": "Défense", "finances": "Finances"}
const REF_ACTIVITE := {"sante": 20.0, "defense": 1.0, "finances": 1.0}    # activité du mois qui donne l'apprentissage maximal
const MOIS_AVANT_DECLIN := {"sante": 3, "defense": 12, "finances": 3}
const GAIN_MENSUEL := 3.0
const DECLIN_MENSUEL := 0.5
const BASE_PERF := 30.0               # une fonction sans capacité fonctionne quand même à la coutume
const COMPETENCE_COUTUME := 30.0
const RATTRAPAGE := 0.25              # part de l'écart comblée chaque mois
const HABITANTS_PAR_GUERISSEUR := 20
const PART_COMBATTANTS := 0.2         # part des adultes visée comme combattants disponibles

var etat := {}                        # secteur -> {capacite, performance, mois, inactifs}
var dernier_mois := -1

func _init() -> void:
    for s in SECTEURS:
        etat[s] = _vide()

static func _vide() -> Dictionary:
    return {"capacite": 0.0, "performance": -1.0, "mois": 0.0, "inactifs": 0}

# Travail réellement fait (appelé par les systèmes existants).
func noter(sid: String, n: float) -> void:
    if etat.has(sid) and n > 0.0:
        etat[sid]["mois"] = float(etat[sid]["mois"]) + n

# ---------- Lecture des systèmes existants ----------

func _moy(l: Array) -> float:
    var s := 0.0
    for x in l:
        s += float(x)
    return s / float(maxi(1, l.size()))

func moyens(sid: String, c, jour: int) -> float:
    match sid:
        "sante":
            var pop = c.population
            var malades: int = pop.a_soigner().size()
            var places: int = int(c.construction.effet_total("soin_places"))
            var effectif: float = minf(1.0, float(pop.nb_guerisseurs()) / float(maxi(1, int(ceil(float(pop.habitants.size()) / HABITANTS_PAR_GUERISSEUR)))))
            var plantes := 1.0
            var cap := 1.0
            if malades > 0:
                plantes = minf(1.0, float(c.ressources.quantite("plantes_medicinales")) / (float(malades) * float(pop.PLANTES_PAR_SOIN) * 10.0))
                cap = minf(1.0, float(pop.capacite_soins(places)) / float(malades))
            return 100.0 * _moy([effectif, plantes, cap])
        "defense":
            var g = c.guerre
            var dispo: int = g.combattants(c.population, c.ressources, jour).size()
            var adultes := 0
            for h in c.population.habitants:
                if c.population.age(h, jour) >= c.population.AGE_ADULTE:
                    adultes += 1
            var effectif: float = minf(1.0, float(dispo) / float(maxi(1, int(ceil(float(adultes) * PART_COMBATTANTS)))))
            var armes: int = c.equipement.nombre("lance") + c.equipement.nombre("arc")
            var arme: float = minf(1.0, float(armes) / maxf(1.0, float(dispo) / 2.0))
            var faim := 0.5 if c.ressources.faim else 1.0
            return 100.0 * _moy([effectif, arme, faim])
        "finances":
            var f = c.get("finances")
            if f == null or not f.budget_actif(c):
                return 0.0
            var e: Dictionary = f.etat(c)
            if float(e["jours"]) < 0.0:
                return 100.0
            return 100.0 * minf(1.0, float(e["jours"]) / float(f.SEUIL_STABLE))
    return 0.0

# Compétence du titulaire nommé ; sans titulaire, la coutume.
func competence(sid: String, c, jour: int) -> Dictionary:
    var g = c.gouvernement
    var id: int = g.titulaire_de(sid, "titulaire")
    if id >= 0:
        var h: Dictionary = g._habitant(c, id)
        if not h.is_empty():
            return {"valeur": float(g.criteres(h, sid, c, jour)["competence"]), "nomme": true}
    return {"valeur": COMPETENCE_COUTUME, "nomme": false}

func cible(sid: String, c, jour: int) -> float:
    var cap: float = float(etat[sid]["capacite"])
    var moy := moyens(sid, c, jour)
    var comp: float = float(competence(sid, c, jour)["valeur"])
    return (BASE_PERF + (100.0 - BASE_PERF) * cap / 100.0) * (0.5 + 0.5 * moy / 100.0) * (0.6 + 0.4 * clampf(comp, 0.0, 100.0) / 100.0)

# ---------- Évolution mensuelle ----------

func mois_passe(c, jour: int) -> void:
    if dernier_mois < 0:
        dernier_mois = jour - 30
    _compter_defense(c, jour)
    _compter_finances(c)
    dernier_mois = jour
    for sid in SECTEURS:
        var e: Dictionary = etat[sid]
        var norm := minf(1.0, float(e["mois"]) / float(REF_ACTIVITE[sid]))
        e["mois"] = 0.0
        if norm > 0.0:
            e["inactifs"] = 0
            e["capacite"] = minf(100.0, float(e["capacite"]) + GAIN_MENSUEL * norm * (1.0 - float(e["capacite"]) / 100.0))
        else:
            e["inactifs"] = int(e["inactifs"]) + 1
            if int(e["inactifs"]) >= int(MOIS_AVANT_DECLIN[sid]) and float(e["capacite"]) > 0.0:
                e["capacite"] = maxf(0.0, float(e["capacite"]) - DECLIN_MENSUEL)
                if int(e["inactifs"]) == int(MOIS_AVANT_DECLIN[sid]):
                    evenement.emit("Institutions : le secteur %s est négligé, sa capacité baisse lentement." % str(NOMS[sid]).to_lower())
        var cb := cible(sid, c, jour)
        if float(e["performance"]) < 0.0:
            e["performance"] = cb
        else:
            e["performance"] = float(e["performance"]) + (cb - float(e["performance"])) * RATTRAPAGE

# Raids menés ou subis par le joueur, terminés depuis le dernier mois (chacun compté une fois).
func _compter_defense(c, jour: int) -> void:
    var r = c.get("raids")
    if r == null:
        return
    var n := 0
    for x in r.historique:
        if (x["att"] == "joueur" or x["dst"] == "joueur") and int(x["retour"]) > dernier_mois and int(x["retour"]) <= jour:
            n += 1
    noter("defense", float(n))

# Finances : un mois où le budget public a réellement enregistré des recettes ou des dépenses.
func _compter_finances(c) -> void:
    var f = c.get("finances")
    if f == null or not f.budget_actif(c):
        return
    if f.somme(f.total("rec", 30)) + f.somme(f.total("dep", 30)) > 0.0:
        noter("finances", 1.0)

# Lignes d'affichage pour le tableau du gouvernement.
func lignes(sid: String, c, jour: int) -> Array:
    var e: Dictionary = etat.get(sid, _vide())
    var comp: Dictionary = competence(sid, c, jour)
    var perf: float = float(e["performance"]) if float(e["performance"]) >= 0.0 else cible(sid, c, jour)
    return [
        ["Capacité (savoir-faire acquis)", "%d/100" % int(round(float(e["capacite"])))],
        ["Performance actuelle", "%d/100 (cible %d)" % [int(round(perf)), int(round(cible(sid, c, jour)))]],
        ["Compétence du responsable", ("%d/100" % int(round(float(comp["valeur"])))) if bool(comp["nomme"]) else "pas de responsable (coutume : %d)" % int(COMPETENCE_COUTUME)],
        ["Moyens disponibles", "%d/100" % int(round(moyens(sid, c, jour)))],
    ]

func negligence(sid: String) -> bool:
    return etat.has(sid) and int(etat[sid]["inactifs"]) >= int(MOIS_AVANT_DECLIN[sid])

func vers_dict() -> Dictionary:
    return {"etat": etat, "dernier_mois": dernier_mois}

func depuis_dict(d: Dictionary) -> void:
    dernier_mois = int(d.get("dernier_mois", -1))
    for s in SECTEURS:
        var x: Dictionary = d.get("etat", {}).get(s, {})
        etat[s] = {"capacite": float(x.get("capacite", 0.0)), "performance": float(x.get("performance", -1.0)), "mois": float(x.get("mois", 0.0)), "inactifs": int(x.get("inactifs", 0))}
