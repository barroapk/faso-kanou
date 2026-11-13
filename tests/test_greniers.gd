extends SceneTree
# Danger des greniers (v0.4) : une vérification courte par règle (1 à 7) + sauvegarde.
# Lancer : godot --headless --path . --script res://tests/test_greniers.gd
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
    C.temps._passer_un_jour()

func _jusqu_au_jour_du_mois(C, j: int) -> void:
    while C.temps.jour_total % 30 != j:
        _jour(C)

func _process(_d) -> bool:
    if _fait:
        return true
    _fait = true
    var C = root.get_node("Civilisation")
    var cons = C.construction
    var res = C.ressources
    var msgs := []
    C.besoins.evenement.connect(func(t): msgs.append(str(t)))
    cons.evenement.connect(func(t): msgs.append(str(t)))
    cons.batiments.append({"type": "grenier", "niveau": 1, "etat": 100})
    var g: int = cons.batiments.size() - 1

    print("--- Règle 2 : capacité selon l'état")
    var cap100: float = res.capacite("nourriture")
    cons.batiments[g]["etat"] = 60
    _t(is_equal_approx(res.capacite("nourriture"), cap100), "Usé (60) : capacité entière")
    cons.batiments[g]["etat"] = 30
    _t(is_equal_approx(res.capacite("nourriture"), cap100 - 500.0), "Fragile (30) : grenier à 50 % (-500 kg)")
    cons.batiments[g]["etat"] = 0
    _t(is_equal_approx(res.capacite("nourriture"), cap100 - 1000.0), "En ruine : grenier ne compte plus")
    var hutte := -1
    for i in cons.batiments.size():
        if cons.batiments[i]["type"] == "hutte":
            hutte = i
            break
    var loge: float = cons.effet_total("logement")
    cons.batiments[hutte]["etat"] = 20
    _t(is_equal_approx(cons.effet_total("logement"), loge), "Hutte fragile : logement entier")
    cons.batiments[hutte]["etat"] = 100

    print("--- Règle 1 : ordre de paiement et suspension")
    cons.batiments[g]["etat"] = 100
    var ordre: Array = cons.ordre_paiement()
    _t(int(ordre[0]) == g, "le grenier est payé en premier par défaut")
    # Bois pour le grenier seulement (3 kg) : les huttes ne sont pas payées.
    res.stocks["bois"] = 3.0
    var etats := []
    for b in cons.batiments:
        etats.append(int(b["etat"]))
    cons.mois_passe(res)
    _t(int(cons.batiments[g]["etat"]) == 100 and float(res.stocks["bois"]) < 0.01, "grenier payé (bois 3 -> 0)")
    _t(int(cons.batiments[hutte]["etat"]) == int(etats[hutte]) - 20, "hutte impayée : -20")
    cons.deplacer_type("hutte", -1)
    cons.deplacer_type("hutte", -1)
    _t(cons.ordre_types()[0] == "hutte", "le joueur peut mettre les huttes en tête")
    cons.ordre_entretien = []
    cons.basculer_suspension(g)
    res.stocks["bois"] = 500.0
    var e_sans: float = cons.entretien_mois()
    cons.mois_passe(res)
    _t(int(cons.batiments[g]["etat"]) == 80, "grenier suspendu : -20 malgré le bois")
    cons.basculer_suspension(g)
    _t(cons.entretien_mois() > e_sans, "suspension levée : l'entretien compte de nouveau")

    print("--- Règle 5 : la ruine ne revient pas avec l'entretien ; réparation par chantier")
    cons.batiments[g]["etat"] = 0
    res.stocks["bois"] = 500.0
    cons.mois_passe(res)
    _t(int(cons.batiments[g]["etat"]) == 0, "en ruine : l'entretien seul ne la relève pas")
    var rep: Dictionary = cons.cout_reparation(g)
    _t(int(rep["cout"]["bois"]) == 45 and int(rep["travail"]) == 12, "coût : 45 kg de bois, 12 jours (30 %)")
    var b0: float = float(res.stocks["bois"])
    cons.chantiers.clear()
    var r: String = cons.lancer_reparation(g, res)
    _t(r == "" and is_equal_approx(float(res.stocks["bois"]), b0 - 45.0), "réparation lancée, 45 kg de bois payés")
    _t(cons.chantiers.size() == 1 and bool(cons.chantiers[0].get("reparation", false)), "elle passe par la file des chantiers")
    _t(cons.lancer_reparation(g, res) != "", "pas deux réparations du même bâtiment")
    cons.jour_passe(5.0)
    _t(int(cons.batiments[g]["etat"]) == 0, "5 jours de travail : pas encore fini")
    cons.jour_passe(7.0)
    _t(int(cons.batiments[g]["etat"]) == 20 and cons.chantiers.is_empty(), "12 jours de travail : état 20 (Fragile)")

    print("--- Règle 3 : perte de 10 % de l'excédent par jour")
    cons.batiments[g]["etat"] = 100
    var ajout: float = res.capacite("nourriture") - 50.0 - res.total_aliments()    # grenier plein ou presque
    res.aliments["fonio_sauvage"] = float(res.aliments.get("fonio_sauvage", 0.0)) + ajout / res.facteur("fonio_sauvage")
    res.stocks["nourriture"] = res.total_aliments()
    var stock0: float = res.total_aliments()
    cons.batiments[g]["etat"] = 0     # le grenier tombe : la capacité baisse d'un coup
    var cap: float = res.capacite("nourriture")
    var exc0: float = stock0 - cap
    print("   stock %.1f, capacité %.1f, excédent %.1f" % [stock0, cap, exc0])
    _jour(C)
    var exc1: float = res.total_aliments() - cap
    print("   après 1 jour : excédent %.1f" % exc1)
    _t(exc0 > 0.0 and exc1 > 0.5 * exc0, "pas de perte d'un coup (il reste plus de la moitié de l'excédent)")
    _t(exc1 < exc0, "l'excédent diminue")
    for i in 30:
        _jour(C)
    _t(res.total_aliments() - cap < 0.1 * exc0, "en un mois, l'excédent a presque disparu")
    # Eau : la production ne fait pas grossir l'excédent.
    res.stocks["eau"] = res.capacite("eau") + 200.0
    var e_avant: float = float(res.stocks["eau"])
    _jour(C)
    _t(float(res.stocks["eau"]) < e_avant and float(res.stocks["eau"]) > res.capacite("eau"), "eau au-dessus de la capacité : baisse progressive, pas de coupure")

    print("--- Règle 4 : prévision à J-10")
    msgs.clear()
    res.stocks["bois"] = 0.0
    res.hist_prod_bois = [0.0, 0.0, 0.0]
    var p: Dictionary = cons.prevision_entretien(res, 10)
    _t(float(p["manque"]) > 0.0 and is_equal_approx(float(p["entretien"]), cons.entretien_mois()), "bois à zéro : manque prévu")
    res.stocks["bois"] = 1000.0
    p = cons.prevision_entretien(res, 10)
    _t(float(p["manque"]) == 0.0, "bois abondant : rien ne manque")
    var postes_bat: int = int(C.population.postes.get("bâtisseur", 0))
    C.population.postes["bâtisseur"] = 0
    C.population.repartir(C.temps.jour_total)
    _jusqu_au_jour_du_mois(C, 15)
    res.stocks["bois"] = 0.0
    _jusqu_au_jour_du_mois(C, 21)
    var vu := false
    for t in msgs:
        if t.find("Le Premier ministre prévient") >= 0:
            vu = true
    _t(vu, "alerte du Premier ministre au 20e jour du mois")
    C.population.postes["bâtisseur"] = postes_bat
    C.population.repartir(C.temps.jour_total)

    print("--- Règle 4 : deux déficits distincts (entretien / bois en général)")
    var bats_sv: Array = cons.batiments.duplicate(true)
    # a) Tous les bâtiments en ruine : entretien nul, aucun déficit d'entretien, même sans bois.
    for b in cons.batiments:
        b["etat"] = 0
    res.stocks["bois"] = 0.0
    res.hist_prod_bois = [0.0]
    res.bois_brule_jour = 8.0
    p = cons.prevision_entretien(res, 10)
    _t(is_zero_approx(float(p["entretien"])) and is_zero_approx(float(p["manque"])), "tout en ruine : entretien 0, déficit d'entretien 0 (déficit général %.0f kg à part)" % float(p["manque_general"]))
    # b) Entretien 14 kg, 8 kg de bois disponibles à la fin du mois : déficit annoncé 6 kg.
    cons.batiments = [{"type": "hutte", "niveau": 1, "etat": 100}, {"type": "hutte", "niveau": 1, "etat": 100}, {"type": "hutte", "niveau": 1, "etat": 100}, {"type": "grenier", "niveau": 2, "etat": 100}, {"type": "grenier", "niveau": 1, "etat": 100}]
    res.stocks["bois"] = 8.0
    res.bois_brule_jour = 0.0
    res.hist_prod_bois = [0.0]
    p = cons.prevision_entretien(res, 10)
    print("   entretien %.1f, bois prévu %.1f, déficit %.1f" % [float(p["entretien"]), float(p["prevu"]), float(p["manque"])])
    _t(is_equal_approx(float(p["entretien"]), 14.0), "entretien du mois : 14 kg")
    _t(is_equal_approx(float(p["manque"]), 6.0), "8 kg disponibles : déficit annoncé 6 kg")
    # c) Le bois baisse (feux > production) mais l'entretien reste couvert : aucune alerte.
    res.stocks["bois"] = 400.0
    res.bois_brule_jour = 30.0
    res.hist_prod_bois = [10.0]
    p = cons.prevision_entretien(res, 10)
    _t(is_zero_approx(float(p["manque"])), "entretien couvert : pas d'alerte d'entretien (prévu %.0f kg)" % float(p["prevu"]))
    res.stocks["bois"] = 50.0
    p = cons.prevision_entretien(res, 10)
    _t(float(p["manque_general"]) > 0.0 and is_equal_approx(float(p["manque"]), float(p["entretien"])), "bois en général négatif : déficit général à part, déficit d'entretien limité à l'entretien")
    cons.batiments = bats_sv

    print("--- Règle 6 : le PM du joueur propose, il ne lance pas")
    cons.batiments[g]["etat"] = 0
    cons.chantiers.clear()
    msgs.clear()
    res.stocks["bois"] = 1000.0
    _jusqu_au_jour_du_mois(C, 0)
    _jour(C)
    _jusqu_au_jour_du_mois(C, 0)
    var propose := false
    for t in msgs:
        if t.find("propose de réparer") >= 0:
            propose = true
    _t(propose, "proposition de réparation dans les messages")
    var lance := false
    for c in cons.chantiers:
        if bool(c.get("reparation", false)):
            lance = true
    _t(not lance, "aucune réparation lancée sans le joueur")

    print("--- Règle 6 : un clan de l'ordinateur répare seul (3 conditions + exception causale)")
    var v = C.voisins[0]
    v.construction.chantiers.clear()
    v.construction.batiments.append({"type": "grenier", "niveau": 1, "etat": 0})
    v.ressources.stocks["bois"] = 10.0
    _t(not v.construction.reparation_auto(v.ressources, {"bloque": false, "causes": []}), "pas assez de bois : pas de réparation")
    v.ressources.stocks["bois"] = 400.0
    _t(not v.construction.reparation_auto(v.ressources, {"bloque": true, "causes": []}), "crise indépendante : pas de réparation")
    _t(v.construction.reparation_auto(v.ressources, {"bloque": false, "causes": []}), "bois suffisant, pas de crise : réparation lancée")
    _t(not v.construction.reparation_auto(v.ressources, {"bloque": false, "causes": []}), "une seule réparation à la fois")
    # Exception causale : tout le stockage est en ruine, la réserve de nourriture est basse.
    v.construction.chantiers.clear()
    for b in v.construction.batiments:
        b["etat"] = 0
    v.ressources.stocks["bois"] = 400.0
    v.ressources.aliments = {"fonio_sauvage": 5.0 / v.ressources.facteur("fonio_sauvage")}
    v.ressources.stocks["nourriture"] = v.ressources.total_aliments()
    v.besoins._contexte(v.population, v.ressources, v.construction, C.temps.jour_total, C.temps.saison_des_pluies(), false)
    var cr: Dictionary = v.besoins.crise_reparation()
    print("   crise : %s ; capacité %.0f kg pour %.1f kg/jour" % [str(cr), v.ressources.capacite("nourriture"), v.besoins._conso("nourriture")])
    _t(cr["causes"].has("nourriture") and not bool(cr["bloque"]), "crise causée par la capacité perdue : reconnue")
    _t(v.construction.reparation_auto(v.ressources, cr), "la ruine qui cause la crise est réparée malgré la crise")
    var repare_stocke := false
    for c in v.construction.chantiers:
        if bool(c.get("reparation", false)) and v.construction._stocke_une(int(c["index"]), ["nourriture"]):
            repare_stocke = true
    _t(repare_stocke, "le bâtiment réparé stocke bien la nourriture")
    # Crise indépendante : capacité intacte, réserve basse.
    v.construction.chantiers.clear()
    for b in v.construction.batiments:
        b["etat"] = 100
    v.construction.batiments.append({"type": "hutte", "niveau": 1, "etat": 0})
    v.besoins._contexte(v.population, v.ressources, v.construction, C.temps.jour_total, C.temps.saison_des_pluies(), false)
    cr = v.besoins.crise_reparation()
    _t(bool(cr["bloque"]), "capacité intacte : la crise ne vient pas de la ruine, réparation bloquée")
    _t(not v.construction.reparation_auto(v.ressources, cr), "donc pas de réparation")

    print("--- Règle 4 bis : le Premier ministre réagit à l'alerte J-10")
    var B = C.besoins
    var pop = C.population
    cons.chantiers.clear()
    for b in cons.batiments:
        b["etat"] = 100
        b.erase("suspendu")
    # Situation : aucun bâtisseur, et juste assez de bois pour brûler 10 jours plus l'entretien moins 15 kg.
    var mise_en_place := func():
        _jusqu_au_jour_du_mois(C, 19)
        pop.postes["bâtisseur"] = 0
        pop.repartir(C.temps.jour_total)
        res.hist_prod_bois = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        var brule0 := 0.0
        for h in pop.habitants:
            brule0 += float((res.CONSO_ENFANT if pop.age(h, C.temps.jour_total) < 14 else res.CONSO_ADULTE)["bois"])
        res.stocks["bois"] = brule0 * 11.0 + cons.entretien_mois() - 15.0
        for b in cons.batiments:
            b["etat"] = 100
    # Témoin : mode conseil (le PM ne fait que prévenir).
    B.mode = "conseil"
    mise_en_place.call()
    _jusqu_au_jour_du_mois(C, 0)
    var impaye_temoin := false
    for b in cons.batiments:
        if int(b["etat"]) < 100:
            impaye_temoin = true
    print("   témoin (conseil) : bâtisseurs %d, bois %.0f, impayé %s" % [pop.nombre("bâtisseur"), float(res.stocks["bois"]), str(impaye_temoin)])
    _t(impaye_temoin, "témoin sans réaction : l'entretien n'est pas payé")
    # Même situation, mode automatique.
    B.mode = "auto"
    mise_en_place.call()
    msgs.clear()
    var nb0: int = pop.nombre("bâtisseur")
    _jour(C)   # jour 20 : alerte et réaction
    var nb1: int = pop.nombre("bâtisseur")
    _jusqu_au_jour_du_mois(C, 0)
    var impaye := false
    for b in cons.batiments:
        if int(b["etat"]) < 100:
            impaye = true
    var texte := ""
    for t in msgs:
        if t.find("Le Premier ministre prévient") >= 0:
            texte = t
    print("   auto : bâtisseurs %d -> %d, bois %.0f ; message : %s" % [nb0, nb1, float(res.stocks["bois"]), texte])
    _t(nb1 == nb0 + 1, "le PM ajoute un bâtisseur au 20e jour")
    _t(not impaye, "avec la réaction, l'entretien est payé (impayé évité)")

    print("--- Règle 4 bis : le PM ne sacrifie pas l'eau ni la nourriture")
    mise_en_place.call()
    res.stocks["eau"] = 5.0
    res.aliments = {"fonio_sauvage": 2.0 / res.facteur("fonio_sauvage")}
    res.stocks["nourriture"] = res.total_aliments()
    var postes_avant: Dictionary = pop.postes.duplicate()
    B._contexte(pop, res, cons, C.temps.jour_total, C.temps.saison_des_pluies(), false)
    var tenue := {"eau": B._jours("eau", {}), "nourriture": B._jours("nourriture", {})}
    msgs.clear()
    var agi: bool = B.reagir_entretien(pop, res, cons, C.temps.jour_total, C.temps.saison_des_pluies(), false, cons.prevision_entretien(res, 10), 10)
    var sain := true
    if agi:
        for r2 in ["eau", "nourriture"]:
            if B._jours(r2, {}) < minf(float(tenue[r2]), B.SEUIL_VITAL_JOURS) - 0.01:
                sain = false
    print("   a agi : %s ; postes %s -> %s ; %s" % [str(agi), str(postes_avant), str(pop.postes), str(msgs)])
    _t(sain, "aucun déplacement qui réduit la tenue de l'eau ou de la nourriture")
    _t(agi or msgs.size() > 0, "s'il n'agit pas, il explique pourquoi")
    res.stocks["eau"] = 1000.0
    res.aliments = {"fonio_sauvage": 500.0 / res.facteur("fonio_sauvage")}
    res.stocks["nourriture"] = res.total_aliments()

    print("--- Règle 7 : le Premier ministre compte l'entretien dans le bois")
    C.besoins.actualiser(C.population, res, cons, C.temps.jour_total, C.temps.saison_des_pluies(), false)
    var avec: float = C.besoins._conso_humaine("bois")
    var e30: float = cons.entretien_mois() / 30.0
    var sans := 0.0
    for h in C.population.habitants:
        sans += float((res.CONSO_ENFANT if C.population.age(h, C.temps.jour_total) < 14 else res.CONSO_ADULTE)["bois"])
    _t(absf(avec - sans - e30) < 0.001, "besoin de bois = habitants + entretien / 30 (%.2f + %.2f)" % [sans, e30])

    print("--- Sauvegarde et rechargement")
    cons.basculer_suspension(hutte)
    cons.deplacer_type("jarres", -1)
    cons.chantiers.clear()
    cons.batiments[g]["etat"] = 0
    res.stocks["bois"] = 500.0
    cons.lancer_reparation(g, res)
    var d: Dictionary = JSON.parse_string(JSON.stringify(cons.vers_dict()))
    var C2 = load("res://scripts/core/construction.gd").new()
    C2.depuis_dict(d)
    _t(bool(C2.batiments[hutte].get("suspendu", false)), "suspension conservée")
    _t(C2.ordre_types()[0] == "jarres", "ordre d'entretien conservé")
    var rep_ok := false
    for c in C2.chantiers:
        if bool(c.get("reparation", false)) and int(c["index"]) == g:
            rep_ok = true
    _t(rep_ok, "réparation en cours conservée")
    _t(int(C2.batiments[g]["etat"]) == int(cons.batiments[g]["etat"]), "état conservé")

    print("RESULTAT : %d OK, %d KO" % [_ok, _ko])
    quit(1 if _ko > 0 else 0)
    return true
