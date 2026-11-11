extends RefCounted

# Missions (v0.3.62). Une seule mission branchée : équiper les combattants par une VRAIE
# fabrication (recettes.gd : lance ou arc, avec matières, travail, ouvriers).
#  - Devis : la durée réelle est calculée d'après le travail, les ouvriers et la file de fabrication ;
#    la durée ANNONCÉE est réduite jusqu'à 40 % selon la compétence du ministre (devis moins fiable).
#    La fabrication, elle, n'est jamais modifiée.
#  - Moyens RÉSERVÉS : les matières sont retirées au lancement (par recettes.gd). Moyens simplement
#    PRÉSENTS : ouvriers, atelier, outil. S'ils disparaissent, c'est un problème de moyens.
#  - Échecs : faute de moyens (aucune sanction), mauvaise exécution (inscrite au dossier du
#    responsable), imprévisible (aucune sanction ; les jours bloqués ne comptent pas dans le délai).
#  - Le responsable et sa compétence sont figés au lancement.
#  - Deux mauvaises exécutions de suite : recommandation au dirigeant, jamais de remplacement automatique.
#  - Aucun remboursement, aucun bonus, aucun point d'institution.

signal evenement(texte)

const NOMS := {"armes": "Équiper les combattants"}
const ARMES := ["lance", "arc"]
const MAX_ARMES := 4
const MAX_RENFORCE := 6
const NIVEAUX := {"moitie": "Moitié", "normal": "Normal", "renforce": "Renforcé"}
const MARGE_SOUS_ESTIMATION := 0.4
const TOLERANCE_RETARD := 0.25
const MAX_BLOQUE_MOYENS := 20
const MAX_BLOQUE_IMPREVU := 30
const ECHECS_AVANT_RECOMMANDATION := 2
const HISTORIQUE := 10
const ISSUES := {"reussie": "réussie", "echec_moyens": "échec : faute de moyens", "echec_execution": "échec : mauvaise exécution", "echec_imprevu": "échec : imprévisible"}
const IMPOSSIBLES := {
    "sante_plantes": "mission pas encore possible : on ne peut pas affecter des habitants à la cueillette de plantes.",
    "finances_arrieres": "aucune mission possible : le paiement est automatique, seul un impôt plus élevé ou des dépenses réduites remplit la réserve."}

var actuelle := {}
var terminees: Array = []
var dossiers := {}
var prochain := 1

func note_impossible(id: String) -> String:
    return str(IMPOSSIBLES.get(id, ""))

# ---------- Devis ----------

func devis(c, jour: int, niveau := "normal") -> Dictionary:
    var d := {"possible": false, "raison": "", "type": "armes", "niveau": niveau}
    if not actuelle.is_empty():
        d["raison"] = "Une mission est déjà en cours."
        return d
    var g = c.gouvernement
    var rid: int = g.titulaire_de("defense", "titulaire")
    var h: Dictionary = g._habitant(c, rid) if rid >= 0 else {}
    if h.is_empty():
        d["raison"] = "Aucun ministre de la Défense n'est nommé : personne ne peut être chargé de la mission."
        return d
    var pop = c.population
    var dispo: int = c.guerre.combattants(pop, c.ressources, jour).size()
    var armes: int = c.equipement.nombre("lance") + c.equipement.nombre("arc")
    var manque: int = int(ceil(float(dispo) / 2.0)) - armes
    if manque <= 0:
        d["raison"] = "Les combattants sont déjà équipés (au moins une arme pour deux)."
        return d
    var cible: int = mini(manque, MAX_ARMES)
    if niveau == "moitie":
        cible = maxi(1, int(ceil(float(cible) / 2.0)))
    elif niveau == "renforce":
        cible = mini(MAX_RENFORCE, int(ceil(float(cible) * 1.5)))
    var choix := ""
    var n := 0
    for id in ARMES:
        for k in range(cible, 0, -1):
            if bool(c.recettes.etat(id, pop, c.ressources, c.construction, jour, k)["possible"]):
                choix = id
                n = k
                break
        if choix != "":
            break
    if choix == "":
        d["raison"] = "Moyens insuffisants : " + str(c.recettes.etat(ARMES[0], pop, c.ressources, c.construction, jour, 1)["raisons"][0])
        return d
    var r: Dictionary = c.recettes.definitions[choix]
    var rythme := 0.0
    for o in c.recettes._libres(pop, jour):
        if pop.savoir(o, r["competence"]) >= float(r.get("niveau_min", 0)):
            rythme += 0.5 + pop.savoir(o, r["competence"]) / 100.0
    if rythme <= 0.0:
        d["raison"] = "Moyens insuffisants : aucun ouvrier capable."
        return d
    var devant := 0.0
    for x in c.recettes.commandes:
        devant += float(x["reste"])
    var reelle: int = maxi(1, int(ceil((devant + float(r["jours_travail"]) * n) / rythme)))
    var comp: float = float(c.institutions.competence("defense", c, jour)["valeur"])
    var sous: float = MARGE_SOUS_ESTIMATION * (1.0 - clampf(comp, 0.0, 100.0) / 100.0)
    var annoncee: int = maxi(1, int(floor(float(reelle) * (1.0 - sous))))
    var entrees := {}
    for m in r["entrees"]:
        entrees[m] = float(r["entrees"][m]) * n
    var pertes := {}
    for m in r.get("pertes", {}):
        pertes[m] = float(r["pertes"][m]) * n
    d.merge({"possible": true, "recette": choix, "nom": str(r["nom"]), "nombre": n, "entrees": entrees, "pertes": pertes,
        "reelle": reelle, "annoncee": annoncee, "ouvriers": c.recettes._libres(pop, jour).size(), "resp_id": rid,
        "resp_nom": "%s %s" % [h["prenom"], h["nom"]], "comp": comp}, true)
    return d

func _liste(m: Dictionary) -> String:
    var l: PackedStringArray = []
    for k in m:
        l.append("%.1f %s" % [float(m[k]), k])
    return ", ".join(l)

func texte_devis(d: Dictionary) -> String:
    return "Devis %s : %d × %s. Matières retirées dès le lancement : %s. Responsable : %s (compétence %d). Durée annoncée : %d jour(s). Durée réellement estimée : %d jour(s). Plus la compétence du ministre est basse, plus l'annonce est optimiste." % [NIVEAUX[d["niveau"]].to_lower(), int(d["nombre"]), d["nom"], _liste(d["entrees"]), d["resp_nom"], int(d["comp"]), int(d["annoncee"]), int(d["reelle"])]

# ---------- Lancement ----------

func lancer(c, jour: int, niveau := "normal") -> String:
    var d: Dictionary = devis(c, jour, niveau)
    if not d["possible"]:
        return str(d["raison"])
    var raison: String = c.recettes.commander(d["recette"], c.population, c.ressources, c.construction, jour, int(d["nombre"]))
    if raison != "":
        return raison
    var cmd: Dictionary = c.recettes.commandes.back()
    var mid := "m%d" % prochain
    prochain += 1
    cmd["mission"] = mid
    actuelle = {"id": mid, "type": "armes", "recette": d["recette"], "nom": d["nom"], "nombre": int(d["nombre"]), "debut": jour,
        "resp_id": int(d["resp_id"]), "resp_nom": d["resp_nom"], "comp": float(d["comp"]), "annoncee": int(d["annoncee"]),
        "reelle": int(d["reelle"]), "reste": float(cmd["reste"]), "imprevu": 0, "moyens": 0, "cons_imprevu": 0, "cons_moyens": 0,
        "entrees": d["entrees"], "pertes": d["pertes"]}
    evenement.emit("Mission : lancée, %d × %s sous la responsabilité de %s (durée annoncée %d jours)." % [int(d["nombre"]), d["nom"], d["resp_nom"], int(d["annoncee"])])
    return ""

# ---------- Chaque jour (après les fabrications) ----------

func jour_passe(c, jour: int) -> void:
    if actuelle.is_empty():
        return
    var cmd := {}
    var rang := -1
    for i in c.recettes.commandes.size():
        if str(c.recettes.commandes[i].get("mission", "")) == str(actuelle["id"]):
            cmd = c.recettes.commandes[i]
            rang = i
    if cmd.is_empty():
        _conclure(c, jour, "livree")
        return
    var reste: float = float(cmd["reste"])
    if reste < float(actuelle["reste"]) - 0.000001:
        actuelle["reste"] = reste
        actuelle["cons_imprevu"] = 0
        actuelle["cons_moyens"] = 0
        return
    if rang > 0:
        return    # une autre fabrication passe devant : déjà comprise dans le devis
    var exclus := 0
    for h in c.population.habitants:
        if h["metier"] == "sans métier" and c.population.age(h, jour) >= c.population.AGE_ADULTE and (h.has("experience") or h.has("expedition")):
            exclus += 1
    if exclus > 0:
        actuelle["imprevu"] = int(actuelle["imprevu"]) + 1
        actuelle["cons_imprevu"] = int(actuelle["cons_imprevu"]) + 1
        actuelle["cons_moyens"] = 0
    else:
        actuelle["moyens"] = int(actuelle["moyens"]) + 1
        actuelle["cons_moyens"] = int(actuelle["cons_moyens"]) + 1
        actuelle["cons_imprevu"] = 0
    if int(actuelle["cons_moyens"]) >= MAX_BLOQUE_MOYENS:
        cmd.erase("mission")
        _conclure(c, jour, "abandon_moyens")
    elif int(actuelle["cons_imprevu"]) >= MAX_BLOQUE_IMPREVU:
        cmd.erase("mission")
        _conclure(c, jour, "abandon_imprevu")

func _conclure(c, jour: int, cas: String) -> void:
    var a: Dictionary = actuelle
    actuelle = {}
    var ecoule: int = jour - int(a["debut"]) + 1
    var effectif: int = ecoule - int(a["imprevu"])
    var limite: int = int(ceil(float(a["annoncee"]) * (1.0 + TOLERANCE_RETARD)))
    var issue := "echec_moyens"
    match cas:
        "livree":
            if effectif <= limite:
                issue = "reussie"
            elif int(a["moyens"]) > 0:
                issue = "echec_moyens"
            else:
                issue = "echec_execution"
        "abandon_imprevu":
            issue = "echec_imprevu"
    var k := str(a["resp_id"])
    var dos: Dictionary = dossiers.get(k, {"reussies": 0, "moyens": 0, "execution": 0, "imprevus": 0, "consecutives": 0})
    match issue:
        "reussie":
            dos["reussies"] = int(dos["reussies"]) + 1
            dos["consecutives"] = 0
        "echec_moyens":
            dos["moyens"] = int(dos["moyens"]) + 1
        "echec_imprevu":
            dos["imprevus"] = int(dos["imprevus"]) + 1
        "echec_execution":
            dos["execution"] = int(dos["execution"]) + 1
            dos["consecutives"] = int(dos["consecutives"]) + 1
    dossiers[k] = dos
    var livre: bool = cas == "livree"
    terminees.append({"id": a["id"], "nom": a["nom"], "recette": a["recette"], "nombre": a["nombre"], "resp_id": a["resp_id"], "resp_nom": a["resp_nom"],
        "comp": a["comp"], "debut": a["debut"], "fin": jour, "annoncee": a["annoncee"], "ecoule": ecoule, "effectif": effectif, "imprevu": a["imprevu"],
        "moyens": a["moyens"], "issue": issue, "livre": livre, "consomme": a["entrees"], "pertes": a["pertes"]})
    while terminees.size() > HISTORIQUE:
        terminees.pop_front()
    evenement.emit("Mission : terminée, %s" % texte_resultat(terminees.back()))
    if issue == "echec_execution" and int(dos["consecutives"]) >= ECHECS_AVANT_RECOMMANDATION:
        evenement.emit("Mission : le Premier ministre recommande de remplacer %s (%d mauvaises exécutions de suite). La décision vous appartient." % [a["resp_nom"], int(dos["consecutives"])])

func texte_resultat(t: Dictionary) -> String:
    var s := "%d × %s, %s. Responsable : %s (compétence %d)." % [int(t["nombre"]), t["nom"], ISSUES[t["issue"]], t["resp_nom"], int(t["comp"])]
    s += " Durée annoncée %d j, durée écoulée %d j" % [int(t["annoncee"]), int(t["ecoule"])]
    if int(t["imprevu"]) > 0:
        s += " (dont %d j bloqués par des absences imprévues)" % int(t["imprevu"])
    s += ". "
    if bool(t["livre"]):
        s += "Produit : %d × %s. " % [int(t["nombre"]), t["recette"]]
    else:
        s += "Rien livré : la fabrication reste en file d'attente. "
    s += "Consommé : %s." % _liste(t["consomme"])
    if not t["pertes"].is_empty() and bool(t["livre"]):
        s += " Pertes de fabrication : %s." % _liste(t["pertes"])
    return s

# ---------- Affichage ----------

func texte_actuelle(jour: int) -> String:
    if actuelle.is_empty():
        return ""
    var a: Dictionary = actuelle
    var s := "Mission en cours : %d × %s. Responsable : %s (compétence %d, figée au lancement). Jour %d, durée annoncée %d, durée réellement estimée %d." % [int(a["nombre"]), a["nom"], a["resp_nom"], int(a["comp"]), jour - int(a["debut"]) + 1, int(a["annoncee"]), int(a["reelle"])]
    if int(a["imprevu"]) > 0 or int(a["moyens"]) > 0:
        s += " Jours bloqués : %d par absences imprévues, %d par manque de moyens." % [int(a["imprevu"]), int(a["moyens"])]
    return s

func texte_dossier(c) -> String:
    var rid: int = c.gouvernement.titulaire_de("defense", "titulaire")
    if rid < 0 or not dossiers.has(str(rid)):
        return ""
    var d: Dictionary = dossiers[str(rid)]
    var s := "Dossier du ministre de la Défense : %d réussite(s), %d échec(s) faute de moyens, %d mauvaise(s) exécution(s), %d imprévu(s)." % [int(d["reussies"]), int(d["moyens"]), int(d["execution"]), int(d["imprevus"])]
    if int(d["consecutives"]) >= ECHECS_AVANT_RECOMMANDATION:
        s += " RECOMMANDATION : remplacer ce ministre (%d mauvaises exécutions de suite). Décision du dirigeant." % int(d["consecutives"])
    return s

func vers_dict() -> Dictionary:
    return {"actuelle": actuelle, "terminees": terminees, "dossiers": dossiers, "prochain": prochain}

func depuis_dict(d: Dictionary) -> void:
    actuelle = d.get("actuelle", {})
    terminees = d.get("terminees", [])
    dossiers = d.get("dossiers", {})
    prochain = int(d.get("prochain", 1))
    if not actuelle.is_empty():
        for k in ["nombre", "debut", "resp_id", "annoncee", "reelle", "imprevu", "moyens", "cons_imprevu", "cons_moyens"]:
            actuelle[k] = int(actuelle.get(k, 0))
        actuelle["reste"] = float(actuelle.get("reste", 0.0))
        actuelle["comp"] = float(actuelle.get("comp", 0.0))
