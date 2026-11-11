extends PanelContainer

# Écran du chef (v0.3.18) : le centre de décision du joueur.
# 1. Le chef et le conseil (nommer, renouveler le mandat).
# 2. Les alertes du chef et ses propositions (appliquer ou ignorer).
# 3. Les expériences possibles (lancer un essai) et l'expérience en cours.
# 4. L'agriculture : terre de l'île, champs, semis, semences.
# 5. Le mode de gestion : le joueur décide, ou le chef applique seul.
# Rien n'est calculé ici : l'écran lit le moteur et appelle ses fonctions.

var boite: VBoxContainer
var message: Label
var _attente := 0.0

func _ready() -> void:
    anchor_left = 0.05
    anchor_right = 0.95
    anchor_top = 0.12
    anchor_bottom = 0.95
    var defil := ScrollContainer.new()
    add_child(defil)
    boite = VBoxContainer.new()
    boite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    boite.add_theme_constant_override("separation", 10)
    defil.add_child(boite)

func _label(t: String, taille := 24) -> Label:
    var l := Label.new()
    l.text = t
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.add_theme_font_size_override("font_size", taille)
    return l

func _bouton(t: String, actif: bool, action: Callable) -> Button:
    var b := Button.new()
    b.text = t
    b.disabled = not actif
    b.add_theme_font_size_override("font_size", 24)
    b.pressed.connect(action)
    return b

func _ligne(enfants: Array) -> HBoxContainer:
    var l := HBoxContainer.new()
    l.add_theme_constant_override("separation", 10)
    for e in enfants:
        l.add_child(e)
    if enfants.size() > 0:
        enfants[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return l

# Résultat d'une action : "" = réussi, sinon la raison du refus.
func _faire(resultat: String, succes: String) -> void:
    remplir()
    message.text = succes if resultat == "" else resultat

func remplir() -> void:
    for c in boite.get_children():
        c.queue_free()
    var C = Civilisation
    var jour: int = C.temps.jour_total
    boite.add_child(_label("Conseil du dirigeant", 36))
    message = _label("", 24)
    message.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
    boite.add_child(message)
    _section_ascension(C)
    _section_conseil(C, jour)
    _section_alertes(C)
    _section_experiences(C, jour)
    _section_territoire(C)
    _section_agriculture(C, jour)
    _section_clotures(C)
    _section_routes(C)
    _section_sous_sol(C)
    _section_flotte(C)
    _section_archipel(C)
    _section_budget(C)
    boite.add_child(_label(C.finances.texte(C), 21))
    _section_force(C, jour)
    _section_raids(C)
    _section_sante(C, jour)
    _section_gouvernement(C, jour)
    _section_rapport(C, jour)
    _section_mode(C)

# ---------- Ascension : décisions, défis, époque ----------

func _section_ascension(C) -> void:
    var df = C.defis
    for i in df.decisions.size():
        var d: Dictionary = df.decisions[i]
        boite.add_child(_label("DÉCISION : %s" % d["titre"], 28))
        boite.add_child(_label("%s (réponse avant %d jours)" % [d["texte"], int(d["fin"]) - C.temps.jour_total], 21))
        var enfants: Array = [_label("", 21)]
        for o in d["options"].size():
            var di: int = i
            var oi: int = o
            enfants.append(_bouton(d["options"][o], true, func(): _faire(C.choisir_decision(di, oi), "Décision prise.")))
        boite.add_child(_ligne(enfants))
    boite.add_child(_label("Époque : %s — renommée %d" % [df.EPOQUES[df.epoque], df.renommee], 30))
    if df.epoque < df.EPOQUES.size() - 1:
        var l: PackedStringArray = []
        for c in df.conditions(C):
            l.append(("[x] " if c[1] else "[  ] ") + c[0])
        boite.add_child(_label("Pour atteindre « %s » :\n%s" % [df.EPOQUES[df.epoque + 1], "\n".join(l)], 22))
    for d in df.defis:
        boite.add_child(_label("Défi (%s terme) : %s — encore %d jours" % [d["horizon"], d["texte"], int(d["fin"]) - C.temps.jour_total], 22))
    var rangs: PackedStringArray = []
    var i := 1
    for r in C.classement():
        rangs.append("%d. %s — %s, %d habitants, réputation %d/100 (%s)" % [i, r["nom"], df.EPOQUES[int(r["epoque"])], int(r["habitants"]), int(r["reputation"]), C.niveau_reputation(int(r["reputation"]))])
        i += 1
    boite.add_child(_label("Clans connus de l'archipel (visitez-les pour les connaître) :\n%s" % "\n".join(rangs), 21))
    boite.add_child(_label(C.heros.texte(), 21))
    boite.add_child(_label(C.histoire.texte(15), 20))

# ---------- 1. Chef et conseil ----------

func _section_conseil(C, jour: int) -> void:
    var cons = C.conseil
    boite.add_child(_label("Conseil des cinq", 30))
    var chef: Dictionary = cons.habitant(C.population, cons.chef_id)
    if chef.is_empty():
        boite.add_child(_label("Pas de Premier ministre : nommez un membre du conseil."))
    else:
        var t := "Premier ministre : %s %s" % [chef["prenom"], chef["nom"]]
        t += " (intérim)" if cons.interim else " — mandat : encore %.1f an(s)" % cons.annees_restantes(jour)
        t += " — confiance du clan : %d %%" % int(cons.confiance)
        boite.add_child(_ligne([_label(t), _bouton("Renouveler", not cons.interim and jour >= cons.mandat_fin - 360,
            func(): _faire(cons.renouveler(C.population, jour), "Mandat renouvelé pour 5 ans."))]))
    for mid in cons.membres:
        var h: Dictionary = cons.habitant(C.population, mid)
        if h.is_empty():
            continue
        var n: Dictionary = cons.notes(h, C.population, jour)
        var t := "%s %s, %d ans — gestion %d, intelligence %d, influence %d" % [h["prenom"], h["nom"], C.population.age(h, jour), int(n["gestion"]), int(n["intelligence"]), int(n["influence"])]
        var sv: Array = []
        for k in h.get("savoirs", {}):
            if float(h["savoirs"][k]) >= 15.0:
                sv.append([str(k), int(h["savoirs"][k])])
        sv.sort_custom(func(a, b): return a[1] > b[1])
        var st: PackedStringArray = []
        for x in sv.slice(0, 4):
            st.append("%s %d" % [x[0], x[1]])
        if not st.is_empty():
            t += "\n   Savoirs : " + ", ".join(st)
        boite.add_child(_ligne([_label(t, 22), _bouton("Nommer Premier ministre", mid != cons.chef_id or cons.interim,
            func(): _faire(cons.nommer(mid, C.population, jour), "Nouveau Premier ministre nommé."))]))

# ---------- 2. Alertes et propositions ----------

func _section_alertes(C) -> void:
    boite.add_child(_label("Alertes du Premier ministre", 30))
    var chef: Dictionary = C.conseil.habitant(C.population, C.conseil.chef_id)
    var prenom: String = chef.get("prenom", "Le conseil")
    if C.chef.alertes.is_empty():
        boite.add_child(_label("Aucune alerte : le clan tient ses besoins."))
    for a in C.chef.alertes:
        var cle: String = a["cle"]
        boite.add_child(_ligne([_label(C.chef.texte_alerte(a, prenom)), _bouton("Ignorer", true,
            func(): _faire(C.ignorer_alerte(cle), "Alerte ignorée."))]))
        var props: Array = a.get("propositions", [])
        for i in props.size():
            var p: Dictionary = props[i]
            var t := "   → %s : %s. Risque : %s" % [p["cout"], p["effet"], p["risque"]]
            boite.add_child(_ligne([_label(t, 21), _bouton("Appliquer", true,
                func(): _faire(C.appliquer_proposition(cle, i), "Proposition appliquée."))]))

# ---------- 3. Expériences ----------

func _section_experiences(C, jour: int) -> void:
    var d = C.decouvertes
    boite.add_child(_label("Expériences", 30))
    if not d.en_cours.is_empty():
        boite.add_child(_label("En cours : %s — résultat dans %d jours." % [d.definitions[d.en_cours["id"]]["nom"], int(d.en_cours["fin"]) - jour]))
    var possibles: Array = C.experiences_possibles()
    if possibles.is_empty():
        boite.add_child(_label("Aucune expérience possible. Le clan cherche quand une difficulté se fait sentir (pression d'au moins 20) et quand les conditions sont réunies.", 21))
    for id in possibles:
        var t := "%s : %d jours, %d personne(s) retirée(s) de leur métier, réussite %d %%" % [d.definitions[id]["nom"], d._duree(id), d._nb(id), int(d.chance(id, C.population, C.pression) * 100)]
        if int(d.essais.get(id, 0)) > 0:
            t += " (%d échec(s) déjà)" % int(d.essais[id])
        boite.add_child(_ligne([_label(t, 22), _bouton("Lancer", d.en_cours.is_empty(),
            func(): _faire(C.lancer_experience(id), "Expérience lancée."))]))
    var p: Dictionary = C.pression.niveaux
    var parts: PackedStringArray = []
    for k in p:
        if float(p[k]) >= 1.0:
            parts.append("%s %d" % [k, int(p[k])])
    boite.add_child(_label("Pression des difficultés : %s" % (", ".join(parts) if parts.size() > 0 else "aucune"), 21))

# ---------- Territoire ----------

func _section_territoire(C) -> void:
    var t = C.territoire
    boite.add_child(_label("Territoire", 30))
    boite.add_child(_label("%d parcelle(s) de 100 ha : %d ha à nous, dont %d ha cultivables. L'île fait %d ha." % [t.possedees.size(), int(t.surface_possedee()), int(t.cultivable_possede()), int(float(t.ile.get("surface_ha", 0)))], 22))
    for p in t.meilleures(3):
        var x: int = p.x
        var z: int = p.y
        var txt := "Parcelle (%d, %d) : %d ha cultivables, à %.1f km du village — %s" % [x, z, int(t.cultivable(p)), t._distance(p), t.texte_cout(t.cout(p))]
        boite.add_child(_ligne([_label(txt, 21), _bouton("Acquérir", true, func(): _faire(C.acquerir_parcelle(x, z), "Parcelle acquise."))]))

# ---------- 4. Agriculture ----------

func _section_agriculture(C, jour: int) -> void:
    var ag = C.agriculture
    boite.add_child(_label("Agriculture — %s" % ag.ile.get("nom", ""), 30))
    if not C.decouvertes.connait("agriculture"):
        boite.add_child(_label("Le clan ne connaît pas encore l'agriculture.", 22))
        return
    boite.add_child(_label("Terre cultivée : %.1f ha — terre libre : %s ha — cultivateurs : %d" % [ag.surface_cultivee(), str(int(ag.terre_libre())), C.population.nombre("cultivateur")], 22))
    boite.add_child(_label("Où ouvrir un champ ? (meilleur sol d'abord)", 22))
    for k in ag.parcelles_libres().slice(0, 4):
        var p: Vector2i = C.territoire.pos(k)
        var libre: float = ag.libre_parcelle(k)
        var cle: String = k
        boite.add_child(_ligne([_label("Parcelle (%d, %d) : sol %d %%, %d ha libres" % [p.x, p.y, int(C.territoire.qualite(p) * 100), int(libre)], 21),
            _bouton("+ 1 ha", libre >= 1.0, func(): _faire(C.creer_champ(1.0, cle), "Champ créé : il faut maintenant le défricher.")),
            _bouton("+ 5 ha", libre >= 5.0, func(): _faire(C.creer_champ(5.0, cle), "Champ créé : il faut maintenant le défricher."))]))
    for c in ag.champs:
        var etat := "récolté, prêt à semer" if c["etat"] == "recolte" else "défriché, prêt à semer"
        if not bool(c["defriche"]):
            etat = "défrichage %d %%" % int(100.0 * float(c.get("defrichage", 0.0)) / (20.0 * float(c["ha"])))
        elif c["etat"] == "seme":
            etat = "%s semé, récolte dans %d jours" % [ag.cultures[c["culture"]]["nom"], int(ag.cultures[c["culture"]]["cycle"]) - int(c["jours"])]
        var enfants: Array = [_label("Champ %d : %.1f ha, fertilité %d %%, %s" % [int(c["id"]), float(c["ha"]), int(float(c["fertilite"]) * 100), etat], 22)]
        if c["etat"] != "seme" and bool(c["defriche"]):
            for culture in ag.cultures:
                var dec: String = str(ag.cultures[culture].get("decouverte", ""))
                if dec != "" and not C.decouvertes.connait(dec):
                    continue
                var id: int = int(c["id"])
                enfants.append(_bouton("Semer %s" % ag.cultures[culture]["nom"].to_lower(), true,
                    func(): _faire(C.semer(id, culture), "Champ semé.")))
        var idc: int = int(c["id"])
        enfants.append(_bouton("Amender (cendres)", true, func(): _faire(C.amender_champ(idc), "Champ amendé : fertilité en hausse.")))
        enfants.append(_bouton("Fumier (%d kg)" % int(ag.FUMIER_HA * float(c["ha"])), true, func(): _faire(C.amender_fumier(idc), "Fumier épandu : fertilité en hausse.")))
        boite.add_child(_ligne(enfants))
    var sem: PackedStringArray = []
    for s in ag.semences:
        if float(ag.semences[s]) >= 0.1:
            sem.append("%s %.0f kg" % [s, float(ag.semences[s])])
    boite.add_child(_label("Semences mises de côté : %s" % (", ".join(sem) if sem.size() > 0 else "aucune"), 21))

# ---------- Clôtures (libre choix : sécurité et décor) ----------

func _section_clotures(C) -> void:
    var cl = C.clotures
    boite.add_child(_label("Clôtures", 30))
    boite.add_child(_label("Au choix : rien n'oblige à clôturer. Une clôture protège (un champ ouvert perd 12 % de sa récolte) et chaque porte est un passage, mais aussi un point faible.", 21))
    var cibles: Array = ["village"]
    for c in C.agriculture.champs:
        cibles.append("champ_%d" % int(c["id"]))
    for cible in cibles:
        var e: Dictionary = cl.enceintes.get(cible, {})
        var nom: String = "Village" if cible == "village" else "Champ %s" % cible.trim_prefix("champ_")
        var t := "%s : pas de clôture" % nom
        if not e.is_empty():
            t = "%s : %s, %d porte(s), état %d %%, protection %d %%" % [nom, cl.NIVEAUX[e["niveau"]]["nom"], int(e["portes"]), int(float(e["etat"]) * 100), int(cl.protection(cible) * 100)]
            if float(e["travail_restant"]) > 0.0:
                t += " — en construction (%d jours de travail)" % int(ceil(float(e["travail_restant"])))
        var enfants: Array = [_label(t, 22)]
        var m: float = cl.longueur(cible, C.agriculture, C.construction)
        for niv in cl.ORDRE:
            if e.get("niveau", "") == niv:
                continue
            var n: String = niv
            var cb: String = cible
            enfants.append(_bouton("%s (%s)" % [cl.NIVEAUX[niv]["nom"], cl.texte_cout(cl.cout(niv, m))], true, func(): _faire(C.cloturer(cb, n), "Clôture commencée.")))
        if not e.is_empty():
            var cb2: String = cible
            enfants.append(_bouton("+ porte", true, func(): _faire(C.changer_portes(cb2, 1), "Passage ouvert.")))
            enfants.append(_bouton("- porte", int(e["portes"]) > 0, func(): _faire(C.changer_portes(cb2, -1), "Passage fermé.")))
        boite.add_child(_ligne(enfants))

# ---------- Routes (un réseau qui part du village) ----------

func _regler_guerisseurs(C, jour: int, n: int) -> void:
    C.population.fixer_guerisseurs(jour, n)
    remplir()

func _section_sante(C, jour: int) -> void:
    var ng: int = C.population.nb_guerisseurs()
    var mg: int = C.population.max_guerisseurs(jour)
    var plantes: float = C.ressources.quantite("plantes_medicinales")
    boite.add_child(_label("Santé", 30))
    boite.add_child(_label("Guérisseurs : %d (maximum %d). Plantes médicinales en réserve : %.1f kg. Un guérisseur soigne jusqu'à %d malades par jour (%.2f kg de plantes chacun) et consacre 25 %% de son temps aux soins. Infirmerie : %d places, soins +%d %%." % [ng, mg, plantes, C.population.SOINS_PAR_GUERISSEUR, C.population.PLANTES_PAR_SOIN, int(C.construction.effet_total("soin_places")), int(minf(1.0, C.construction.effet_total("soin_bonus")) * 100.0)], 21))
    boite.add_child(_ligne([_label("Nombre de guérisseurs", 22), _bouton("−", ng > 0, func(): _regler_guerisseurs(C, jour, ng - 1)), _bouton("+", ng < mg, func(): _regler_guerisseurs(C, jour, ng + 1))]))

func _regler_protecteurs(C, jour: int, n: int) -> void:
    C.guerre.fixer_protecteurs(C.population, jour, n)
    remplir()

func _section_force(C, jour: int) -> void:
    boite.add_child(_label("Force militaire", 30))
    boite.add_child(_label(C.guerre.texte(C.population, C.equipement, C.clotures, C.ressources, jour), 22))
    var np: int = C.guerre.nb_protecteurs(C.population)
    var mp: int = C.guerre.max_protecteurs(C.population, jour)
    boite.add_child(_label("Protecteurs : %d (maximum %d). Un protecteur consacre 25 %% de son temps à garder le clan : sa production baisse, son combat progresse." % [np, mp], 21))
    boite.add_child(_ligne([_label("Nombre de protecteurs", 22), _bouton("−", np > 0, func(): _regler_protecteurs(C, jour, np - 1)), _bouton("+", np < mp, func(): _regler_protecteurs(C, jour, np + 1))]))

func _section_raids(C) -> void:
    boite.add_child(_label("Raids", 30))
    boite.add_child(_label("Un raid envoie un petit groupe par bateau prendre des vivres à un clan visité. Il consomme des vivres, expose vos guerriers et détériore les relations. Pas de conquête.", 21))
    var t: String = C.raids.texte("joueur")
    if t != "":
        boite.add_child(_label(t, 21))
    var att: Dictionary = C.raids.en_attente()
    if not att.is_empty():
        if att["dst"] == "joueur":
            boite.add_child(_label("Des guerriers ont débarqué. Que faites-nous ?", 24))
            boite.add_child(_ligne([_bouton("Résister", true, func(): _faire(C.repondre_raid("resister"), "Nous résistons.")), _bouton("Offrir une rançon", true, func(): _faire(C.repondre_raid("offrir"), "Rançon acceptée, ils repartent."))]))
        else:
            boite.add_child(_label("Le clan offre %d kg de vivres pour éviter le combat." % int(att["offre"]), 24))
            boite.add_child(_ligne([_bouton("Accepter l'offre", true, func(): _faire(C.repondre_raid("accepter"), "Offre acceptée.")), _bouton("Attaquer", true, func(): _faire(C.repondre_raid("attaquer"), "Nous attaquons."))]))
    for v in C.voisins:
        if not v.vivant() or int(C.expeditions.connues.get(v.agriculture.ile_id, 0)) < 2:
            continue
        var e: Dictionary = C.evaluer_raid(v.id)
        var txt := "%s : %s" % [v.nom, ("raid possible — %d guerriers, force %.1f contre %.1f estimée, %d jours, butin attendu %d kg pour %d kg de vivres" % [int(e["n"]), float(e["force"]), float(e["defense_estimee"]), int(e["jours"]), int(e["butin"]), int(e["vivres"])]) if bool(e["possible"]) else str(e["raison"])]
        var vid: String = v.id
        boite.add_child(_ligne([_label(txt, 21), _bouton("Raid", bool(e["possible"]), func(): _faire(C.lancer_raid(vid), "Le raid est parti."))]))

func _section_gouvernement(C, jour: int) -> void:
    var g = C.gouvernement
    boite.add_child(_label("Gouvernement", 30))
    boite.add_child(_label("Maturité : %s (%s). Aucun ministère constitué : ce tableau montre les systèmes qui existent déjà. Une fonction confiée prend une part du temps de travail de la personne (pas de bonus pour l'instant)." % [g.maturite()["nom"], g.maturite()["texte"]], 21))
    for s in g.tableau(C, jour):
        boite.add_child(_label(str(s["nom"]), 24))
        var lignes: PackedStringArray = []
        for i in s["indicateurs"]:
            lignes.append("%s : %s" % [i[0], i[1]])
        boite.add_child(_label("\n".join(lignes), 21))
        if not s["besoins"].is_empty():
            boite.add_child(_label("À surveiller : " + " ".join(s["besoins"]), 21))
        boite.add_child(_label("Rattaché : " + ", ".join(s["rattaches"]), 21))
        _postes_secteur(C, str(s["id"]), jour)
    boite.add_child(_label("Secteurs prévus : " + ", ".join(g.prevus()), 21))

func _lancer_mission(C, did: String, jour: int) -> void:
    var r: String = C.missions.lancer(C, jour)
    if r == "":
        C.rapports.decider(did, "acceptee", jour)
    _faire(r, "Mission lancée.")

# ---------- Rapport du Premier ministre : information et décisions, sans exécution ----------

func _section_rapport(C, jour: int) -> void:
    var R = C.rapports
    boite.add_child(_label("Rapport du Premier ministre", 30))
    var r: Dictionary = R.dernier
    if r.is_empty():
        boite.add_child(_label("Pas encore de rapport : le premier arrive à la fin du mois.", 21))
    else:
        var par: String = ("établi par " + str(r["pm"])) if str(r["pm"]) != "" else "établi sans Premier ministre en fonction"
        boite.add_child(_label("Rapport du jour %d (%s)." % [int(r["jour"]), par], 21))
        if str(r["alerte"]) != "":
            boite.add_child(_label("ALERTE : " + str(r["alerte"]) + ".", 24))
        boite.add_child(_label("Résultats (réalisations mesurées)", 24))
        for s in r["resultats"]:
            var t: String = "%s\n   " % R.NOMS[s["secteur"]] + "\n   ".join(PackedStringArray(s["lignes"]))
            if float(s["taux"]) >= 0.0:
                t += "\n   Taux d'exécution : %d %%" % int(round(float(s["taux"]) * 100.0))
            else:
                t += "\n   Taux d'exécution : indisponible (%s)" % str(s["raison"])
            boite.add_child(_label(t, 21))
        if not r["blocages"].is_empty():
            boite.add_child(_label("Blocages : " + " ; ".join(PackedStringArray(r["blocages"])), 21))
    boite.add_child(_label("Demandes (accepter ou refuser enregistre seulement votre décision : rien n'est exécuté)", 24))
    if R.demandes.is_empty():
        boite.add_child(_label("Aucune demande en attente.", 21))
    var M = C.missions
    for d in R.demandes:
        var did: String = str(d["id"])
        if did == "defense_armes":
            var dv: Dictionary = M.devis(C, jour)
            boite.add_child(_label("%s : %s" % [R.NOMS[d["secteur"]], d["texte"]], 21))
            if dv["possible"]:
                boite.add_child(_label(M.texte_devis(dv), 21))
            else:
                boite.add_child(_label("Mission impossible pour l'instant : " + str(dv["raison"]), 21))
            boite.add_child(_ligne([_bouton("Lancer la mission", bool(dv["possible"]), func(): _lancer_mission(C, did, jour)),
                _bouton("Refuser", true, func(): _faire(R.decider(did, "refusee", jour), "Décision enregistrée."))]))
            continue
        var note: String = M.note_impossible(did)
        boite.add_child(_ligne([_label("%s : %s (coût : %s)%s" % [R.NOMS[d["secteur"]], d["texte"], d["cout"], (" Note : " + note) if note != "" else ""], 21),
            _bouton("Accepter", true, func(): _faire(R.decider(did, "acceptee", jour), "Décision enregistrée : aucune exécution à ce stade.")),
            _bouton("Refuser", true, func(): _faire(R.decider(did, "refusee", jour), "Décision enregistrée."))]))
    var pr: String = M.texte_actuelle(jour)
    boite.add_child(_label("Projets : " + (pr if pr != "" else "aucune mission en cours."), 21))
    if not M.terminees.is_empty():
        boite.add_child(_label("Dernière mission : " + M.texte_resultat(M.terminees.back()), 21))
    var dos: String = M.texte_dossier(C)
    if dos != "":
        boite.add_child(_label(dos, 21))
    var dl: PackedStringArray = []
    for i in range(R.decisions.size() - 1, maxi(-1, R.decisions.size() - 6), -1):
        var x: Dictionary = R.decisions[i]
        dl.append("Jour %d, %s : %s (%s)" % [int(x["jour"]), x["choix"], x["texte"], R.NOMS[x["secteur"]]])
    boite.add_child(_label("Décisions : " + ("\n".join(dl) if not dl.is_empty() else "aucune pour l'instant."), 21))

# ---------- Nominations : le jeu propose, le joueur choisit ----------

var _nom := {}   # nomination en cours : {"sid", "poste", "mode", "filtres"}

func _postes_secteur(C, sid: String, jour: int) -> void:
    var g = C.gouvernement
    for poste in ["titulaire", "adjoint"]:
        var d: Dictionary = g.postes_def()[poste]
        var id: int = g.titulaire_de(sid, poste)
        var sp: String = sid
        var po: String = poste
        var nom: String = str(d["nom"]).capitalize()
        if id >= 0:
            var h: Dictionary = C.conseil.habitant(C.population, id)
            if h.is_empty():
                continue
            boite.add_child(_ligne([_label("%s : %s %s (%d %% de son temps)" % [nom, h["prenom"], h["nom"], int(float(d["temps"]) * 100.0)], 21), _bouton("Relever", true, func(): _relever(C, sp, po))]))
        else:
            boite.add_child(_ligne([_label("%s : vacant" % nom, 21),
                _bouton("Proposition", true, func(): _ouvrir(C, sp, po, "auto")),
                _bouton("Concours", true, func(): _ouvrir(C, sp, po, "concours"))]))
            if _nom.get("sid", "") == sid and _nom.get("poste", "") == poste:
                _detail_nomination(C, jour)

func _relever(C, sid: String, poste: String) -> void:
    _nom = {}
    _faire(C.gouvernement.revoquer(sid, poste, C), "Fonction retirée.")

func _ouvrir(C, sid: String, poste: String, mode: String) -> void:
    if _nom.get("sid", "") == sid and _nom.get("poste", "") == poste and _nom.get("mode", "") == mode:
        _nom = {}
    else:
        _nom = {"sid": sid, "poste": poste, "mode": mode, "filtres": C.gouvernement.filtres_defaut()}
    remplir()

func _nommer(C, sid: String, poste: String, id: int, jour: int) -> void:
    var r: String = C.gouvernement.nommer(sid, poste, id, C, jour)
    if r == "":
        _nom = {}
    _faire(r, "Nomination faite.")

func _ligne_candidat(g, cand: Dictionary) -> String:
    var v: Dictionary = cand["v"]
    var t := "%s, %d ans, %s — compétence %d, expérience %d, loyauté %d, santé %d, temps libre %d %%, ancienneté %d an(s)" % [cand["nom"], int(cand["age"]), cand["metier"], int(v["competence"]), int(v["experience"]), int(v["loyaute"]), int(v["sante"]), int(v["disponibilite"]), int(v["anciennete"])]
    if bool(cand["vital"]):
        t += " — attention : seul(e) de son métier (poste vital)"
    return t

func _detail_nomination(C, jour: int) -> void:
    var g = C.gouvernement
    var sid: String = _nom["sid"]
    var poste: String = _nom["poste"]
    if _nom["mode"] == "auto":
        var p: Dictionary = g.proposer(sid, poste, C, jour)
        if p.is_empty():
            boite.add_child(_label("Aucun candidat convenable pour l'instant. Essayez un concours.", 21))
            return
        var pid: int = int(p["id"])
        boite.add_child(_ligne([_label("Proposition : " + _ligne_candidat(g, p), 21),
            _bouton("Nommer", true, func(): _nommer(C, sid, poste, pid, jour)),
            _bouton("Refuser", true, func(): g.refuser(sid, poste, pid); remplir())]))
        return
    var f: Dictionary = _nom["filtres"]
    boite.add_child(_label("Filtres du concours (un filtre désactivé n'écarte personne) :", 21))
    for k in g.CRITERES:
        var kk: String = k
        var pas: int = 1 if k == "anciennete" else 10
        var fk: Dictionary = f[k]
        var t := "%s %s ≥ %d" % ["[x]" if bool(fk["actif"]) else "[  ]", g.NOMS_CRITERES[k], int(fk["seuil"])]
        boite.add_child(_ligne([_label(t, 21),
            _bouton("Oui/Non", true, func(): f[kk]["actif"] = not bool(f[kk]["actif"]); remplir()),
            _bouton("-", int(fk["seuil"]) > 0, func(): f[kk]["seuil"] = maxi(0, int(f[kk]["seuil"]) - pas); remplir()),
            _bouton("+", true, func(): f[kk]["seuil"] = int(f[kk]["seuil"]) + pas; remplir())]))
    var l: Array = g.candidats(sid, poste, C, jour, f)
    boite.add_child(_label("%d candidat(s) admissible(s), classés par compétence (les critères sont affichés séparément, vous choisissez) :" % l.size(), 21))
    for i in mini(l.size(), 6):
        var cid: int = int(l[i]["id"])
        boite.add_child(_ligne([_label(_ligne_candidat(g, l[i]), 20), _bouton("Nommer", true, func(): _nommer(C, sid, poste, cid, jour))]))
    if l.size() > 6:
        boite.add_child(_label("... et %d autre(s) : durcissez les filtres pour les voir." % (l.size() - 6), 20))

func _section_budget(C) -> void:
    boite.add_child(_label("Budget du clan", 30))
    boite.add_child(_label(C.budget.texte(), 22))
    boite.add_child(_label("L'impôt prélève une part du surplus produit (jamais la nourriture ni l'eau) pour les chantiers et l'entretien. Au-delà de 10 %, le travail rend moins. Maximum : 30 %.", 21))
    var enfants: Array = []
    for t in [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30]:
        var tt: float = t
        enfants.append(_bouton("%d %%" % int(round(t * 100.0)), absf(C.budget.taux - t) > 0.001, func(): _faire(C.budget.regler(tt), "Impôt réglé.")))
    boite.add_child(_ligne(enfants))

func _section_routes(C) -> void:
    var ro = C.routes
    boite.add_child(_label("Routes", 30))
    boite.add_child(_label("Un champ hors du village, un puits ou une retenue ne fonctionnent que reliés par la route. Une route vers l'eau ou la forêt rend le travail plus rapide.", 21))
    var dests: Array = ro.destinations().keys()
    # Parcelles acquises : celles déjà reliées, et celles qu'on peut relier maintenant.
    for k in C.territoire.possedees:
        if k == C.territoire.cle(C.territoire.centre):
            continue
        if ro.troncons.has("parcelle_" + k) or ro._parcelle_atteignable(k, C.territoire):
            dests.append("parcelle_" + k)
    for dest in dests:
        var t: Dictionary = ro.troncons.get(dest, {})
        var txt := "Vers %s (%.1f km) : " % [ro.nom(dest), ro.km(dest)]
        if t.is_empty():
            txt += "pas de route"
        else:
            txt += ro.DEF[t["niveau"]]["nom"]
            if float(t["travail_restant"]) > 0.0:
                txt += " — travaux : %d jours de travail" % int(ceil(float(t["travail_restant"])))
            else:
                txt += " — travail +%d %%" % int(ro.bonus(dest) * 100)
        var enfants: Array = [_label(txt, 22)]
        var actuel: int = ro.NIVEAUX.find(t.get("niveau", "")) if not t.is_empty() else -1
        if actuel + 1 < ro.NIVEAUX.size():
            var niv: String = ro.NIVEAUX[actuel + 1]
            var de: String = dest
            enfants.append(_bouton("%s (%s)" % [ro.DEF[niv]["nom"], ro.texte_cout(ro.cout(dest, niv))], true, func(): _faire(C.construire_route(de, niv), "Travaux commencés.")))
        boite.add_child(_ligne(enfants))

# ---------- Sous-sol : prospecter, ouvrir, extraire ----------

func _section_sous_sol(C) -> void:
    var g = C.gisements
    boite.add_child(_label("Sous-sol de l'île", 30))
    var t := "Gisements à découvrir : %s." % ("peut-être encore" if g.a_decouvrir() > 0 else "aucun")
    if not g.prospection.is_empty():
        t += " Prospection en cours (%d jours)." % (int(g.prospection["fin"]) - C.temps.jour_total)
    boite.add_child(_ligne([_label(t, 21), _bouton("Prospecter (1 adulte, 15 jours)", g.prospection.is_empty() and g.a_decouvrir() > 0, func(): _faire(C.prospecter(), "Prospection lancée."))]))
    for typ in g.connus:
        var info: Dictionary = g.connus[typ]
        var txt := "%s — teneur %d %%, déjà extrait : %d kg" % [g.TYPES[typ]["nom"], int(g.teneur(typ) * 100), int(float(info["extrait"]))]
        var enfants: Array = [_label(txt, 21)]
        if not bool(info["ouvert"]):
            var ty: String = typ
            enfants.append(_bouton("Ouvrir (50 bois, 20 pierres, route vers %s)" % C.routes.nom(g.TYPES[typ]["route"]), true, func(): _faire(C.ouvrir_site(ty), "Site ouvert.")))
        else:
            txt += " — ouvert, mineurs : %d" % C.population.nombre("mineur")
            enfants[0].text = txt
        boite.add_child(_ligne(enfants))

# ---------- Port et flotte ----------

func _section_flotte(C) -> void:
    var f = C.flotte
    var jour: int = C.temps.jour_total
    boite.add_child(_label("Port et flotte", 30))
    var np: int = f.niveau_port(C.construction, C.routes)
    var t := "Port : %s — places pour %d bateau(x). Construisez le port dans « Construire » ; il ne sert que relié par la route." % [["aucun (1 pirogue sur la plage)", "débarcadère", "port aménagé", "grand port"][np], f.places(C.construction, C.routes)]
    boite.add_child(_label(t, 21))
    for b in f.bateaux:
        var etat := "au port" if int(b["occupe_jusqu"]) < jour else "en mer (%s), retour dans %d jours" % [b["mission"], int(b["occupe_jusqu"]) - jour]
        boite.add_child(_label("%s n° %d : %s, état %d %%" % [f.TYPES[b["type"]]["nom"], int(b["id"]), etat, int(float(b["etat"]) * 100)], 21))
    if f.en_travaux():
        boite.add_child(_label("Chantier naval : %s, encore %d jours de travail." % [f.TYPES[f.chantier["type"]]["nom"], int(ceil(float(f.chantier["travail_restant"])))], 21))
    var enfants: Array = [_label("Construire un bateau :", 21)]
    for typ in f.TYPES:
        var ty: String = typ
        var d: Dictionary = f.TYPES[typ]
        enfants.append(_bouton("%s (%d pers., %d kg, %s)" % [d["nom"], int(d["personnes"]), int(d["kg"]), f._texte(d["cout"])], true, func(): _faire(C.construire_bateau(ty), "Chantier naval lancé.")))
    boite.add_child(_ligne(enfants))
    var ventes: Array = [_label("Vendre nos surplus (au clan connu qui paie le mieux) :", 21)]
    for prod in ["bois", "sel"] + C.ressources.aliments.keys() + C.ressources.objets.keys():
        var pr: String = prod
        var q: float = C.marche.disponible(C, pr, jour)
        if q >= 1.0 and C.marche.valeur_ref(pr) > 0.0:
            ventes.append(_bouton("%s (%d)" % [pr, int(q)], true, func(): _faire(C.vendre_surplus(pr), "Marchandise partie.")))
    if ventes.size() > 1:
        boite.add_child(_ligne(ventes))
    # Élevage (v0.3.36)
    boite.add_child(_label(C.elevage.texte(jour), 21))
    var ab: Array = [_label("Abattre :", 21)]
    for esp in C.elevage.especes:
        var e2: String = esp
        if C.elevage.nombre(e2) > 0:
            ab.append(_bouton("1 %s" % str(C.elevage.especes[e2]["nom"]).to_lower(), true, func(): _faire(C.abattre(e2), "Bête abattue.")))
    if ab.size() > 1:
        boite.add_child(_ligne(ab))
    var ac: Array = [_label("Acheter un couple :", 21)]
    for esp in C.elevage.especes:
        var e3: String = esp
        var vid: String = C.vendeur_animaux(e3)
        if vid != "":
            ac.append(_bouton("%s (%s, %d kg de grain)" % [str(C.elevage.especes[e3]["nom"]).to_lower(), C.voisin(vid).nom, int(C.PRIX_BETE[e3] * 2)], true, func(): _faire(C.acheter_animaux(e3), "Bétail acheté : il arrive par bateau.")))
    if ac.size() > 1:
        boite.add_child(_ligne(ac))

# ---------- Archipel : explorer, visiter, connaître les autres îles ----------

var _ile_vue := ""

func _section_archipel(C) -> void:
    var ex = C.expeditions
    boite.add_child(_label("Archipel", 30))
    if not ex.en_cours.is_empty():
        boite.add_child(_label("Expédition en mer (%s) : retour dans %d jours." % [ex.en_cours["type"], int(ex.en_cours["retour"]) - C.temps.jour_total], 22))
    boite.add_child(_ligne([_label("Partir vers l'inconnu (3 adultes, vivres, risques en mer) : 6 chances sur 10 de trouver une île.", 21),
        _bouton("Explorer", ex.en_cours.is_empty(), func(): _faire(C.lancer_expedition("exploration"), "Expédition partie."))]))
    var par_ile: Dictionary = C._clans_par_ile()
    var iles: Dictionary = C.agriculture.catalogue_iles()
    for id in iles:
        if id == C.ile_joueur or int(ex.connues.get(id, 0)) < 1:
            continue
        var t := "%s" % iles[id]["nom"]
        if par_ile.has(id):
            var cid: String = par_ile[id][0]
            t += " — %s, relation : %s (%d), %d visite(s)" % [par_ile[id][1].nom, C.diplomatie.etat("joueur", cid), int(C.diplomatie.relation("joueur", cid)["score"]), int(ex.visites.get(cid, {}).get("nb", 0))]
        t += " — %d jours de mer" % ex.jours_mer(C.ile_joueur, id)
        var i: String = id
        boite.add_child(_ligne([_label(t, 21),
            _bouton("Voir", true, func():
                _ile_vue = "" if _ile_vue == i else i
                remplir()),
            _bouton("Visiter", ex.en_cours.is_empty(), func(): _faire(C.lancer_expedition("visite", i), "Délégation partie."))]))
        if _ile_vue == id:
            boite.add_child(_label(ex.fiche(id, par_ile, C.temps.jour_total), 21))
    var obs: PackedStringArray = []
    for d in C.decouvertes.observees:
        obs.append("%s (niveau %.1f)" % [C.decouvertes.definitions[d]["nom"], float(C.decouvertes.observees[d])])
    boite.add_child(_label("Techniques observées chez les autres : %s" % (", ".join(obs) if obs.size() > 0 else "aucune"), 21))

# ---------- 5. Mode de gestion ----------

func _section_mode(C) -> void:
    var g = C.gouvernement
    var jour: int = C.temps.jour_total
    boite.add_child(_label("Délégations du Premier ministre", 30))
    boite.add_child(_label("Le Premier ministre conseille, vous décidez. Il n'agit seul que dans ce que vous lui déléguez, pour la durée choisie, et vous pouvez retirer la délégation à tout moment. Jamais de guerre, d'alliance, de loi ni d'impôt.", 21))
    for id in g.DELEGATIONS:
        var di: String = id
        var def: Dictionary = g.DELEGATIONS[id]
        boite.add_child(_ligne([_label("%s : %s" % [def["nom"], g.texte_delegation(id, jour)], 22),
            _bouton("1 an", true, func(): _faire(g.deleguer(di, 360, C, jour), "Délégation accordée.")),
            _bouton("5 ans", true, func(): _faire(g.deleguer(di, 1800, C, jour), "Délégation accordée.")),
            _bouton("Sans limite", true, func(): _faire(g.deleguer(di, -1, C, jour), "Délégation accordée.")),
            _bouton("Retirer", g.delegations.has(id), func(): _faire(g.retirer_delegation(di, C), "Délégation retirée."))]))
        boite.add_child(_label("Limites : " + str(def["limites"]), 19))

func _process(delta: float) -> void:
    if not visible:
        return
    _attente += delta
    if _attente >= 2.0:
        _attente = 0.0
        var m: String = message.text if message else ""
        remplir()
        message.text = m
