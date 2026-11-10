extends CanvasLayer

# Écran de choix de l'île (v0.3.16 C).
# Montré au début d'une nouvelle partie : carte de l'archipel, propriétés de
# chaque île libre, avantages et difficultés, puis confirmation.
# Les îles des rivaux (BARRO FASO, KONATÉ) sont sur la carte mais pas au choix.

const NOMS_CLANS := {"barro_faso": "BARRO FASO", "konate": "KONATÉ"}

var iles := {}
var choix := ""
var carte: Control
var details: Label
var bouton_ok: Button
var liste: VBoxContainer

func _ready() -> void:
    layer = 20
    iles = Civilisation.agriculture.catalogue_iles()
    Civilisation.temps.vitesse = 0
    var fond := ColorRect.new()
    fond.color = Color(0.05, 0.12, 0.2, 0.97)
    fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(fond)
    var defil := ScrollContainer.new()
    defil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    defil.offset_left = 24
    defil.offset_right = -24
    defil.offset_top = 24
    defil.offset_bottom = -24
    add_child(defil)
    var boite := VBoxContainer.new()
    boite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    boite.add_theme_constant_override("separation", 14)
    defil.add_child(boite)
    boite.add_child(_label("Choisis l'île de ton clan", 40))
    boite.add_child(_label("Chaque clan vit sur son île. Les autres îles se rejoignent par bateau.", 22))
    carte = Control.new()
    carte.custom_minimum_size = Vector2(0, 520)
    carte.draw.connect(_dessiner_carte)
    carte.gui_input.connect(_toucher_carte)
    boite.add_child(carte)
    liste = VBoxContainer.new()
    liste.add_theme_constant_override("separation", 8)
    boite.add_child(liste)
    for id in Civilisation.iles_au_choix():
        var b := Button.new()
        b.text = "%s — %s" % [iles[id]["nom"], iles[id]["forme"]]
        b.add_theme_font_size_override("font_size", 24)
        b.pressed.connect(_choisir.bind(id))
        liste.add_child(b)
    details = _label("Touche une île pour voir ses propriétés.", 24)
    details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    boite.add_child(details)
    bouton_ok = Button.new()
    bouton_ok.text = "Commencer sur cette île"
    bouton_ok.disabled = true
    bouton_ok.add_theme_font_size_override("font_size", 30)
    bouton_ok.pressed.connect(_confirmer)
    boite.add_child(bouton_ok)

func _label(t: String, taille: int) -> Label:
    var l := Label.new()
    l.text = t
    l.add_theme_font_size_override("font_size", taille)
    return l

# ---------- Carte ----------

func _echelle() -> float:
    return minf(carte.size.x / 900.0, carte.size.y / 700.0)

func _position(ile: Dictionary) -> Vector2:
    var e := _echelle()
    return Vector2(float(ile["carte"]["x"]), float(ile["carte"]["z"])) * e

func _rayon(ile: Dictionary) -> float:
    # Rayon proportionnel à la vraie surface (1 ha = 0,01 km²).
    return sqrt(float(ile["surface_ha"]) / 100.0 / PI) * _echelle()

func _dessiner_carte() -> void:
    carte.draw_rect(Rect2(Vector2.ZERO, Vector2(900, 700) * _echelle()), Color(0.1, 0.3, 0.5))
    var police := ThemeDB.fallback_font
    for id in iles:
        var ile: Dictionary = iles[id]
        var rival := str(ile.get("clan", "")) != ""
        var couleur := Color(0.45, 0.45, 0.45) if rival else Color(0.35, 0.6, 0.3)
        if id == choix:
            couleur = Color(0.9, 0.75, 0.3)
        var p := _position(ile)
        carte.draw_circle(p, _rayon(ile), couleur)
        var nom: String = ile["nom"].replace("Île de ", "").replace("Îles de ", "")
        if rival:
            nom += " (" + NOMS_CLANS.get(ile["clan"], ile["clan"]) + ")"
        carte.draw_string(police, p + Vector2(-_rayon(ile), _rayon(ile) + 22), nom, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

func _toucher_carte(ev: InputEvent) -> void:
    var appui: bool = (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed)
    if not appui:
        return
    for id in Civilisation.iles_au_choix():
        if ev.position.distance_to(_position(iles[id])) <= _rayon(iles[id]) + 20.0:
            _choisir(id)
            return

# ---------- Choix ----------

func _choisir(id: String) -> void:
    choix = id
    details.text = _description(id)
    bouton_ok.disabled = false
    bouton_ok.text = "Commencer : %s" % iles[id]["nom"]
    carte.queue_redraw()

func _niveau(v: float) -> String:
    if v >= 1.4:
        return "très riche"
    if v >= 1.1:
        return "riche"
    if v >= 0.8:
        return "moyen"
    if v >= 0.5:
        return "pauvre"
    return "très pauvre"

func _description(id: String) -> String:
    var i: Dictionary = iles[id]
    var r: Dictionary = i["richesse"]
    var e: Dictionary = i["eau_douce"]
    var l: Dictionary = i["littoral"]
    var t := "%s\n%s ; relief : %s.\n\n" % [i["nom"], i["forme"], i["relief"]]
    t += "Surface : %s km² ; terres cultivables : %s ha.\n" % [_nombre(float(i["surface_ha"]) / 100.0), _nombre(float(i["cultivable_ha"]))]
    t += "Fertilité : %s ; pluie : %d mm par an.\n" % [_niveau(float(i["fertilite"])), int(i["pluie_mm"])]
    t += "Eau douce : %d rivière(s), %d source(s), nappe %s.\n" % [int(e["rivieres"]), int(e["sources"]), e["nappe"]]
    t += "Côtes : %d baie(s)%s.\n\n" % [int(l["baies"]), ", port naturel" if bool(l["port_naturel"]) else ""]
    t += "Ressources : "
    var parts: PackedStringArray = []
    for k in ["bois", "chasse", "cueillette", "pierre", "argile", "fer", "or", "sel", "poisson"]:
        parts.append("%s %s" % [k, _niveau(float(r.get(k, 1.0)))])
    t += ", ".join(parts) + ".\n\n"
    var plus: PackedStringArray = []
    var moins: PackedStringArray = []
    for k in r:
        if float(r[k]) >= 1.4:
            plus.append(k)
        elif float(r[k]) <= 0.4:
            moins.append(k)
    if float(i["fertilite"]) >= 1.1:
        plus.append("sols fertiles")
    elif float(i["fertilite"]) <= 0.75:
        moins.append("sols pauvres")
    if int(i["pluie_mm"]) >= 1000:
        plus.append("pluies abondantes")
    elif int(i["pluie_mm"]) <= 500:
        moins.append("sécheresse")
    t += "Avantages : %s.\n" % (", ".join(plus) if plus.size() > 0 else "équilibrée")
    t += "Difficultés : %s." % (", ".join(moins) if moins.size() > 0 else "aucune grande faiblesse")
    return t

func _nombre(v: float) -> String:
    var s := str(int(round(v)))
    var r := ""
    while s.length() > 3:
        r = " " + s.substr(s.length() - 3) + r
        s = s.substr(0, s.length() - 3)
    return s + r

func _confirmer() -> void:
    if choix == "":
        return
    Civilisation.nouvelle_partie(choix)
