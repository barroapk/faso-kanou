extends RefCounted

# Flotte du clan (v0.3.22 T5) : UN seul gestionnaire de bateaux pour tout ce
# qui traverse la mer : commerce, visites, explorations (et plus tard migrants).
# Règle : une mission = un bateau, immobilisé jusqu'à son retour. Deux bateaux
# en mer = pas de troisième départ.
# Sans port, le clan garde 1 pirogue sur la plage. Le port (relié par la route)
# donne des places en plus : 2, puis 4, puis 8 selon son niveau. Les grands
# bateaux demandent un port assez grand.
# Chaque bateau a une capacité (personnes, kg), une vitesse et un état ; il
# s'use en mer et coûte un entretien chaque année.
# Plus tard : l'aéroport (époque moderne) ajoutera ses propres appareils, avec
# leurs coûts, sans rendre les bateaux inutiles.

signal evenement(texte)

const TYPES := {
    "pirogue": {"nom": "Grande pirogue", "personnes": 4, "kg": 500.0, "km_jour": 40.0, "cout": {"bois": 60.0}, "travail": 15.0, "port_min": 0},
    "boutre": {"nom": "Bateau marchand", "personnes": 8, "kg": 3000.0, "km_jour": 55.0, "cout": {"bois": 300.0}, "travail": 60.0, "port_min": 2},
    "navire": {"nom": "Grand navire", "personnes": 20, "kg": 15000.0, "km_jour": 70.0, "cout": {"bois": 900.0, "pierre": 50.0}, "travail": 150.0, "port_min": 3},
}
const USURE_MER := 0.002         # état perdu par jour en mer
const ENTRETIEN := 0.05          # entretien annuel : 5 % du prix du bateau

var bateaux: Array = []          # {id, type, etat, occupe_jusqu: jour, mission}
var chantier := {}               # {type, travail_restant}
var prochain_id := 1

func depart() -> void:
    if bateaux.is_empty():
        bateaux.append({"id": prochain_id, "type": "pirogue", "etat": 1.0, "occupe_jusqu": -1, "mission": ""})
        prochain_id += 1

# Niveau du port en service (0 = pas de port, ou pas de route jusqu'au port).
func niveau_port(construction, routes) -> int:
    if routes != null and not routes.relie("port"):
        return 0
    var n := 0
    for b in construction.batiments:
        if b["type"] == "port":
            n = maxi(n, int(b["niveau"]))
    return n

func places(construction, routes) -> int:
    return [1, 2, 4, 8][clampi(niveau_port(construction, routes), 0, 3)]

func libres(jour: int) -> Array:
    return bateaux.filter(func(b): return int(b["occupe_jusqu"]) < jour)

# Prend le plus petit bateau libre qui suffit (personnes, kg). {} si aucun.
func reserver(jour: int, jusqu_a: int, personnes: int, kg: float, mission: String) -> Dictionary:
    var choix := {}
    for b in libres(jour):
        var t: Dictionary = TYPES[b["type"]]
        if int(t["personnes"]) < personnes or float(t["kg"]) < kg:
            continue
        if choix.is_empty() or float(t["kg"]) < float(TYPES[choix["type"]]["kg"]):
            choix = b
    if not choix.is_empty():
        choix["occupe_jusqu"] = jusqu_a
        choix["mission"] = mission
        choix["etat"] = maxf(0.2, float(choix["etat"]) - USURE_MER * float(jusqu_a - jour))
    return choix

func vitesse_libre(jour: int, personnes: int, kg: float) -> float:
    var v := 0.0
    for b in libres(jour):
        var t: Dictionary = TYPES[b["type"]]
        if int(t["personnes"]) >= personnes and float(t["kg"]) >= kg:
            v = maxf(v, float(t["km_jour"]))
    return v

func raison_aucun(jour: int, personnes: int, kg: float) -> String:
    if libres(jour).is_empty():
        return "Tous nos bateaux sont en mer (%d bateau(x))." % bateaux.size()
    return "Aucun bateau libre assez grand (%d personnes, %d kg)." % [personnes, int(kg)]

# ---------- Construire un bateau (par les bâtisseurs libres) ----------

func commander(type: String, res, construction, routes) -> String:
    if not chantier.is_empty():
        return "Un bateau est déjà en construction."
    if bateaux.size() >= places(construction, routes):
        return "Plus de place : agrandissez le port (relié par la route) pour avoir plus de bateaux."
    var t: Dictionary = TYPES[type]
    if niveau_port(construction, routes) < int(t["port_min"]):
        return "Il faut un port de niveau %d pour construire un %s." % [int(t["port_min"]), t["nom"].to_lower()]
    for r in t["cout"]:
        if res.quantite(r) < float(t["cout"][r]):
            return "Il faut %s." % _texte(t["cout"])
    for r in t["cout"]:
        res.retirer(r, float(t["cout"][r]), "construction")
    chantier = {"type": type, "travail_restant": float(t["travail"])}
    evenement.emit("Chantier naval : %s commencé." % t["nom"].to_lower())
    return ""

func _texte(c: Dictionary) -> String:
    var l: PackedStringArray = []
    for r in c:
        l.append("%d %s" % [int(c[r]), r])
    return ", ".join(l)

func en_travaux() -> bool:
    return not chantier.is_empty()

func jour_passe(travail: float) -> void:
    if chantier.is_empty():
        return
    chantier["travail_restant"] = float(chantier["travail_restant"]) - travail
    if float(chantier["travail_restant"]) <= 0.0:
        bateaux.append({"id": prochain_id, "type": chantier["type"], "etat": 1.0, "occupe_jusqu": -1, "mission": ""})
        prochain_id += 1
        evenement.emit("%s mis à l'eau." % TYPES[chantier["type"]]["nom"])
        chantier = {}

# Entretien annuel : sans bois, le bateau s'abîme ; à 20 %, il coule au port.
func mois_passe(res, mois: int) -> void:
    if mois != 0:
        return
    for b in bateaux.duplicate():
        var bois: float = float(TYPES[b["type"]]["cout"].get("bois", 0.0)) * ENTRETIEN
        if res.quantite("bois") >= bois:
            res.retirer("bois", bois, "entretien")
            b["etat"] = minf(1.0, float(b["etat"]) + 0.2)
        else:
            b["etat"] = float(b["etat"]) - 0.2
            if float(b["etat"]) <= 0.2 and bateaux.size() > 1:
                bateaux.erase(b)
                evenement.emit("Faute d'entretien, un bateau (%s) est hors d'usage." % TYPES[b["type"]]["nom"].to_lower())

func vers_dict() -> Dictionary:
    return {"bateaux": bateaux, "chantier": chantier, "prochain_id": prochain_id}

func depuis_dict(d: Dictionary) -> void:
    bateaux = d.get("bateaux", [])
    chantier = d.get("chantier", {})
    prochain_id = int(d.get("prochain_id", 1))
    depart()
