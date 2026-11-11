extends RefCounted

# Rapport mensuel du Premier ministre (v0.3.61) : INFORMATION SEULEMENT.
#  - Résultats : uniquement des réalisations mesurées (soins donnés, raids terminés, recettes et
#    dépenses écrites au journal). Aucune estimation n'est présentée comme une réalisation.
#  - Taux d'exécution : réalisé / besoin RÉEL du mois. Sans dénominateur (aucun malade, aucun
#    impôt dû, pas d'objectif), il est marqué « indisponible » au lieu d'être inventé.
#  - Demandes : ce que les secteurs réclament d'après des besoins réels. Accepter ou refuser
#    enregistre une DÉCISION ; rien n'est exécuté, aucune ressource ni aucun système ne change.
#    Une demande déjà tranchée n'est pas reproposée avant 6 mois.
#  - Projets : vide pour l'instant (les missions viennent plus tard).
#  - Alerte : seulement pour une crise réelle (malades sans guérisseur, faim, finances critiques).
# Pas de missions, pas de directives, pas de bonus, pas de dépense.

signal evenement(texte)

const NOMS := {"sante": "Santé", "defense": "Défense", "finances": "Finances"}
const DELAI_REPROPOSITION := 180
const MAX_DEMANDES := 6
const DECISIONS_GARDEES := 20
const DELAI_REPORT := 30
const MAX_URGENCE := 3
const URGENCES := ["normale", "élevée", "haute", "critique"]
# Indicateur de satisfaction qui mesure le problème derrière chaque demande (sinon : pas de mesure).
const LIES := {"sante_guerisseur": "sante", "sante_plantes": "sante", "sante_soins": "sante", "finances_arrieres": "salaires"}
const SI_RIEN := {
    "sante_guerisseur": "les malades ne sont pas soignés : la satisfaction santé baisse, puis la stabilité du clan.",
    "sante_plantes": "les soins manquent de plantes : les malades restent sans traitement.",
    "sante_soins": "des malades restent sans soin : la satisfaction santé baisse.",
    "defense_armes": "des combattants restent sans arme : le clan est plus faible face aux raids.",
    "defense_effectif": "le clan ne peut pas mobiliser de groupe en cas de menace.",
    "finances_budget": "chantiers et entretien continuent de se payer sur les stocks des habitants.",
    "finances_reserve": "la réserve s'épuise : salaires et entretien risquent de ne plus être payés.",
    "finances_arrieres": "les salaires impayés s'accumulent : la satisfaction salaires baisse."}

var dernier := {}                 # dernier rapport mensuel
var demandes: Array = []          # en attente : {id, secteur, texte, cout, jour}
var decisions: Array = []         # {id, secteur, texte, choix, jour}
var delais := {}                  # id de demande -> jour de la dernière décision
var derniere_alerte := ""
var dernier_jour := -1

# ---------- Résultats ----------

func _taux(realise: float, besoin: float) -> float:
    return realise / besoin if besoin > 0.0001 else -1.0

func _resultats(c, jour: int) -> Array:
    var l: Array = []
    var inst = c.institutions
    # Santé
    var soins: float = float(inst.etat["sante"]["dernier"])
    var besoin: float = float(inst.etat["sante"]["besoin_dernier"])
    l.append({"secteur": "sante", "lignes": ["Soins donnés : %d" % int(soins), "Journées de malades à soigner : %d" % int(besoin)], "taux": _taux(soins, besoin), "raison": "aucun malade ce mois-ci"})
    # Défense : raids terminés depuis le dernier rapport
    var menes := 0
    var subis := 0
    var gagnes := 0
    var repousses := 0
    var butin := 0.0
    var morts := 0
    var r = c.get("raids")
    if r != null:
        for x in r.historique:
            if int(x["retour"]) <= dernier_jour or int(x["retour"]) > jour:
                continue
            if x["att"] == "joueur":
                menes += 1
                morts += int(x["morts_att"])
                butin += float(x["butin"])
                if x["issue"] == "victoire" or x["issue"] == "partiel":
                    gagnes += 1
            elif x["dst"] == "joueur":
                subis += 1
                morts += int(x["morts_def"])
                if x["issue"] == "repousse" or x["issue"] == "defaite":
                    repousses += 1
    l.append({"secteur": "defense", "lignes": ["Raids menés : %d (réussis : %d)" % [menes, gagnes], "Raids subis : %d (repoussés ou perdus par l'attaquant : %d)" % [subis, repousses], "Butin rapporté : %d kg, morts de notre côté : %d" % [int(butin), morts]], "taux": -1.0, "raison": "aucun objectif de défense fixé"})
    # Finances
    var f = c.finances
    var rec: Dictionary = f.total("rec", 30)
    var dep: Dictionary = f.total("dep", 30)
    var du := 0.0
    if not c.budget.journal.is_empty():
        du = float(c.budget.journal[c.budget.journal.size() - 1].get("du", 0.0))
    var lf: Array = ["Recettes : %d, dépenses : %d, solde : %+d (kg de mil équivalent)" % [int(round(f.somme(rec))), int(round(f.somme(dep))), int(round(f.somme(rec) - f.somme(dep)))]]
    if float(f.arrieres) > 0.0001:
        lf.append("Salaires impayés : %d" % int(round(float(f.arrieres))))
    l.append({"secteur": "finances", "lignes": lf, "taux": _taux(float(rec.get("impot", 0.0)), du), "raison": "aucun impôt dû ce mois-ci"})
    return l

func _blocages(c, jour: int) -> Array:
    var l: Array = []
    for s in c.gouvernement.tableau(c, jour):
        if NOMS.has(s["id"]):
            for b in s["besoins"]:
                l.append("%s : %s" % [NOMS[s["id"]], b])
    return l

# ---------- Demandes (besoins réels) ----------

func _candidates(c, jour: int) -> Array:
    var l: Array = []
    var pop = c.population
    var malades: int = pop.a_soigner().size()
    var g: int = pop.nb_guerisseurs()
    var plantes: float = float(c.ressources.quantite("plantes_medicinales"))
    var capacite: int = pop.capacite_soins(int(c.construction.effet_total("soin_places")))
    if malades > 0 and g == 0:
        l.append({"id": "sante_guerisseur", "secteur": "sante", "texte": "Désigner un guérisseur : %d malade(s) et personne pour soigner." % malades, "cout": "25 % du temps d'un habitant, aucune dépense"})
    if malades > 0 and plantes < float(malades) * float(pop.PLANTES_PAR_SOIN) * 10.0:
        l.append({"id": "sante_plantes", "secteur": "sante", "texte": "Constituer une réserve de plantes médicinales (%d kg pour %d malade(s))." % [int(plantes), malades], "cout": "temps de cueillette ; coût à chiffrer par une mission"})
    if g > 0 and malades > capacite:
        l.append({"id": "sante_soins", "secteur": "sante", "texte": "Augmenter la capacité de soins (%d à soigner pour %d soins par jour)." % [malades, capacite], "cout": "chantier d'infirmerie ou guérisseurs de plus ; coût à chiffrer par une mission"})
    var dispo: int = c.guerre.combattants(pop, c.ressources, jour).size()
    var armes: int = c.equipement.nombre("lance") + c.equipement.nombre("arc")
    if dispo > 0 and armes * 2 < dispo:
        l.append({"id": "defense_armes", "secteur": "defense", "texte": "Équiper les combattants : %d arme(s) pour %d combattant(s)." % [armes, dispo], "cout": "fabrication d'armes ; coût à chiffrer par une mission"})
    if c.guerre.plafond(pop, c.ressources, jour) < 2:
        l.append({"id": "defense_effectif", "secteur": "defense", "texte": "Former davantage de protecteurs : trop peu de combattants pour mobiliser un groupe.", "cout": "temps des habitants désignés, aucune dépense"})
    var f = c.finances
    var e: Dictionary = f.etat(c)
    if not f.budget_actif(c) and not c.construction.batiments.is_empty():
        l.append({"id": "finances_budget", "secteur": "finances", "texte": "Fixer un impôt : chantiers et entretien se paient sur les stocks des habitants.", "cout": "impôt de 0 à 30 % ; au-delà de 10 %, le travail rend moins"})
    if str(e["code"]) == "alerte" or str(e["code"]) == "critique" or str(e["code"]) == "incapacite":
        l.append({"id": "finances_reserve", "secteur": "finances", "texte": "Redresser la réserve commune (%d jours de réserve)." % int(maxf(0.0, float(e["jours"]))), "cout": "relever l'impôt ou réduire les dépenses"})
    if float(f.arrieres) > 0.0001:
        l.append({"id": "finances_arrieres", "secteur": "finances", "texte": "Payer les salaires impayés.", "cout": "%d kg de mil équivalent prélevés sur la réserve" % int(round(float(f.arrieres)))})
    return l

func _alerte(c) -> String:
    var l: PackedStringArray = []
    var pop = c.population
    if pop.a_soigner().size() > 0 and pop.nb_guerisseurs() == 0:
        l.append("des habitants sont malades et personne ne soigne")
    if c.ressources.faim:
        l.append("le clan souffre de la faim")
    var e: Dictionary = c.finances.etat(c)
    if str(e["code"]) == "critique" or str(e["code"]) == "incapacite":
        l.append("les finances sont critiques")
    if str(c.satisfaction.statut) != "stable":
        l.append("la stabilité du clan est %s (%d %%)" % [c.satisfaction.statut, int(round(c.satisfaction.stabilite))])
    return ", ".join(l)

# ---------- Chaque mois (après les institutions) ----------

func mois_passe(c, jour: int) -> void:
    if dernier_jour < 0:
        dernier_jour = jour - 30
    var pm: Dictionary = c.conseil.habitant(c.population, int(c.conseil.chef_id)) if int(c.conseil.chef_id) >= 0 else {}
    dernier = {"jour": jour, "pm": ("%s %s" % [pm["prenom"], pm["nom"]]) if not pm.is_empty() else "", "resultats": _resultats(c, jour), "blocages": _blocages(c, jour), "alerte": _alerte(c), "satisfaction": c.satisfaction.etat()}
    dernier_jour = jour
    # Demandes : on retire celles qui n'ont plus d'objet, on ajoute les nouvelles besoins réels.
    var actives := {}
    for cand in _candidates(c, jour):
        actives[cand["id"]] = cand
    var gardees: Array = []
    var revenues := 0
    for d in demandes:
        if actives.has(d["id"]):
            d["texte"] = actives[d["id"]]["texte"]
            if str(d.get("etat", "attente")) == "reportee" and jour >= int(d.get("jusqu", 0)):
                _reformuler(c, d, jour)
                revenues += 1
            gardees.append(d)
        else:
            _noter_decision(d, "sans objet", jour)
    demandes = gardees
    var nouvelles := 0
    for id in actives:
        var deja := false
        for d in demandes:
            if d["id"] == id:
                deja = true
        if deja or demandes.size() >= MAX_DEMANDES:
            continue
        if delais.has(id) and jour - int(delais[id]) < DELAI_REPROPOSITION:
            continue
        var a: Dictionary = actives[id]
        demandes.append({"id": id, "secteur": a["secteur"], "texte": a["texte"], "cout": a["cout"], "jour": jour, "etat": "attente", "urgence": 0, "jusqu": 0, "ref": -1.0, "reports": 0, "note": "", "si_rien": SI_RIEN.get(id, "")})
        nouvelles += 1
    if str(dernier["alerte"]) != derniere_alerte:
        derniere_alerte = str(dernier["alerte"])
        if derniere_alerte != "":
            evenement.emit("Rapport du Premier ministre : alerte, %s." % derniere_alerte)
    if nouvelles > 0 or revenues > 0:
        var attente := 0
        for d in demandes:
            if str(d.get("etat", "attente")) == "attente":
                attente += 1
        evenement.emit("Rapport du Premier ministre : %d demande(s) en attente de votre décision." % attente)

# Une demande reportée revient devant le dirigeant : la MÊME demande, reformulée d'après les faits.
# Son urgence ne monte que si l'indicateur lié montre que le problème persiste.
func _reformuler(c, d: Dictionary, jour: int) -> void:
    d["etat"] = "attente"
    var lie: String = str(LIES.get(str(d["id"]), ""))
    var avant: float = float(d.get("ref", -1.0))
    var apres: float = c.satisfaction.valeur(lie) if lie != "" else -1.0
    var depuis: int = jour - int(d.get("jusqu", jour)) + DELAI_REPORT
    if lie != "" and avant >= 0.0 and apres >= 0.0:
        var nom: String = c.satisfaction.NOMS[lie].to_lower()
        if apres <= avant + 2.0:
            d["urgence"] = mini(MAX_URGENCE, int(d.get("urgence", 0)) + 1)
            d["note"] = "Reportée depuis %d jours : le problème persiste (satisfaction %s %d %% puis %d %%)." % [depuis, nom, int(round(avant)), int(round(apres))]
        else:
            d["note"] = "Reportée depuis %d jours : la situation s'améliore (satisfaction %s %d %% puis %d %%)." % [depuis, nom, int(round(avant)), int(round(apres))]
    else:
        d["note"] = "Reportée depuis %d jours : aucun indicateur ne permet de mesurer l'évolution, l'urgence reste inchangée." % depuis

# Le dirigeant remet la décision à plus tard. La demande reste suivie, aucune décision n'est enregistrée comme refus.
func reporter(id: String, jour: int, valeur_ref: float) -> String:
    for d in demandes:
        if d["id"] == id:
            if str(d.get("etat", "attente")) == "reportee":
                return "Cette demande est déjà reportée."
            d["etat"] = "reportee"
            d["jusqu"] = jour + DELAI_REPORT
            d["ref"] = valeur_ref
            d["reports"] = int(d.get("reports", 0)) + 1
            _noter_decision(d, "reportee", jour)
            return ""
    return "Cette demande n'existe plus."

func _noter_decision(d: Dictionary, choix: String, jour: int) -> void:
    decisions.append({"id": d["id"], "secteur": d["secteur"], "texte": d["texte"], "choix": choix, "jour": jour})
    while decisions.size() > DECISIONS_GARDEES:
        decisions.pop_front()

# Enregistre la décision du dirigeant. Aucune exécution, aucune ressource touchée.
func decider(id: String, choix: String, jour: int) -> String:
    if choix != "acceptee" and choix != "refusee":
        return "Choix inconnu."
    for i in demandes.size():
        if demandes[i]["id"] == id:
            var d: Dictionary = demandes[i]
            demandes.remove_at(i)
            delais[id] = jour
            _noter_decision(d, choix, jour)
            return ""
    return "Cette demande n'existe plus."

func vers_dict() -> Dictionary:
    return {"dernier": dernier, "demandes": demandes, "decisions": decisions, "delais": delais, "alerte": derniere_alerte, "jour": dernier_jour}

func depuis_dict(d: Dictionary) -> void:
    dernier = d.get("dernier", {})
    demandes = d.get("demandes", [])
    decisions = d.get("decisions", [])
    delais = {}
    for k in d.get("delais", {}):
        delais[str(k)] = int(d["delais"][k])
    derniere_alerte = str(d.get("alerte", ""))
    dernier_jour = int(d.get("jour", -1))
