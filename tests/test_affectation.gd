extends SceneTree
# Contrôle de l'affectation individuelle (v0.4) : critères 1 à 5, protection de
# 90 jours, expiration, sauvegarde, cas du dernier porteur d'eau.
# Lancer : godot --headless --path . --script res://tests/test_affectation.gd
var _ok := 0
var _ko := 0
var _fait := false

func _t(cond: bool, nom: String) -> void:
    if cond:
        _ok += 1
        print("  OK  ", nom)
    else:
        _ko += 1
        print("  KO  ", nom)

func _jour(C) -> void:
    C.temps._passer_un_jour()    # jour complet, avec les passages de mois

func _coherent(pop) -> bool:
    # nombre de travailleurs == postes pour chaque métier tenu
    for m in pop.postes:
        if pop.nombre(m) > int(pop.postes[m]):
            return false
    return true

func _process(_d) -> bool:
    if _fait:
        return true
    _fait = true
    var C = root.get_node("Civilisation")
    var pop = C.population
    var j0: int = C.temps.jour_total
    for i in 5:
        _jour(C)
    print("--- Critère 2 : refus et raisons")
    var chasseur: Dictionary = {}
    for h in pop.habitants:
        if h["metier"] == "chasseur":
            chasseur = h
    _t(not chasseur.is_empty(), "un chasseur existe")
    var jour: int = C.temps.jour_total
    _t(pop.raison_affectation(chasseur, "cueilleur", jour) == "", "adulte : affectation possible")
    _t(pop.raison_affectation(chasseur, "chasseur", jour) != "", "déjà dans ce métier : refusé")
    var chef: Dictionary = {}
    var enfant: Dictionary = {}
    for h in pop.habitants:
        if h["metier"] == "chef":
            chef = h
        if pop.age(h, jour) < pop.AGE_ADULTE:
            enfant = h
    _t(chef.is_empty() or pop.raison_affectation(chef, "cueilleur", jour) != "", "Premier ministre : refusé")
    _t(enfant.is_empty() or pop.raison_affectation(enfant, "cueilleur", jour) != "", "enfant : refusé")
    chasseur["expedition"] = true
    _t(pop.raison_affectation(chasseur, "cueilleur", jour) != "", "en expédition : refusé")
    chasseur.erase("expedition")
    _t(pop.raison_affectation(chasseur, "métier inventé", jour) != "", "métier inconnu : refusé")

    print("--- Critère 3 : postes et personne ensemble")
    var dc0: int = C.besoins.dernier_changement
    var nb_c: int = pop.nombre("cueilleur")
    var p_c: int = int(pop.postes["cueilleur"])
    var nb_ch: int = pop.nombre("chasseur")
    var p_ch: int = int(pop.postes["chasseur"])
    var r: String = pop.affecter(chasseur, "cueilleur", jour)
    _t(r == "", "affecter() accepte")
    _t(chasseur["metier"] == "cueilleur", "la personne a changé de métier")
    _t(int(pop.postes["cueilleur"]) == p_c + 1 and pop.nombre("cueilleur") == nb_c + 1, "cueilleur : postes et effectif +1")
    _t(int(pop.postes["chasseur"]) == p_ch - 1 and pop.nombre("chasseur") == nb_ch - 1, "chasseur : postes et effectif -1")
    _t(_coherent(pop), "effectifs <= postes pour tous les métiers")
    _t(C.besoins.dernier_changement == dc0, "le délai de 60 jours du Premier ministre n'est pas relancé")
    _t(pop.est_protege(chasseur, jour) and int(chasseur["protege_jusqu"]) == jour + 90, "protégé 90 jours")
    pop.repartir(jour)
    _t(chasseur["metier"] == "cueilleur", "repartir() ne défait pas le choix")

    print("--- Critère 4 : aperçu = production réelle (une seule formule)")
    # Nourriture du cueilleur : prod_metier cumule la quantité réelle du jour.
    # On compare sur 5 jours consécutifs ; l'écart doit rester faible.
    var pire := 0.0
    for k in 5:
        C.ressources.prod_metier = {}
        var prevu := 0.0
        var pluie: bool = C.temps.saison_des_pluies()
        for h in pop.habitants:
            if h["metier"] == "cueilleur" and not h.get("occupe", false):
                prevu += float(C.ressources.apercu_metier(h, "cueilleur", pop, pluie).get("nourriture", 0.0))
        if k == 0:
            for h in pop.habitants:
                if h["metier"] == "cueilleur":
                    print("     avant : id %d comp %.2f savoir %.2f occupe %s apercu %.3f" % [int(h["id"]), float(h["competence"]), pop.savoir(h, "cueillette"), str(h.get("occupe", false)), float(C.ressources.apercu_metier(h, "cueilleur", pop, pluie).get("nourriture", 0.0))])
        _jour(C)
        if k == 0:
            for h in pop.habitants:
                if h["metier"] == "cueilleur":
                    print("     après : id %d comp %.2f" % [int(h["id"]), float(h["competence"])])
        var reel: float = float(C.ressources.prod_metier.get("cueilleur", 0.0))
        print("   jour %d : prévu %.4f / réel %.4f / stabilité %.3f" % [k, prevu, reel, C.ressources.facteur_stabilite])
        if k > 0:    # jour 0 : le monde change (mois, saison) entre l'aperçu et le calcul réel
            pire = maxf(pire, absf(prevu - reel) / maxf(prevu, 1.0))
    _t(pire < 0.05, "aperçu cueilleur = production du jour (écart max %.1f %%, seuil 5 %%)" % (pire * 100.0))

    print("--- Métier sans poste (pêcheur) : la personne reste gérée par les postes")
    var autre: Dictionary = {}
    var attendu_exp := 1
    for h in pop.habitants:
        if h["metier"] == "cueilleur" and h != chasseur:
            autre = h
            break
    if not autre.is_empty() and pop.metiers_choisis().has("pêcheur"):
        var ra: String = pop.affecter(autre, "pêcheur", jour)
        attendu_exp = 2
        _t(ra == "" and int(pop.postes.get("pêcheur", 0)) >= 1, "un métier sans poste en reçoit un")
        _t(pop.nombre("pêcheur") <= int(pop.postes.get("pêcheur", 0)), "effectif pêcheur <= postes")
    print("--- Protection sur 120 jours (PM, plancher d'eau, agriculture)")
    var morts_avant: int = pop.habitants.size()
    var expire := [0]
    pop.protection_expiree.connect(func(h): expire[0] += 1)
    var changements := 0
    var vu_protege_ok := true
    var j_aff: int = jour
    var id_c: int = int(chasseur["id"])
    for i in 120:
        _jour(C)
        var x: Dictionary = pop.par_id(id_c)
        if x.is_empty():
            break
        if C.temps.jour_total < j_aff + 90 and x["metier"] != "cueilleur":
            vu_protege_ok = false
    var x2: Dictionary = pop.par_id(id_c)
    _t(not x2.is_empty(), "la personne est toujours vivante")
    _t(vu_protege_ok, "métier inchangé pendant les 90 jours")
    _t(expire[0] == attendu_exp, "chaque protection expire une fois (signal)")
    _t(not x2.is_empty() and not x2.has("protege_jusqu"), "clé de protection retirée à l'expiration")

    print("--- Critère 5 / sauvegarde : la protection survit à un rechargement")
    var cible: Dictionary = {}
    for h in pop.habitants:
        if h["metier"] == "cueilleur" and pop.age(h, C.temps.jour_total) >= 14:
            cible = h
            break
    var cible_id := -1
    if not cible.is_empty():
        cible_id = int(cible["id"])
        var m_voulu := "pêcheur" if pop.metiers_choisis().has("pêcheur") else "chasseur"
        var r2: String = pop.affecter(cible, m_voulu, C.temps.jour_total)
        _t(r2 == "", "affectation pour le test de sauvegarde")
        # Critère 4 bis : l'aperçu du jour de l'affectation, plus tard dans la partie
        C.ressources.prod_metier = {}
        var prevu2 := 0.0
        var pl2: bool = C.temps.saison_des_pluies()
        for h in pop.habitants:
            if h["metier"] == m_voulu and not h.get("occupe", false):
                prevu2 += float(C.ressources.apercu_metier(h, m_voulu, pop, pl2).get("nourriture", 0.0))
        _jour(C)
        var reel2: float = float(C.ressources.prod_metier.get(m_voulu, 0.0))
        print("   aperçu bis (%s) : prévu %.4f / réel %.4f" % [m_voulu, prevu2, reel2])
        _t(absf(prevu2 - reel2) < 0.03 * maxf(prevu2, 1.0), "aperçu = réel dès le premier jour après l'affectation (3 %)")
        var json := JSON.stringify(pop.vers_dict())
        var d: Dictionary = JSON.parse_string(json)
        var P2 = load("res://scripts/core/population.gd").new()
        P2.depuis_dict(d)
        var y: Dictionary = P2.par_id(cible_id)
        _t(not y.is_empty() and typeof(y["protege_jusqu"]) == TYPE_INT, "protege_jusqu rechargé en entier")
        _t(P2.est_protege(y, C.temps.jour_total), "toujours protégé après rechargement")
        _t(y["metier"] == m_voulu, "métier conservé après rechargement")

    print("--- Cas du dernier porteur d'eau")
    var porteur: Dictionary = {}
    for h in pop.habitants:
        if h["metier"] == "porteur d'eau" and not pop.est_protege(h, C.temps.jour_total):
            porteur = h
    if porteur.is_empty():
        print("  (aucun porteur d'eau libre : cas non testé)")
    else:
        var msgs := []
        C.besoins.evenement.connect(func(t): msgs.append(str(t)))
        var n_porteurs: int = pop.nombre("porteur d'eau")
        var rb: String = pop.affecter(porteur, "bâtisseur", C.temps.jour_total)
        _t(rb == "", "le joueur retire un porteur d'eau (alerte, pas d'interdiction)")
        C.ressources.stocks["eau"] = 20.0
        var id_p: int = int(porteur["id"])
        for i in 45:
            _jour(C)
            if i % 5 == 0:
                print("     j%d (jour du mois %d) : porteurs %d / postes %s" % [C.temps.jour_total, C.temps.jour_total % 30, pop.nombre("porteur d'eau"), str(pop.postes.get("porteur d'eau"))])
            C.ressources.stocks["eau"] = minf(maxf(float(C.ressources.stocks["eau"]), 60.0), 60.0)   # réserve critique mais personne ne meurt de soif
        var libre_bat: Array = pop.habitants.filter(func(x): return x["metier"] == "bâtisseur").map(func(x): return [int(x["id"]), pop.est_protege(x, C.temps.jour_total), int(x["competence"])])
        print("   bâtisseurs (id, protégé, comp) : ", libre_bat, " postes ", pop.postes)
        pop.repartir(C.temps.jour_total)
        print("   après repartir manuel : porteurs ", pop.nombre("porteur d'eau"), " bâtisseurs ", pop.nombre("bâtisseur"), " sans métier ", pop.nombre("sans métier"))
        var xp: Dictionary = pop.par_id(id_p)
        _t(not xp.is_empty() and xp["metier"] == "bâtisseur", "le Premier ministre ne déplace pas la personne protégée")
        print("   habitants : ", pop.habitants.size(), " ; personne protégée : ", "absente (morte ?)" if xp.is_empty() else xp["metier"], " ; sans métier : ", pop.nombre("sans métier"), " ; bâtisseurs : ", pop.nombre("bâtisseur"), "/", pop.postes.get("bâtisseur"))
        var nouveaux: int = pop.nombre("porteur d'eau")
        var avis_pm := false
        for t in msgs:
            if t.find("protègent") >= 0 or t.find("porteur") >= 0:
                avis_pm = true
        print("   porteurs avant %d, après %d ; messages PM : %s" % [n_porteurs, nouveaux, str(msgs)])
        _t(nouveaux >= n_porteurs or avis_pm, "soit un autre adulte devient porteur, soit le jeu le dit")

    print("RESULTAT : %d OK, %d KO" % [_ok, _ko])
    quit(1 if _ko > 0 else 0)
    return true
