extends SceneTree
# Le Premier ministre sait-il NE PAS recruter un bâtisseur quand c'est dangereux ?
# Et la réparation en crise ne se déclenche-t-elle pas sans raison ?
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

# Met le clan dans l'état voulu : postes {métier: nombre}, tous les adultes placés,
# ceux qui ne sont pas « candidats » protégés par le joueur ; bois juste en manque.
func _preparer(C, postes: Dictionary, candidats: Array) -> Dictionary:
    var pop = C.population
    var res = C.ressources
    var jour: int = C.temps.jour_total
    for h in pop.habitants:
        h.erase("protege_jusqu")
        if pop.age(h, jour) >= pop.AGE_ADULTE and h["metier"] != "chef" and h["metier"] != "ancien":
            h["metier"] = "sans métier"
    pop.postes = postes.duplicate()
    pop.repartir(jour)
    var restants := candidats.duplicate()
    for h in pop.habitants:
        if pop.age(h, jour) < pop.AGE_ADULTE or h["metier"] in ["chef", "ancien", "enfant"]:
            continue
        if restants.has(h["metier"]):
            restants.erase(h["metier"])
        else:
            h["protege_jusqu"] = jour + 90
    C.construction.chantiers.clear()
    res.hist_prod_bois = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    res.bois_brule_jour = 0.0
    for h in pop.habitants:
        res.bois_brule_jour += float((res.CONSO_ENFANT if pop.age(h, jour) < 14 else res.CONSO_ADULTE)["bois"])
    res.stocks["bois"] = res.bois_brule_jour * 10.0 + C.construction.entretien_mois() - 5.0
    var libres := 0
    for h in pop.habitants:
        if h["metier"] == "sans métier" and pop.age(h, jour) >= pop.AGE_ADULTE:
            libres += 1
    return {"libres": libres}

func _essai(C, nom: String, postes: Dictionary, candidats: Array, eau: float, nourriture: float) -> Dictionary:
    var pop = C.population
    var res = C.ressources
    var B = C.besoins
    var prep := _preparer(C, postes, candidats)
    res.stocks["eau"] = eau
    res.aliments = {"fonio_sauvage": nourriture / res.facteur("fonio_sauvage")}
    res.stocks["nourriture"] = res.total_aliments()
    var metiers := {}
    for h in pop.habitants:
        metiers[int(h["id"])] = h["metier"]
    var avant: Dictionary = pop.postes.duplicate()
    var msgs := []
    var f := func(t): msgs.append(str(t))
    B.evenement.connect(f)
    B.mode = "auto"
    var agi: bool = B.reagir_entretien(pop, res, C.construction, C.temps.jour_total, C.temps.saison_des_pluies(), false, C.construction.prevision_entretien(res, 10), 10)
    if agi:
        pop.repartir(C.temps.jour_total)
    B.evenement.disconnect(f)
    var protege_touche := false
    for h in pop.habitants:
        if h.has("protege_jusqu") and metiers[int(h["id"])] != h["metier"]:
            protege_touche = true
    print("   [%s] libres %d, postes %s -> %s, a agi %s\n      %s" % [nom, int(prep["libres"]), str(avant), str(pop.postes), str(agi), str(msgs)])
    return {"agi": agi, "msgs": msgs, "protege_touche": protege_touche}

func _process(_d) -> bool:
    if _fait:
        return true
    _fait = true
    var C = root.get_node("Civilisation")
    for i in 40:
        C.temps._passer_un_jour()

    print("--- A. Le seul candidat est le dernier porteur d'eau")
    var r := _essai(C, "porteur", {"porteur d'eau": 1, "cueilleur": 2, "chasseur": 1, "bâtisseur": 0}, ["porteur d'eau"], 40.0, 300.0)
    _t(not r["agi"], "il ne prend pas le dernier porteur d'eau")
    _t(not r["protege_touche"], "il ne touche à aucune personne protégée")
    _t(r["msgs"].size() == 1 and str(r["msgs"][0]).find("Il ne peut déplacer personne") >= 0, "il explique son refus")

    print("--- B. Le seul candidat est le dernier cueilleur, indispensable à la nourriture")
    r = _essai(C, "cueilleur", {"porteur d'eau": 2, "cueilleur": 1, "chasseur": 0, "bâtisseur": 0}, ["cueilleur"], 3000.0, 15.0)
    _t(not r["agi"], "il ne prend pas le cueilleur dont dépend la nourriture")
    _t(not r["protege_touche"], "il ne touche à aucune personne protégée")
    _t(r["msgs"].size() == 1 and str(r["msgs"][0]).find("Il ne peut déplacer personne") >= 0, "il explique son refus")

    print("--- C. Aucun adulte disponible sans dégrader l'eau ou la nourriture")
    r = _essai(C, "aucun", {"porteur d'eau": 1, "cueilleur": 1, "chasseur": 1, "bâtisseur": 0}, ["porteur d'eau", "cueilleur", "chasseur"], 40.0, 15.0)
    var B = C.besoins
    _t(not r["agi"], "il ne recrute personne")
    _t(not r["protege_touche"], "il ne touche à aucune personne protégée")
    _t(r["msgs"].size() == 1 and (str(r["msgs"][0]).find("Il ne peut déplacer personne") >= 0 or str(r["msgs"][0]).find("aide déjà") >= 0), "il explique son refus")

    print("--- D. Témoin : un candidat sans danger existe (chasseur avec réserves pleines)")
    r = _essai(C, "témoin", {"porteur d'eau": 2, "cueilleur": 2, "chasseur": 1, "bâtisseur": 0}, ["chasseur"], 3000.0, 1500.0)
    _t(r["agi"], "il recrute quand c'est sans danger")
    _t(not r["protege_touche"], "il ne touche à aucune personne protégée")

    print("--- E. Pas de réparation injustifiée en crise")
    var v = C.voisins[0]
    var vc = v.construction
    vc.chantiers.clear()
    # Clan qui a simplement peu de réserves : aucun bâtiment en ruine.
    for b in vc.batiments:
        b["etat"] = 100
    v.ressources.stocks["bois"] = 500.0
    v.ressources.aliments = {"fonio_sauvage": 5.0 / v.ressources.facteur("fonio_sauvage")}
    v.ressources.stocks["nourriture"] = v.ressources.total_aliments()
    v.besoins._contexte(v.population, v.ressources, vc, C.temps.jour_total, C.temps.saison_des_pluies(), false)
    var cr: Dictionary = v.besoins.crise_reparation()
    print("   réserves basses, rien en ruine : %s, capacité %.0f kg / %.1f kg par jour" % [str(cr), v.ressources.capacite("nourriture"), v.besoins._conso("nourriture")])
    _t(not vc.reparation_auto(v.ressources, cr), "rien à réparer : aucune réparation")
    # Seules des jarres (eau) sont en ruine, la crise porte sur la nourriture.
    vc.batiments.append({"type": "jarres", "niveau": 1, "etat": 0})
    for b in vc.batiments:
        if b["type"] != "jarres":
            b["etat"] = 0 if b["type"] in ["hutte", "grenier"] and false else int(b["etat"])
    var cr2 := {"bloque": false, "causes": ["nourriture"]}
    _t(not vc.reparation_auto(v.ressources, cr2), "crise de nourriture : on ne répare pas des jarres (eau)")
    # Réserves basses mais capacité normale (grand stockage intact) et une hutte en ruine.
    vc.batiments.append({"type": "grenier", "niveau": 2, "etat": 100})
    vc.batiments.append({"type": "hutte", "niveau": 1, "etat": 0})
    v.besoins._contexte(v.population, v.ressources, vc, C.temps.jour_total, C.temps.saison_des_pluies(), false)
    cr = v.besoins.crise_reparation()
    print("   réserves basses, stockage suffisant : %s, capacité %.0f kg" % [str(cr), v.ressources.capacite("nourriture")])
    _t(bool(cr["bloque"]), "capacité suffisante pour une saison : crise indépendante, réparation bloquée")
    _t(not vc.reparation_auto(v.ressources, cr), "donc aucune réparation")

    print("RESULTAT : %d OK, %d KO" % [_ok, _ko])
    quit(1 if _ko > 0 else 0)
    return true
