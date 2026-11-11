extends RefCounted

# Journal du travail (v0.3.67) : MESURE SEULEMENT, aucune règle de jeu.
#  - Par activité et par mois : personnes-jours, travail effectif, production réelle,
#    et ce qui n'a pas été produit quand une capacité est réellement définie :
#      perte_stab : production perdue à cause du facteur de stabilité (métiers, mines, fabrication) ;
#      ecart      : récolte sous le potentiel du champ (travail ou eau, non séparables).
#    Rien n'est inventé : une activité sans capacité définie n'affiche pas de « non réalisé ».
#  - Présence : pour chaque adulte, jours travaillés sur les 30 derniers jours (emploi régulier).

const FENETRE := 30
const MIN_JOURS := 5
const SEUIL_REGULIER := 0.5

var mois := {}
var presence := {}

func _fiche(a: String) -> Dictionary:
    if not mois.has(a):
        mois[a] = {"jp": 0.0, "travail": 0.0, "perte_travail": 0.0, "prod": {}, "perte_stab": {}, "ecart": {}}
    return mois[a]

func _ajouter(d: Dictionary, k: String, q: float) -> void:
    if absf(q) > 0.000001:
        d[k] = float(d.get(k, 0.0)) + q

func noter_travail(a: String, personnes: float, travail: float, perte := 0.0) -> void:
    var f := _fiche(a)
    f["jp"] = float(f["jp"]) + personnes
    f["travail"] = float(f["travail"]) + travail
    f["perte_travail"] = float(f["perte_travail"]) + maxf(0.0, perte)

func noter_prod(a: String, r: String, q: float, perte_stab := 0.0, ecart := 0.0) -> void:
    var f := _fiche(a)
    _ajouter(f["prod"], r, q)
    _ajouter(f["perte_stab"], r, maxf(0.0, perte_stab))
    _ajouter(f["ecart"], r, maxf(0.0, ecart))

# Après toute la production du jour : qui a réellement travaillé.
func fin_de_jour(pop, ids: Dictionary, jour: int) -> void:
    var vus := {}
    for h in pop.habitants:
        if pop.age(h, jour) < pop.AGE_ADULTE:
            continue
        var cle := str(int(h["id"]))
        vus[cle] = true
        var l: Array = presence.get(cle, [])
        l.append(1 if ids.has(int(h["id"])) else 0)
        while l.size() > FENETRE:
            l.pop_front()
        presence[cle] = l
    for cle in presence.keys():
        if not vus.has(cle):
            presence.erase(cle)

# Emploi régulier : adultes en âge de travailler ayant travaillé au moins la moitié des jours mesurés.
func emploi(pop, jour: int) -> Dictionary:
    var aptes := 0
    var evalues := 0
    var reguliers := 0
    for h in pop.habitants:
        var a: int = pop.age(h, jour)
        if a < pop.AGE_ADULTE or a >= pop.AGE_TRAVAIL_MAX:
            continue
        aptes += 1
        var l: Array = presence.get(str(int(h["id"])), [])
        if l.size() < MIN_JOURS:
            continue
        evalues += 1
        var s := 0.0
        for v in l:
            s += float(v)
        if s / float(l.size()) >= SEUIL_REGULIER:
            reguliers += 1
    return {"aptes": aptes, "evalues": evalues, "reguliers": reguliers}

func etat(pop, jour: int) -> Dictionary:
    return {"activites": mois.duplicate(true), "emploi": emploi(pop, jour)}

func nouveau_mois() -> void:
    mois = {}

func _liste(d: Dictionary) -> String:
    var p: PackedStringArray = []
    for k in d:
        p.append("%s %d" % [str(k), int(round(float(d[k])))])
    return ", ".join(p)

func texte(d: Dictionary) -> String:
    var acts: Dictionary = d.get("activites", {})
    var s := "Travail du mois"
    if acts.is_empty():
        s += " : aucune donnée pour l'instant."
    else:
        s += " (personnes-jours, travail effectif, production réelle) :"
        for a in acts:
            var f: Dictionary = acts[a]
            var t := "\n- %s : %d personnes-jours, travail effectif %d" % [str(a), int(round(float(f["jp"]))), int(round(float(f["travail"])))]
            if not f["prod"].is_empty():
                t += ", produit : " + _liste(f["prod"])
            if not f["perte_stab"].is_empty():
                t += ". Perdu à cause de la stabilité : " + _liste(f["perte_stab"])
            elif float(f["perte_travail"]) > 0.5:
                t += ". Travail perdu à cause de la stabilité : %d" % int(round(float(f["perte_travail"])))
            if not f["ecart"].is_empty():
                t += ". Sous le potentiel des champs (travail ou eau, part de la stabilité non isolable) : " + _liste(f["ecart"])
            s += t
    var e: Dictionary = d.get("emploi", {})
    if not e.is_empty():
        if int(e["evalues"]) > 0:
            s += "\nEmploi régulier (au moins la moitié des 30 derniers jours) : %d sur %d adultes en âge de travailler mesurés (%d au total)." % [int(e["reguliers"]), int(e["evalues"]), int(e["aptes"])]
        else:
            s += "\nEmploi régulier : indisponible (pas assez de jours mesurés)."
    return s

func vers_dict() -> Dictionary:
    return {"mois": mois, "presence": presence}

func depuis_dict(d: Dictionary) -> void:
    mois = {}
    presence = {}
    var m: Dictionary = d.get("mois", {})
    for a in m:
        var f: Dictionary = m[a]
        mois[str(a)] = {"jp": float(f.get("jp", 0.0)), "travail": float(f.get("travail", 0.0)), "perte_travail": float(f.get("perte_travail", 0.0)),
            "prod": f.get("prod", {}).duplicate(), "perte_stab": f.get("perte_stab", {}).duplicate(), "ecart": f.get("ecart", {}).duplicate()}
    var p: Dictionary = d.get("presence", {})
    for cle in p:
        var l: Array = []
        for v in p[cle]:
            l.append(int(v))
        presence[str(cle)] = l
