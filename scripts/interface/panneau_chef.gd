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
    boite.add_child(_label("Le chef", 36))
    message = _label("", 24)
    message.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
    boite.add_child(message)
    _section_conseil(C, jour)
    _section_alertes(C)
    _section_experiences(C, jour)
    _section_territoire(C)
    _section_agriculture(C, jour)
    _section_mode(C)

# ---------- 1. Chef et conseil ----------

func _section_conseil(C, jour: int) -> void:
    var cons = C.conseil
    boite.add_child(_label("Conseil des cinq", 30))
    var chef: Dictionary = cons.habitant(C.population, cons.chef_id)
    if chef.is_empty():
        boite.add_child(_label("Pas de chef : nommez un membre du conseil."))
    else:
        var t := "Chef : %s %s" % [chef["prenom"], chef["nom"]]
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
        boite.add_child(_ligne([_label(t, 22), _bouton("Nommer chef", mid != cons.chef_id or cons.interim,
            func(): _faire(cons.nommer(mid, C.population, jour), "Nouveau chef nommé."))]))

# ---------- 2. Alertes et propositions ----------

func _section_alertes(C) -> void:
    boite.add_child(_label("Alertes du chef", 30))
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
                var id: int = int(c["id"])
                enfants.append(_bouton("Semer %s" % ag.cultures[culture]["nom"].to_lower(), true,
                    func(): _faire(C.semer(id, culture), "Champ semé.")))
        var idc: int = int(c["id"])
        enfants.append(_bouton("Amender (cendres)", true, func(): _faire(C.amender_champ(idc), "Champ amendé : fertilité en hausse.")))
        boite.add_child(_ligne(enfants))
    var sem: PackedStringArray = []
    for s in ag.semences:
        if float(ag.semences[s]) >= 0.1:
            sem.append("%s %.0f kg" % [s, float(ag.semences[s])])
    boite.add_child(_label("Semences mises de côté : %s" % (", ".join(sem) if sem.size() > 0 else "aucune"), 21))

# ---------- 5. Mode de gestion ----------

func _section_mode(C) -> void:
    boite.add_child(_label("Gestion", 30))
    var auto: bool = C.besoins.mode == "auto"
    var t := "Mode actuel : %s" % ("le chef applique seul ses solutions" if auto else "le chef conseille, vous décidez")
    boite.add_child(_ligne([_label(t, 22), _bouton("Passer en %s" % ("conseil" if auto else "automatique"), true,
        func():
            C.besoins.mode = "conseil" if auto else "auto"
            _faire("", "Mode changé."))]))

func _process(delta: float) -> void:
    if not visible:
        return
    _attente += delta
    if _attente >= 2.0:
        _attente = 0.0
        var m: String = message.text if message else ""
        remplir()
        message.text = m
