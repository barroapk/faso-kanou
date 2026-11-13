extends SceneTree
# Danger du sel (D-2) : critères d'acceptation automatiques 1 à 14 (conception D-2).
# Lancer : godot --headless --path . --script res://tests/test_sel.gd
# (dans un dossier de sauvegarde neuf : XDG_DATA_HOME="$(mktemp -d)")
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

# Un clan sans production de sel : pas de pêcheur, pas de séchage, PM en conseil.
func _sans_production(C) -> void:
    C.besoins.mode = "conseil"
    for h in C.population.habitants:
        if h["metier"] in ["pêcheur", "sécheur", "mineur"]:
            C.population.changer_metier(h, "sans métier")
    C.population.postes.erase("pêcheur")
    C.population.postes.erase("sécheur")
    C.ressources.objets["sel_vegetal"] = 0.0
    C.ressources.hist_sel_prod = []
    C.ressources.hist_sel_sechage = []

func _besoin(C) -> float:
    return C.population.habitants.size() * C.ressources.SEL_PAR_PERSONNE

func _process(_d) -> bool:
    if _fait:
        return true
    _fait = true
    var C = root.get_node("Civilisation")
    var r = C.ressources
    var pop = C.population
    var msgs := []
    r.evenement.connect(func(t): msgs.append([C.temps.jour_total, str(t)]))
    C.besoins.evenement.connect(func(t): msgs.append([C.temps.jour_total, str(t)]))
    _sans_production(C)

    print("--- 1. Compteur")
    r.stocks["sel"] = 0.0
    r.jours_sans_sel = 0.0
    for i in 60:
        _jour(C)
    _t(is_equal_approx(r.jours_sans_sel, 60.0), "60 jours sans sel : compteur 60 (%.2f)" % r.jours_sans_sel)
    r.stocks["sel"] = 20.0
    _jour(C)
    _t(is_equal_approx(r.jours_sans_sel, 57.0), "puis 1 jour couvert : 57 (%.2f)" % r.jours_sans_sel)
    r.stocks["sel"] = 0.5 * _besoin(C)
    var avant: float = r.jours_sans_sel
    _jour(C)
    _t(absf(r.jours_sans_sel - avant + 1.0) < 0.02, "jour couvert à 50 %% : -1 (%.3f)" % (r.jours_sans_sel - avant))
    for cv in [[0.0, 1.0], [0.25, 0.0], [0.5, -1.0], [0.75, -2.0], [1.0, -3.0]]:
        r.jours_sans_sel = 100.0
        r.stocks["sel"] = float(cv[0]) * _besoin(C) + (0.000001 if float(cv[0]) >= 1.0 else 0.0)
        _jour(C)
        _t(absf(r.jours_sans_sel - 100.0 - float(cv[1])) < 0.02, "couverture %d %% : variation %+.0f (%.3f)" % [int(float(cv[0]) * 100.0), float(cv[1]), r.jours_sans_sel - 100.0])
    r.stocks["sel"] = 0.0
    r.jours_sans_sel = 269.6
    _jour(C)
    _jour(C)
    _t(is_equal_approx(r.jours_sans_sel, 270.0), "plafonné à 270")
    r.stocks["sel"] = 20.0
    r.jours_sans_sel = 2.0
    _jour(C)
    _t(r.jours_sans_sel == 0.0, "jamais sous 0")

    print("--- 2. Santé inchangée pour un même compteur")
    var pareil := true
    for c in 300:
        var ancien: int = 100 - clampi((c - 30) / 6, 0, 40)
        if pop.plafond_sante(float(c)) != ancien:
            pareil = false
    _t(pareil, "plafond identique à 95b3380 pour les compteurs 0 à 299")

    print("--- 3. Pas de mort par le sel seul")
    var copie: Array = pop.habitants.duplicate(true)
    var n0: int = pop.habitants.size()
    for h in pop.habitants:
        h["sante"] = 100
    for i in 360:
        pop.jour_passe(false, false, 270.0, C.temps.jour_total)
    var min_sante := 100
    for h in pop.habitants:
        min_sante = mini(min_sante, int(h["sante"]))
    _t(pop.habitants.size() == n0 and min_sante == 60, "360 jours au compteur 270, nourri et abreuvé : %d/%d vivants, santé min %d" % [pop.habitants.size(), n0, min_sante])
    pop.habitants = copie

    print("--- 4. Rétablissement")
    r.stocks["sel"] = 20.0
    r.jours_sans_sel = 120.0
    var jours := 0
    while r.plafond_sel() < 100 and jours < 100:
        _jour(C)
        jours += 1
    _t(jours <= 29, "après 120 jours de manque, plafond à 100 en %d jours (≤ 29)" % jours)

    print("--- 5 et 6. Prévision du délai et alerte avant effet")
    r.jours_sans_sel = 40.0
    _t(r.delai_sel(pop) == 0.0, "compteur 40 : santé déjà touchée, pas de délai")
    r.jours_sans_sel = 0.0
    r.hist_sel_prod = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    _t(r.delai_sel(pop) >= r.SEL_SANS_LIMITE, "production ≥ consommation : sans limite")
    r.hist_sel_prod = []
    r.hist_sel_sechage = []
    r.jours_sans_sel = 30.0
    r.stocks["sel"] = 100.0 * r.sel_conso(pop)
    _t(absf(r.delai_sel(pop) - 136.0) < 0.01, "compteur 30, 100 jours, sans production : 136 jours (%.1f)" % r.delai_sel(pop))
    var prevu: float = r.delai_sel(pop)
    var debut: int = C.temps.jour_total
    msgs.clear()
    r.alerte_sel = 0
    var j_effet := -1
    while j_effet < 0 and C.temps.jour_total - debut < 200:
        _jour(C)
        if r.plafond_sel() < 100:
            j_effet = C.temps.jour_total - debut
    _t(j_effet > 0 and absf(j_effet - prevu) <= 5.0, "simulation : effet au jour %d, prévu %.0f (écart ≤ 5)" % [j_effet, prevu])
    var j_alerte := -1
    var niveaux := {}
    for m in msgs:
        var t: String = m[1]
        if t.begins_with("Le sel baisse") and j_alerte < 0:
            j_alerte = int(m[0]) - debut
        for cle in ["Le sel baisse", "Pénurie de sel", "Le manque de sel limite"]:
            if t.begins_with(cle):
                niveaux[cle] = int(niveaux.get(cle, 0)) + 1
    _t(j_alerte >= 0 and j_alerte < j_effet, "alerte de niveau 1 au jour %d, avant l'effet (jour %d)" % [j_alerte, j_effet])
    _t(niveaux.get("Le sel baisse", 0) == 1 and niveaux.get("Pénurie de sel", 0) == 1 and niveaux.get("Le manque de sel limite", 0) == 1, "chaque message une seule fois : %s" % str(niveaux))
    # Un clan qui grandit : 20 habitants de plus, l'alerte part toujours avant l'effet.
    r.stocks["sel"] = 20.0
    while r.jours_sans_sel > 0.0 or r.plafond_sel() < 100:
        _jour(C)
    _jour(C)
    var avant_croissance: Array = pop.habitants.duplicate(true)
    var id_avant: int = pop.prochain_id
    for i in 20:
        var h: Dictionary = pop.habitants[i % pop.habitants.size()].duplicate(true)
        h["id"] = pop.prochain_id
        pop.prochain_id += 1
        pop.habitants.append(h)
    r.stocks["sel"] = 60.0 * r.sel_conso(pop)
    r.alerte_sel = 0
    msgs.clear()
    debut = C.temps.jour_total
    j_effet = -1
    while j_effet < 0 and C.temps.jour_total - debut < 200:
        _jour(C)
        if r.plafond_sel() < 100:
            j_effet = C.temps.jour_total - debut
    j_alerte = -1
    for m in msgs:
        if str(m[1]).begins_with("Le sel baisse") and j_alerte < 0:
            j_alerte = int(m[0]) - debut
    _t(j_alerte >= 0 and j_alerte < j_effet, "clan agrandi (%d habitants) : alerte au jour %d, effet au jour %d" % [pop.habitants.size(), j_alerte, j_effet])
    pop.habitants = avant_croissance
    pop.prochain_id = id_avant
    r.aliments["fonio_sauvage"] = float(r.aliments.get("fonio_sauvage", 0.0)) + 200.0
    r.stocks["eau"] = 500.0
    r.jours_sans_sel = 0.0
    r.alerte_sel = 0

    print("--- 7. Une seule formule")
    _t(is_equal_approx(C.marche._jours(C, "sel", C.temps.jour_total), r.autonomie_sel(pop)), "le marché lit la même autonomie que l'affichage")

    print("--- 8. Approvisionnement régulier ou par lots (même quantité)")
    var fin := {}
    for mode in ["régulier", "lots"]:
        r.jours_sans_sel = 120.0
        r.stocks["sel"] = 0.0
        var total := 0.0
        var b: float = _besoin(C)
        var pop0: int = C.population.habitants.size()
        var fige: Array = C.population.habitants.duplicate()
        var id_fige: int = C.population.prochain_id
        for i in 60:
            if mode == "régulier":
                r.stocks["sel"] = 0.5 * b
                total += 0.5 * b
            elif i % 10 == 0:
                r.stocks["sel"] = 5.0 * b + 0.000001
                total += 5.0 * b
            _jour(C)
            C.population.habitants = fige.duplicate()
            C.population.prochain_id = id_fige
        fin[mode] = [r.jours_sans_sel, r.plafond_sel(), total]
        print("      (%s : habitants %d -> %d)" % [mode, pop0, C.population.habitants.size()])
    print("      régulier : compteur %.1f, plafond %d, sel fourni %.2f kg" % fin["régulier"])
    print("      par lots : compteur %.1f, plafond %d, sel fourni %.2f kg" % fin["lots"])
    _t(absf(float(fin["régulier"][0]) - float(fin["lots"][0])) < 0.5 and absf(float(fin["régulier"][2]) - float(fin["lots"][2])) < 0.5, "même quantité, même compteur final (écart %.2f)" % absf(float(fin["régulier"][0]) - float(fin["lots"][0])))
    r.jours_sans_sel = 0.0
    r.stocks["sel"] = 0.0
    r.alerte_sel = 0

    print("--- 9. Rien de gratuit : un achat retire chez le vendeur ce qu'il ajoute chez l'acheteur")
    var a = C.voisins[0]
    var b = C.voisins[1]
    a.ressources.stocks["sel"] = 0.0
    b.ressources.stocks["sel"] = 200.0
    var vend_avant: float = b.ressources.stocks["sel"]
    var dv: Dictionary = C.marche.devis(a, b, "sel", 5.0, C.temps.jour_total)
    var res_achat: String = C.marche.conclure(a, a.id, b, b.id, dv, C.temps.jour_total, null) if dv.get("possible", false) else str(dv.get("raison"))
    _t(res_achat == "", "achat conclu (%s)" % res_achat)
    var q: float = float(dv.get("quantite", 0.0))
    _t(absf(vend_avant - float(b.ressources.stocks["sel"]) - q) < 0.0001, "vendeur : %.2f kg retirés" % (vend_avant - float(b.ressources.stocks["sel"])))
    _t(absf(C.caravanes.en_attente(a.id, "sel") - q) < 0.0001, "acheteur : %.2f kg en route, pas encore dans le stock (%.2f)" % [C.caravanes.en_attente(a.id, "sel"), float(a.ressources.stocks["sel"])])
    var arrive := 0
    while C.caravanes.en_attente(a.id, "sel") > 0.0 and arrive < 60:
        _jour(C)
        arrive += 1
    _t(C.caravanes.en_attente(a.id, "sel") == 0.0, "livré en %d jours" % arrive)

    print("--- 10, 11, 12. Premier ministre")
    _sans_production(C)
    C.besoins.mode = "auto"
    C.besoins.dernier_changement = -9999
    r.jours_sans_sel = 0.0
    r.stocks["sel"] = 30.0 * r.sel_conso(pop)
    # Toutes les personnes d'un métier protégées : le PM n'y touche pas.
    var proteges := {}
    for h in pop.habitants:
        if h["metier"] == "cueilleur":
            h["protege_jusqu"] = C.temps.jour_total + 90
            proteges[int(h["id"])] = h["metier"]
    var porteurs_avant: int = pop.nombre("porteur d'eau")
    var p_avant: int = int(pop.postes.get("pêcheur", 0))
    msgs.clear()
    C.besoins.mois_passe(pop, r, C.construction, C.temps.jour_total, C.temps.saison_des_pluies(), false)
    pop.repartir(C.temps.jour_total)
    var sel_msgs := msgs.filter(func(m): return str(m[1]).begins_with("Sel :"))
    _t(sel_msgs.size() == 1, "un message du PM sur le sel : %s" % (str(sel_msgs[0][1]) if sel_msgs.size() > 0 else "aucun"))
    var touche_protege := false
    for h in pop.habitants:
        if proteges.has(int(h["id"])) and h["metier"] != proteges[int(h["id"])]:
            touche_protege = true
    _t(not touche_protege, "aucune personne protégée déplacée")
    _t(pop.nombre("porteur d'eau") >= mini(porteurs_avant, 1), "dernier porteur d'eau gardé")
    var p_apres: int = int(pop.postes.get("pêcheur", 0))
    print("      pêcheurs : %d → %d" % [p_avant, p_apres])
    # Gain trop faible : un séchage énorme rend un pêcheur inutile ; le PM ne déplace personne.
    C.besoins.dernier_changement = -9999
    r.hist_sel_sechage = [5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0]
    var postes_avant: Dictionary = pop.postes.duplicate()
    msgs.clear()
    C.besoins.mois_passe(pop, r, C.construction, C.temps.jour_total, C.temps.saison_des_pluies(), false)
    sel_msgs = msgs.filter(func(m): return str(m[1]).begins_with("Sel :"))
    _t(int(pop.postes.get("pêcheur", 0)) == int(postes_avant.get("pêcheur", 0)) and sel_msgs.size() == 1 and str(sel_msgs[0][1]).find("gain trop faible") >= 0, "gain trop faible : personne ne bouge, et le PM le dit")
    r.hist_sel_sechage = []
    # Gain utile : sur une île plus riche en sel, avec 60 jours de stock, un pêcheur repousse
    # le délai au-delà de 120 jours ; le PM l'ajoute, sans toucher aux personnes protégées.
    var richesse_avant: Dictionary = r.richesse.duplicate()
    r.richesse["sel"] = 1.0
    r.richesse["poisson"] = 1.0
    r.stocks["sel"] = 60.0 * r.sel_conso(pop)
    C.besoins.dernier_changement = -9999
    var p0: int = int(pop.postes.get("pêcheur", 0))
    msgs.clear()
    C.besoins.mois_passe(pop, r, C.construction, C.temps.jour_total, C.temps.saison_des_pluies(), false)
    pop.repartir(C.temps.jour_total)
    sel_msgs = msgs.filter(func(m): return str(m[1]).begins_with("Sel :"))
    print("      ", str(sel_msgs[0][1]) if sel_msgs.size() > 0 else "aucun message")
    _t(int(pop.postes.get("pêcheur", 0)) == p0 + 1, "gain utile : le PM ajoute un pêcheur (%d → %d)" % [p0, int(pop.postes.get("pêcheur", 0))])
    touche_protege = false
    for h in pop.habitants:
        if proteges.has(int(h["id"])) and h["metier"] != proteges[int(h["id"])]:
            touche_protege = true
    _t(not touche_protege, "toujours aucune personne protégée déplacée")
    msgs.clear()
    C.besoins.mois_passe(pop, r, C.construction, C.temps.jour_total, C.temps.saison_des_pluies(), false)
    sel_msgs = msgs.filter(func(m): return str(m[1]).begins_with("Sel :"))
    _t(int(pop.postes.get("pêcheur", 0)) == p0 + 1, "le mois suivant, délai de 60 jours : pas de second pêcheur")
    r.richesse = richesse_avant
    # Sel végétal : jamais deux fournées en même temps.
    r.ajouter("canari", 1.0, "test")
    r.objets["cendres"] = 50.0
    C.recettes.commandes = []
    C.besoins._contexte(pop, r, C.construction, C.temps.jour_total, false, false)
    for h in pop.habitants:
        if h["metier"] == "cueilleur":
            h.erase("protege_jusqu")
            pop.changer_metier(h, "sans métier")
            break
    print("      ", C.besoins._sel_vegetal(), " / ", C.besoins._sel_vegetal())
    var nb: int = C.recettes.commandes.filter(func(c): return c["recette"] == "sel_vegetal").size()
    _t(nb == 1, "une fournée lancée, pas de seconde en même temps (%d)" % nb)

    print("--- 13. Achats automatiques de l'ordinateur")
    for v in C.voisins:
        v.ressources.stocks["sel"] = 200.0
    var acheteur = C.voisins[2]
    acheteur.ressources.stocks["sel"] = 0.0
    C.caravanes.en_route = []
    for v in C.voisins:
        for bt in v.flotte.bateaux:
            bt["occupe_jusqu"] = 0
    C.marche.mois_passe(C._clans(), C._ids_voisins(), C.temps.jour_total, C.diplomatie)
    var attendu1: float = C.caravanes.en_attente(acheteur.id, "sel")
    C.marche.mois_passe(C._clans(), C._ids_voisins(), C.temps.jour_total, C.diplomatie)
    var attendu2: float = C.caravanes.en_attente(acheteur.id, "sel")
    _t(attendu1 > 0.0, "un clan sans sel achète (%.2f kg en route)" % attendu1)
    _t(is_equal_approx(attendu1, attendu2), "pas de nouvel achat tant que la livraison est en route")
    var hostile: Dictionary = C.marche.devis(acheteur, C.voisins[3], "sel", 5.0, C.temps.jour_total, "", "hostilité")
    _t(not hostile.get("possible", false), "jamais avec un clan hostile")

    print("--- 14. Sauvegarde")
    r.jours_sans_sel = 57.5
    r.alerte_sel = 2
    r.hist_sel_prod = [0.01, 0.02]
    var d: Dictionary = r.vers_dict()
    var r2 = load("res://scripts/core/ressources.gd").new()
    r2.construction = C.construction
    r2.depuis_dict(JSON.parse_string(JSON.stringify(d)))
    _t(is_equal_approx(r2.jours_sans_sel, 57.5) and r2.alerte_sel == 2 and r2.hist_sel_prod.size() == 2, "compteur décimal, alerte et historique relus")
    var r3 = load("res://scripts/core/ressources.gd").new()
    r3.construction = C.construction
    r3.depuis_dict({"jours_sans_sel": 40})
    _t(is_equal_approx(r3.jours_sans_sel, 40.0) and r3.alerte_sel == 0, "ancienne sauvegarde : compteur entier relu")

    print("Bilan : %d OK, %d KO" % [_ok, _ko])
    quit(1 if _ko > 0 else 0)
    return true
