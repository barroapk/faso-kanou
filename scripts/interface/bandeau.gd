extends CanvasLayer

var etiquette_date: Label
var etiquette_pop: Label
var etiquette_res: Label
var message: Label
var temps_message := 0.0
var panneau: PanelContainer
var liste: VBoxContainer
var panneau_fin: PanelContainer
var panneau_travail: PanelContainer
var panneau_construction: PanelContainer
var panneau_chef: PanelContainer

func _ready() -> void:
    var barre := HBoxContainer.new()
    barre.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    barre.alignment = BoxContainer.ALIGNMENT_END
    barre.offset_top = 20
    barre.offset_right = -20
    barre.add_theme_constant_override("separation", 16)
    add_child(barre)

    etiquette_pop = _etiquette(barre)
    etiquette_date = _etiquette(barre)

    var clan := Button.new()
    clan.text = "Clan"
    clan.add_theme_font_size_override("font_size", 30)
    clan.pressed.connect(_basculer_panneau)
    barre.add_child(clan)

    var chef := Button.new()
    chef.text = "Chef"
    chef.add_theme_font_size_override("font_size", 30)
    chef.pressed.connect(_basculer_chef)
    barre.add_child(chef)

    var travail := Button.new()
    travail.text = "Travail"
    travail.add_theme_font_size_override("font_size", 30)
    travail.pressed.connect(_basculer_travail)
    barre.add_child(travail)

    var construire := Button.new()
    construire.text = "Construire"
    construire.add_theme_font_size_override("font_size", 30)
    construire.pressed.connect(_basculer_construction)
    barre.add_child(construire)

    var groupe := ButtonGroup.new()
    var noms := ["Pause", "Jouer"]
    for i in noms.size():
        var b := Button.new()
        b.text = noms[i]
        b.toggle_mode = true
        b.button_group = groupe
        b.button_pressed = i == Civilisation.temps.vitesse
        b.add_theme_font_size_override("font_size", 30)
        b.pressed.connect(_changer_vitesse.bind(i))
        barre.add_child(b)

    etiquette_res = Label.new()
    etiquette_res.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    etiquette_res.offset_top = 90
    etiquette_res.offset_right = -20
    etiquette_res.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    etiquette_res.add_theme_font_size_override("font_size", 30)
    add_child(etiquette_res)

    message = Label.new()
    message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    message.offset_top = -90
    message.offset_bottom = -30
    message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    message.add_theme_font_size_override("font_size", 34)
    add_child(message)

    panneau = PanelContainer.new()
    panneau.anchor_left = 0.15
    panneau.anchor_right = 0.85
    panneau.anchor_top = 0.15
    panneau.anchor_bottom = 0.85
    panneau.visible = false
    add_child(panneau)
    var defil := ScrollContainer.new()
    panneau.add_child(defil)
    liste = VBoxContainer.new()
    liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    defil.add_child(liste)

    Civilisation.population.naissance.connect(func(h): _afficher_message("Naissance : %s %s" % [h["prenom"], h["nom"]]))
    Civilisation.population.deces.connect(func(h): _afficher_message("Décès : %s %s" % [h["prenom"], h["nom"]]))
    Civilisation.ressources.penurie.connect(func(r): _afficher_message("Pénurie de %s !" % r))
    _creer_panneau_fin()
    panneau_travail = preload("res://scripts/interface/panneau_travail.gd").new()
    panneau_travail.visible = false
    add_child(panneau_travail)
    panneau_construction = preload("res://scripts/interface/panneau_construction.gd").new()
    panneau_construction.visible = false
    add_child(panneau_construction)
    panneau_chef = preload("res://scripts/interface/panneau_chef.gd").new()
    panneau_chef.visible = false
    add_child(panneau_chef)
    Civilisation.construction.evenement.connect(_afficher_message)
    Civilisation.besoins.evenement.connect(_afficher_message)
    Civilisation.conseil.evenement.connect(_afficher_message)
    Civilisation.chef.evenement.connect(_afficher_message)
    Civilisation.migration.evenement.connect(_afficher_message)
    Civilisation.recettes.evenement.connect(_afficher_message)
    Civilisation.equipement.evenement.connect(_afficher_message)
    Civilisation.decouvertes.evenement.connect(_afficher_message)
    Civilisation.diplomatie.evenement.connect(_afficher_message)
    Civilisation.marche.evenement.connect(_afficher_message)
    Civilisation.caravanes.evenement.connect(_afficher_message)
    Civilisation.agriculture.evenement.connect(_afficher_message)
    Civilisation.pression.evenement.connect(_afficher_message)
    Civilisation.expeditions.evenement.connect(_afficher_message)
    Civilisation.territoire.evenement.connect(_afficher_message)
    Civilisation.clotures.evenement.connect(_afficher_message)
    Civilisation.routes.evenement.connect(_afficher_message)
    if not Civilisation.ile_confirmee:
        add_child.call_deferred(preload("res://scripts/interface/choix_ile.gd").new())
    for c in Civilisation.voisins:
        c.evenement.connect(_afficher_message)

func _etiquette(parent: Control) -> Label:
    var l := Label.new()
    l.add_theme_font_size_override("font_size", 32)
    parent.add_child(l)
    return l

func _changer_vitesse(i: int) -> void:
    Civilisation.temps.vitesse = i

func _afficher_message(texte: String) -> void:
    message.text = texte
    temps_message = 5.0
    if panneau.visible:
        _remplir_liste()

func _basculer_panneau() -> void:
    panneau.visible = not panneau.visible
    if panneau.visible:
        _remplir_liste()

func _remplir_liste() -> void:
    for ligne in liste.get_children():
        ligne.queue_free()
    var pop = Civilisation.population
    var jour: int = Civilisation.temps.jour_total
    var choix_possibles: Array = pop.metiers_choisis()
    for h in pop.habitants:
        var ligne := HBoxContainer.new()
        var l := Label.new()
        l.text = "%s %s · %d ans · santé %d · compétence %d" % [h["prenom"], h["nom"], pop.age(h, jour), int(h["sante"]), int(h["competence"])]
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        l.add_theme_font_size_override("font_size", 28)
        ligne.add_child(l)
        if pop.peut_changer(h, jour):
            var choix := OptionButton.new()
            choix.add_theme_font_size_override("font_size", 28)
            var actuel := -1
            for i in choix_possibles.size():
                var m: String = choix_possibles[i]
                choix.add_item(pop.nom_metier({"metier": m, "sexe": h["sexe"]}), i)
                if m == h["metier"]:
                    actuel = i
            if actuel == -1:
                actuel = choix_possibles.size()
                choix.add_item(pop.nom_metier(h), actuel)
            choix.select(actuel)
            choix.item_selected.connect(_choisir_metier.bind(h))
            ligne.add_child(choix)
        else:
            var m := Label.new()
            m.text = pop.nom_metier(h)
            m.add_theme_font_size_override("font_size", 28)
            ligne.add_child(m)
        liste.add_child(ligne)

func _choisir_metier(index: int, h: Dictionary) -> void:
    var pop = Civilisation.population
    var choix_possibles: Array = pop.metiers_choisis()
    if index < choix_possibles.size():
        pop.changer_metier(h, choix_possibles[index])
    _remplir_liste()

func _creer_panneau_fin() -> void:
    panneau_fin = PanelContainer.new()
    panneau_fin.anchor_left = 0.3
    panneau_fin.anchor_right = 0.7
    panneau_fin.anchor_top = 0.35
    panneau_fin.anchor_bottom = 0.65
    panneau_fin.visible = false
    add_child(panneau_fin)
    var boite := VBoxContainer.new()
    boite.alignment = BoxContainer.ALIGNMENT_CENTER
    panneau_fin.add_child(boite)
    var texte := Label.new()
    texte.text = "Le clan a disparu."
    texte.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    texte.add_theme_font_size_override("font_size", 40)
    boite.add_child(texte)
    var bouton := Button.new()
    bouton.text = "Recommencer"
    bouton.add_theme_font_size_override("font_size", 36)
    bouton.pressed.connect(Civilisation.nouvelle_partie)
    boite.add_child(bouton)

func _process(delta: float) -> void:
    etiquette_pop.text = "Habitants : %d" % Civilisation.population.habitants.size()
    etiquette_date.text = Civilisation.temps.texte()
    etiquette_res.text = Civilisation.ressources.texte() + "\n" + Civilisation.ressources.texte_aliments() + "   Richesse du clan : %d" % int(Civilisation.economie.valeur_stocks(Civilisation.ressources) + Civilisation.economie.patrimoine(Civilisation.construction, Civilisation.equipement) + Civilisation.economie.tresorerie(Civilisation.ressources))
    panneau_fin.visible = Civilisation.population.habitants.is_empty()
    if temps_message > 0.0:
        temps_message -= delta
        if temps_message <= 0.0:
            message.text = ""

func _basculer_travail() -> void:
    panneau_travail.visible = not panneau_travail.visible
    if panneau_travail.visible:
        panneau.visible = false

func _basculer_chef() -> void:
    panneau_chef.visible = not panneau_chef.visible
    if panneau_chef.visible:
        panneau.visible = false
        panneau_travail.visible = false
        panneau_construction.visible = false
        panneau_chef.remplir()

func _basculer_construction() -> void:
    panneau_construction.visible = not panneau_construction.visible
    if panneau_construction.visible:
        panneau.visible = false
        panneau_travail.visible = false
        panneau_construction.remplir()
