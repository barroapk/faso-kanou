extends RefCounted

# Relations entre clans (v0.3.14) : un score de -100 à +100 par paire de clans,
# et une mémoire des événements (échanges, conflits, promesses).
# État : alliance (accord signé), amitié, neutralité, rivalité, hostilité.
# Le temps adoucit lentement les souvenirs (le score revient vers 0).

signal evenement(texte)

const MEMOIRE_MAX := 50
const OUBLI_MOIS := 0.995
const DEPART := {"barro_faso|joueur": -20.0, "joueur|konate": 10.0, "barro_faso|konate": 0.0}

const SEUIL_OUBLI_RAPIDE := -50.0
const JOURS_SANS_HOSTILE := 180
const CADEAU_MAX := 10.0
const CADEAU_REPOS := 30
const AIDE_REPOS := 60
var repos := {}       # "cadeau|a|b" ou "aide|a|b" -> jour de la dernière action
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

# Oubli mensuel. v0.3.69 : pour les relations du joueur seulement, un score très bas (sous -50)
# s'efface deux fois plus vite (1 % au lieu de 0,5 %) après 6 mois sans aucun événement hostile.
# Dès qu'un nouvel événement hostile est noté, l'accélération s'arrête d'elle-même. La mémoire
# des événements n'est jamais effacée.
func mois_passe(jour := -1) -> void:
    for k in relations:
        var f := OUBLI_MOIS
        if jour >= 0 and str(k).split("|").has("joueur") and float(relations[k]["score"]) < SEUIL_OUBLI_RAPIDE and _jours_sans_hostile(relations[k], jour) >= JOURS_SANS_HOSTILE:
            f = 1.0 - 2.0 * (1.0 - OUBLI_MOIS)
        relations[k]["score"] = float(relations[k]["score"]) * f

func _jours_sans_hostile(r: Dictionary, jour: int) -> int:
    var dernier_hostile := -1000000
    for m in r["memoire"]:
        if float(m["effet"]) < 0.0:
            dernier_hostile = maxi(dernier_hostile, int(m["jour"]))
    return jour - dernier_hostile

# Somme des effets enregistrés sur les derniers jours (la tendance vient des événements, pas d'une impression).
func tendance(a: String, b: String, jour: int, fenetre := 30) -> float:
    var s := 0.0
    for m in relation(a, b)["memoire"]:
        if int(m["jour"]) > jour - fenetre:
            s += float(m["effet"])
    return s

func dernier_evenement(a: String, b: String) -> Dictionary:
    var mem: Array = relation(a, b)["memoire"]
    return mem[mem.size() - 1] if not mem.is_empty() else {}

# Cadeau de vivres : le gain dépend de la quantité réellement offerte, plafonné à +10.
func gain_cadeau(kg: float, ref: float) -> float:
    return CADEAU_MAX * clampf(kg / maxf(1.0, ref), 0.0, 1.0)

func repos_restant(type: String, a: String, b: String, jour: int, duree: int) -> int:
    var k := "%s|%s" % [type, cle(a, b)]
    if not repos.has(k):
        return 0
    return maxi(0, int(repos[k]) + duree - jour)

func noter_repos(type: String, a: String, b: String, jour: int) -> void:
    repos["%s|%s" % [type, cle(a, b)]] = jour

func vers_dict() -> Dictionary:
    return {"relations": relations, "repos": repos}

func depuis_dict(d: Dictionary, ids: Array) -> void:
    if d.is_empty():
        etat_initial(ids)
        return
    relations = {}
    repos = {}
    for k in d.get("repos", {}):
        repos[str(k)] = int(d["repos"][k])
    for k in d.get("relations", {}):
        var r: Dictionary = d["relations"][k]
        relations[str(k)] = {"score": float(r.get("score", 0.0)), "alliance": bool(r.get("alliance", false)), "memoire": r.get("memoire", [])}
