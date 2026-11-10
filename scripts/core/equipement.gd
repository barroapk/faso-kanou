extends RefCounted

# Outils et équipements du clan (v0.3.10) : data/outils.json.
# Chaque outil est un objet réel : il appartient au clan, il s'use à chaque
# jour d'utilisation, on peut le réparer (avec des matières et du travail),
# et il faut le remplacer quand il est cassé.
# Les outils ne sont pas donnés à chaque habitant : chaque jour, ceux qui sont
# en état sont confiés aux travailleurs, métier par métier, selon les priorités
# du clan. Un outil n'aide que le métier pour lequel il est fait.

signal evenement(texte)

const FICHIER := "res://data/outils.json"
const PERTE_PAR_REPARATION := 0.9   # durée de vie maximale x 0,9 à chaque réparation
const LIMITE_REPARATION := 0.5      # en dessous de 50 % de sa vie d'origine : à remplacer

var definitions := {}
var depart := {}
var priorites: Array = []
var instances: Array = []          # {uid, id, durabilite, max}
var prochain_uid := 1
var jours_utilises := 0
var casses := 0
var reparations := 0

func _init() -> void:
    var d = JSON.parse_string(FileAccess.get_file_as_string(FICHIER))
    if typeof(d) == TYPE_DICTIONARY:
        definitions = d.get("outils", {})
        depart = d.get("depart", {})
        priorites = d.get("priorites", [])
    etat_initial()

func etat_initial() -> void:
    instances = []
    prochain_uid = 1
    for id in depart:
        ajouter(id, int(depart[id]))

func est_outil(id: String) -> bool:
    return definitions.has(id)

func _creer(id: String) -> void:
    var vie := float(definitions[id]["durabilite"])
    instances.append({"uid": prochain_uid, "id": id, "durabilite": vie, "max": vie})
    prochain_uid += 1

func ajouter(id: String, n: int) -> void:
    for i in n:
        _creer(id)

# Nombre d'outils de ce type encore utilisables.
func nombre(id: String) -> int:
    var n := 0
    for o in instances:
        if o["id"] == id and float(o["durabilite"]) > 0.0:
            n += 1
    return n

func retirer(id: String, n: int) -> bool:
    if nombre(id) < n:
        return false
    for i in n:
        for o in instances:
            if o["id"] == id:
                instances.erase(o)
                break
    return true

func _user(o: Dictionary) -> void:
    o["durabilite"] = float(o["durabilite"]) - 1.0
    jours_utilises += 1
    if float(o["durabilite"]) <= 0.0:
        instances.erase(o)
        casses += 1
        evenement.emit("Un outil est hors d'usage : %s. Il faut le remplacer." % o["id"])

# Utilisation par une recette (par exemple le canari pour le sel végétal).
func user(id: String) -> void:
    for o in instances:
        if o["id"] == id and float(o["durabilite"]) > 0.0:
            _user(o)
            return

# ---------- Chaque jour : qui reçoit quel outil ----------

func jour_passe(pop, chantier_actif: bool) -> void:
    for h in pop.habitants:
        h.erase("bonus_outil")
    var libres := instances.duplicate()
    for metier in priorites:
        for h in pop.habitants:
            if h["metier"] != metier or h.get("occupe", false):
                continue
            var effet: String = "chantier" if metier == "bâtisseur" and chantier_actif else metier
            var meilleur := {}
            var bonus_max := 1.0
            for o in libres:
                var b := float(definitions[o["id"]]["effets"].get(effet, 1.0))
                if b > bonus_max:
                    bonus_max = b
                    meilleur = o
            if meilleur.is_empty():
                continue
            libres.erase(meilleur)
            h["bonus_outil"] = bonus_max
            _user(meilleur)

# ---------- Réparation ----------

# Un outil se répare s'il est usé, pas cassé, et pas déjà trop réparé.
func _reparable(o: Dictionary) -> bool:
    var vie := float(definitions[o["id"]]["durabilite"])
    return float(o["durabilite"]) > 0.0 and float(o["durabilite"]) < float(o["max"]) and float(o["max"]) * PERTE_PAR_REPARATION >= vie * LIMITE_REPARATION

func a_reparer(id: String) -> bool:
    for o in instances:
        if o["id"] == id and _reparable(o):
            return true
    return false

# Répare l'outil le plus usé de ce type.
func reparer(id: String) -> void:
    var pire := {}
    for o in instances:
        if o["id"] == id and _reparable(o):
            if pire.is_empty() or float(o["durabilite"]) < float(pire["durabilite"]):
                pire = o
    if pire.is_empty():
        return
    pire["max"] = float(pire["max"]) * PERTE_PAR_REPARATION
    pire["durabilite"] = pire["max"]
    reparations += 1

func etat_moyen(id: String) -> float:
    var t := 0.0
    var n := 0
    for o in instances:
        if o["id"] == id:
            t += float(o["durabilite"]) / float(definitions[id]["durabilite"])
            n += 1
    return t / n if n > 0 else 0.0

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {"instances": instances, "prochain_uid": prochain_uid, "priorites": priorites, "jours_utilises": jours_utilises, "casses": casses, "reparations": reparations}

# Ancienne sauvegarde : le clan reçoit l'équipement de départ, rien de plus.
func depuis_dict(d: Dictionary) -> void:
    if d.is_empty():
        etat_initial()
        return
    instances = []
    for o in d.get("instances", []):
        if definitions.has(str(o["id"])):
            instances.append({"uid": int(o["uid"]), "id": str(o["id"]), "durabilite": float(o["durabilite"]), "max": float(o["max"])})
    prochain_uid = int(d.get("prochain_uid", instances.size() + 1))
    if d.has("priorites"):
        priorites = []
        for m in d["priorites"]:
            priorites.append(str(m))
    jours_utilises = int(d.get("jours_utilises", 0))
    casses = int(d.get("casses", 0))
    reparations = int(d.get("reparations", 0))
