extends RefCounted

# Le héros du clan (v0.3.29) et son héritage (v0.3.30).
# Un héros naît d'un exploit réel, jamais du hasard :
#   navigateur : rentré vivant d'un bateau disparu
#   savant     : a réussi une expérience (découverte)
#   protecteur : a veillé sur les champs ou creusé les puits de la sécheresse
#   artisan    : maître de son métier (compétence 90 ou plus)
# Un seul héros vivant à la fois. S'il meurt, un autre peut naître.
# Son bonus (10, 15 puis 20 %) ne joue que s'il fait vraiment l'activité.
# À sa mort, il rejoint les ancêtres ; le clan peut l'honorer (monument,
# ou son nom donné à un puits, un grenier, un port, une route : +2 %).

signal evenement(texte)

const TITRES := {"navigateur": "le Navigateur", "savant": "le Savant", "artisan": "le Maître", "protecteur": "le Protecteur"}
const EFFETS := {"navigateur": "moins de risques en mer, explorations plus sûres",
    "savant": "expériences plus faciles quand il y participe",
    "artisan": "les apprentis de son métier progressent plus vite à ses côtés",
    "protecteur": "moins de dégâts des bêtes sauvages quand il est au village"}
const NIVEAUX := ["connu", "célèbre", "légendaire"]
const BONUS := [0.10, 0.15, 0.20]
const HERITAGES := {"puits": "le puits", "grenier": "le grenier", "port": "le port", "route": "la route de l'eau"}

var heros_id := -1
var parti := false               # parti chez un autre clan (pas un ancêtre)
var mort := false                # vraie mort (ou perdu en mer), pas un départ
var ancetres: Array = []         # {nom, titre, niveau, jour, heritage}
var memo := {}                   # nom, titre, niveau du héros vivant (pour l'histoire)
var rng := RandomNumberGenerator.new()

func _init() -> void:
    rng.seed = 9009

# Bonus d'un habitant pour une activité (0 s'il n'est pas le héros de ce type).
static func bonus(h: Dictionary, type: String) -> float:
    var d: Dictionary = h.get("heros", {})
    if d.get("type", "") != type:
        return 0.0
    return BONUS[clampi(int(d["niveau"]), 0, 2)]

func heros(pop) -> Variant:
    for h in pop.habitants:
        if int(h["id"]) == heros_id:
            return h
    return null

func sur_depart(h: Dictionary, deces: bool) -> void:
    if int(h["id"]) == heros_id and (deces or h.has("perdu_en_mer")):
        mort = true

func nom(h: Dictionary) -> String:
    return "%s %s %s" % [h["prenom"], h["nom"], TITRES[h["heros"]["type"]]]

func mois_passe(C) -> void:
    var pop = C.population
    var jour: int = C.temps.jour_total
    # Le héros a-t-il quitté le clan ?
    if heros_id >= 0 and heros(pop) == null:
        if mort:
            var niv := int(memo.get("niveau", 0))
            ancetres.append({"nom": memo.get("nom", "?"), "titre": memo.get("titre", ""), "niveau": niv, "jour": jour, "heritage": ""})
            C.defis.renommee += 5 * (niv + 1)
            evenement.emit("Notre héros %s nous a quittés. Il rejoint les ancêtres du clan (renommée +%d)." % [ancetres[-1]["nom"], 5 * (niv + 1)])
            C.defis._proposer("honneur_%d" % (ancetres.size() - 1), "Honorer %s" % ancetres[-1]["nom"],
                "Le clan veut garder vivante la mémoire de son héros.",
                ["Ériger un monument (60 bois, 80 pierres, 60 jours de travail)", "Donner son nom à une infrastructure (puits, grenier, port ou route)", "Garder son nom parmi les ancêtres"],
                30, jour, {"ancetre": ancetres.size() - 1})
        elif not parti:
            evenement.emit("Notre héros %s a quitté l'île." % memo.get("nom", "?"))
        heros_id = -1
        parti = false
        mort = false
    appliquer(C)
    # Un monument achevé rappelle chaque année la grandeur du clan.
    if C.temps.mois() == 0:
        var m := mini(C.construction.nombre("monument"), ancetres.filter(func(a): return a.get("heritage", "") == "monument").size())
        if m > 0:
            C.defis.renommee += m
            evenement.emit("Fête des ancêtres devant les monuments : renommée +%d." % m)
    # Les exploits du mois.
    for h in pop.habitants:
        var ex: String = h.get("exploit", "")
        h.erase("exploit")
        if ex == "" and not h["metier"] in ["chef", "ancien", "enfant", "sans métier"] and float(h["competence"]) >= 90.0 and not h.has("maitre"):
            h["maitre"] = true
            ex = "artisan"
        if ex == "":
            continue
        if h.has("heros"):
            var d: Dictionary = h["heros"]
            d["exploits"] = int(d["exploits"]) + 1
            var niv := 2 if int(d["exploits"]) >= 4 else (1 if int(d["exploits"]) >= 2 else 0)
            C.defis.renommee += 3
            if niv > int(d["niveau"]):
                d["niveau"] = niv
                evenement.emit("Nouvel exploit : %s devient %s !" % [nom(h), NIVEAUX[niv]])
        elif heros_id < 0:
            h["heros"] = {"type": ex, "niveau": 0, "exploits": 1, "depuis": jour}
            heros_id = int(h["id"])
            C.defis.renommee += 5
            evenement.emit("Un héros est né : %s ! (%s)" % [nom(h), EFFETS[ex]])
    var hh = heros(pop)
    if hh != null:
        memo = {"nom": "%s %s" % [hh["prenom"], hh["nom"]], "titre": TITRES[hh["heros"]["type"]], "niveau": int(hh["heros"]["niveau"])}
    # BARRO FASO veut attirer un héros célèbre.
    if hh != null and int(hh["heros"]["niveau"]) >= 1 and C.rival.connu(C) and C.diplomatie.etat("joueur", "barro_faso") != "alliance" and rng.randf() < 0.06:
        C.defis._proposer("recrue_%d" % heros_id, "BARRO FASO veut attirer %s" % hh["prenom"],
            "Le chef de BARRO FASO lui promet honneurs et richesses. S'il part, il est perdu pour notre clan.",
            ["Le laisser partir (BARRO FASO nous en sera reconnaissant)", "Le garder"], 15, jour, {"id": heros_id})

# Choix du joueur à la mort d'un héros. Renvoie "" si c'est fait.
func honorer(C, i: int, option: int) -> String:
    if i < 0 or i >= ancetres.size():
        return ""
    var a: Dictionary = ancetres[i]
    if option == 0:
        if not C.construction.lancer("monument", -1, C.ressources):
            return "Il faut 60 bois et 80 pierres."
        a["heritage"] = "monument"
        evenement.emit("Chantier lancé : le monument de %s." % a["nom"])
    elif option == 1:
        var pris: Array = ancetres.map(func(x): return x.get("heritage", ""))
        var choix := ""
        for k in ["puits", "grenier", "port", "route"]:
            var existe: bool = C.routes.relie("eau") if k == "route" else C.construction.nombre(k) > 0
            if existe and pris.count(k) < 3:
                choix = k
                break
        if choix == "":
            return "Aucune infrastructure à nommer pour l'instant."
        a["heritage"] = choix
        appliquer(C)
        evenement.emit("%s portera désormais le nom de %s (+2 %%)." % [HERITAGES[choix].left(1).to_upper() + HERITAGES[choix].substr(1), a["nom"]])
    return ""

# Recalcule les effets d'héritage (après chaque mois et au chargement).
func appliquer(C) -> void:
    var n := {"puits": 0, "grenier": 0, "port": 0, "route": 0}
    for a in ancetres:
        var k: String = a.get("heritage", "")
        if n.has(k):
            n[k] = mini(3, n[k] + 1)
    C.agriculture.honneur_puits = 0.02 * n["puits"] if C.construction.nombre("puits") > 0 else 0.0
    C.ressources.honneur_grenier = 0.02 * n["grenier"] if C.construction.nombre("grenier") > 0 else 0.0
    C.flotte.honneur_port = 0.02 * n["port"] if C.construction.nombre("port") > 0 else 0.0
    C.ressources.honneur_route = 0.02 * n["route"] if C.routes.relie("eau") else 0.0

func laisser_partir(C, jour: int) -> void:
    var h = heros(C.population)
    if h == null:
        return
    parti = true
    evenement.emit("%s part rejoindre BARRO FASO." % nom(h))
    C.population.faire_sortir(h, jour)
    C.diplomatie.noter("joueur", "barro_faso", "heros", 10.0, "héros cédé", jour)

func texte() -> String:
    var l: PackedStringArray = []
    if heros_id >= 0 and not memo.is_empty():
        l.append("Héros : %s %s (%s)" % [memo["nom"], memo["titre"], NIVEAUX[int(memo["niveau"])]])
    else:
        l.append("Héros : aucun pour l'instant (il naîtra d'un exploit).")
    for a in ancetres:
        var her: String = a.get("heritage", "")
        var t := "Ancêtre : %s %s (%s)" % [a["nom"], a["titre"], NIVEAUX[int(a["niveau"])]]
        if her == "monument":
            t += " — son monument"
        elif her != "":
            t += " — %s porte son nom" % HERITAGES[her]
        l.append(t)
    return "\n".join(l)

func vers_dict() -> Dictionary:
    return {"id": heros_id, "parti": parti, "ancetres": ancetres, "memo": memo, "mort": mort, "graine": rng.seed, "etat": rng.state}

func depuis_dict(d: Dictionary) -> void:
    heros_id = int(d.get("id", -1))
    parti = bool(d.get("parti", false))
    ancetres = d.get("ancetres", [])
    memo = d.get("memo", {})
    mort = bool(d.get("mort", false))
    if d.has("graine"):
        rng.seed = int(d["graine"])
        rng.state = int(d["etat"])
