extends PanelContainer

var boite: VBoxContainer
var etiquette_chantiers: Label

func _ready() -> void:
    anchor_left = 0.12
    anchor_right = 0.88
    anchor_top = 0.15
    anchor_bottom = 0.88
    var defil := ScrollContainer.new()
    add_child(defil)
    boite = VBoxContainer.new()
    boite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    boite.add_theme_constant_override("separation", 12)
    defil.add_child(boite)
    Civilisation.construction.evenement.connect(func(_t): if visible: remplir())

func _label(texte: String, taille: int) -> Label:
    var l := Label.new()
    l.text = texte
    l.add_theme_font_size_override("font_size", taille)
    return l

func _bouton(texte: String, actif: bool, action: Callable) -> Button:
    var b := Button.new()
    b.text = texte
    b.disabled = not actif
    b.add_theme_font_size_override("font_size", 26)
    b.pressed.connect(action)
    return b

func remplir() -> void:
    for c in boite.get_children():
        c.queue_free()
    var cons = Civilisation.construction
    var res = Civilisation.ressources
    boite.add_child(_label("Construction", 36))
    for type in cons.definitions:
        if not cons.disponible(type):
            continue
        var def: Dictionary = cons.definitions[type]
        var ligne := HBoxContainer.new()
        var l := _label("%s : %d" % [def["nom"], cons.nombre(type)], 30)
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        ligne.add_child(l)
        var n1: Dictionary = def["niveaux"][0]
        ligne.add_child(_bouton("Construire (%s, %d j)" % [cons.texte_cout(n1["cout"]), int(n1["travail"])], cons.peut_payer(n1["cout"], res), _agir.bind(type, -1)))
        var idx: int = cons.index_a_ameliorer(type)
        if idx >= 0:
            var niv: Dictionary = def["niveaux"][int(cons.batiments[idx]["niveau"])]
            ligne.add_child(_bouton("Améliorer (%s, %d j)" % [cons.texte_cout(niv["cout"]), int(niv["travail"])], cons.peut_payer(niv["cout"], res), _agir.bind(type, idx)))
        boite.add_child(ligne)
    etiquette_chantiers = _label("", 28)
    boite.add_child(etiquette_chantiers)
    _remplir_entretien(cons, res)

# Danger des greniers (v0.4) : état de chaque bâtiment, ordre d'entretien, suspension, réparation.
func _remplir_entretien(cons, res) -> void:
    boite.add_child(HSeparator.new())
    var e: float = cons.entretien_mois()
    var t := _label("Entretien du mois : %d kg de bois (stock : %d kg)" % [int(ceil(e)), int(res.stocks["bois"])], 30)
    if float(res.stocks["bois"]) < e:
        t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
    boite.add_child(t)
    boite.add_child(_label("Payé dans cet ordre, du haut vers le bas :", 24))
    var types: Array = cons.ordre_types()
    for type in types:
        if cons.nombre(type) == 0:
            continue
        var ligne := HBoxContainer.new()
        var l := _label(cons.definitions[type]["nom"], 28)
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        ligne.add_child(l)
        ligne.add_child(_bouton("Monter", true, _deplacer.bind(type, -1)))
        ligne.add_child(_bouton("Descendre", true, _deplacer.bind(type, 1)))
        boite.add_child(ligne)
        for i in cons.batiments.size():
            var b: Dictionary = cons.batiments[i]
            if b["type"] != type:
                continue
            var niv: Dictionary = cons.definitions[type]["niveaux"][int(b["niveau"]) - 1]
            var lb := HBoxContainer.new()
            var etat := int(b["etat"])
            var texte := "    %s : état %d (%s), %s/mois" % [niv["nom"], etat, cons.palier(etat), cons.texte_cout(niv["entretien"])]
            if bool(b.get("suspendu", false)):
                texte += ", entretien suspendu"
            if cons.en_reparation(i):
                texte += ", en réparation"
            var lab := _label(texte, 24)
            lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            if etat <= 0:
                lab.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
            elif etat < cons.ETAT_FRAGILE:
                lab.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
            elif etat < cons.ETAT_USE:
                lab.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
            lb.add_child(lab)
            if etat <= 0:
                var rep: Dictionary = cons.cout_reparation(i)
                lb.add_child(_bouton("Réparer (%s, %d j)" % [cons.texte_cout(rep["cout"]), int(rep["travail"])], not cons.en_reparation(i) and cons.peut_payer(rep["cout"], res), _reparer.bind(i)))
            else:
                lb.add_child(_bouton("Reprendre" if bool(b.get("suspendu", false)) else "Suspendre", true, _suspendre.bind(i)))
            boite.add_child(lb)

func _deplacer(type: String, sens: int) -> void:
    Civilisation.construction.deplacer_type(type, sens)
    remplir()

func _suspendre(index: int) -> void:
    Civilisation.construction.basculer_suspension(index)
    remplir()

func _reparer(index: int) -> void:
    Civilisation.construction.lancer_reparation(index, Civilisation.ressources)
    remplir()

func _agir(type: String, index: int) -> void:
    Civilisation.construction.lancer(type, index, Civilisation.ressources)
    remplir()

func _process(_delta: float) -> void:
    if visible and etiquette_chantiers:
        etiquette_chantiers.text = Civilisation.construction.texte_chantiers(Civilisation.travail_batisseurs())
