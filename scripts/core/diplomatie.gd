extends RefCounted

# Relations entre clans (v0.3.14) : un score de -100 à +100 par paire de clans,
# et une mémoire des événements (échanges, conflits, promesses).
# État : alliance (accord signé), amitié, neutralité, rivalité, hostilité.
# Le temps adoucit lentement les souvenirs (le score revient vers 0).

signal evenement(texte)

const MEMOIRE_MAX := 50
const OUBLI_MOIS := 0.995
const DEPART := {"barro_faso|joueur": -20.0, "joueur|konate": 10.0, "barro_faso|konate": 0.0}

var relations := {}   # "a|b" (ordre alphabétique) -> {score, alliance, memoire}

func cle(a: String, b: String) -> String:
    return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

func relation(a: String, b: String) -> Dictionary:
    var k := cle(a, b)
    if not relations.has(k):
        relations[k] = {"score": float(DEPART.get(k, 0.0)), "alliance": false, "memoire": []}
    return relations[k]

func etat(a: String, b: String) -> String:
    var r := relation(a, b)
    var s := float(r["score"])
    if bool(r["alliance"]):
        return "alliance"
    if s >= 40.0:
        return "amitié"
    if s >= -15.0:
        return "neutralité"
    if s >= -50.0:
        return "rivalité"
    return "hostilité"

func etat_initial(ids: Array) -> void:
    relations = {}
    for i in ids.size():
        for j in range(i + 1, ids.size()):
            relation(ids[i], ids[j])

# Un événement change la relation et reste en mémoire.
func noter(a: String, b: String, type: String, effet: float, texte: String, jour: int) -> void:
    var r := relation(a, b)
    var avant := etat(a, b)
    r["score"] = clampf(float(r["score"]) + effet, -100.0, 100.0)
    r["memoire"].append({"jour": jour, "type": type, "effet": effet, "texte": texte})
    while r["memoire"].size() > MEMOIRE_MAX:
        r["memoire"].pop_front()
    if etat(a, b) != avant:
        evenement.emit("Relations %s - %s : %s." % [a, b, etat(a, b)])

# Une alliance se signe entre amis, et se rompt.
func signer_alliance(a: String, b: String, jour: int) -> String:
    if etat(a, b) != "amitié":
        return "Il faut d'abord être amis."
    relation(a, b)["alliance"] = true
    noter(a, b, "promesse", 5.0, "alliance signée", jour)
    return ""

func rompre_alliance(a: String, b: String, jour: int) -> void:
    if bool(relation(a, b)["alliance"]):
        relation(a, b)["alliance"] = false
        noter(a, b, "trahison", -40.0, "alliance rompue", jour)

func mois_passe() -> void:
    for k in relations:
        relations[k]["score"] = float(relations[k]["score"]) * OUBLI_MOIS

func vers_dict() -> Dictionary:
    return {"relations": relations}

func depuis_dict(d: Dictionary, ids: Array) -> void:
    if d.is_empty():
        etat_initial(ids)
        return
    relations = {}
    for k in d.get("relations", {}):
        var r: Dictionary = d["relations"][k]
        relations[str(k)] = {"score": float(r.get("score", 0.0)), "alliance": bool(r.get("alliance", false)), "memoire": r.get("memoire", [])}
