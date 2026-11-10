extends RefCounted

# Recettes et transformations (v0.3.9) : data/recettes.json.
# Une recette consomme des matières et du combustible, demande du travail,
# et donne un produit, des sous-produits et des pertes ; le bilan de masse
# doit tomber juste. Rien n'est produit gratuitement.
# Pour lancer une recette, il faut à la fois :
#   recette connue, matières et combustible en stock, outil, bâtiment,
#   bonne saison, et un adulte libre ("sans métier") pour travailler.
# Les matières sont réservées (retirées) au lancement ; le produit arrive
# quand le travail est fini. Le savoir-faire individuel viendra à l'étape 4.

signal evenement(texte)

const FICHIER := "res://data/recettes.json"

var definitions := {}
var masses := {}            # masse d'une unité, d'après le catalogue
var connues: Array = []
var commandes: Array = []   # {recette, reste} : reste = jours de travail restants

func _init() -> void:
    var d = JSON.parse_string(FileAccess.get_file_as_string(FICHIER))
    if typeof(d) == TYPE_DICTIONARY:
        definitions = d.get("recettes", {})
    var c = JSON.parse_string(FileAccess.get_file_as_string("res://data/produits.json"))
    if typeof(c) == TYPE_DICTIONARY:
        for id in c.get("produits", {}):
            masses[id] = float(c["produits"][id].get("masse_unite_kg", 1.0))
    etat_initial()

func etat_initial() -> void:
    connues = []
    commandes = []
    for id in definitions:
        if bool(definitions[id].get("connue_au_depart", false)):
            connues.append(id)

func apprendre(id: String) -> void:
    if definitions.has(id) and not connues.has(id):
        connues.append(id)
        evenement.emit("Le clan sait maintenant faire : %s." % definitions[id]["nom"])

# ---------- Bilan de masse ----------

func masse(id: String, q: float) -> float:
    return q * float(masses.get(id, 1.0))

func bilan_masse(id: String) -> Dictionary:
    var r: Dictionary = definitions[id]
    var entree := 0.0
    var sortie := 0.0
    for m in r.get("terrain", {}):
        entree += masse(m, float(r["terrain"][m]))
    for m in r["entrees"]:
        entree += masse(m, float(r["entrees"][m]))
    for m in r["combustible"]:
        entree += masse(m, float(r["combustible"][m]))
    for m in r["sorties"]:
        sortie += masse(m, float(r["sorties"][m]))
    for m in r["sous_produits"]:
        sortie += masse(m, float(r["sous_produits"][m]))
    var pertes := 0.0
    for raison in r["pertes"]:
        pertes += float(r["pertes"][raison])
    return {"entree": entree, "sortie": sortie, "pertes": pertes, "ecart": entree - sortie - pertes}

# ---------- Peut-on la faire ? ----------

func _libres(pop, jour: int) -> Array:
    var l := []
    for h in pop.habitants:
        if h["metier"] == "sans métier" and pop.age(h, jour) >= pop.AGE_ADULTE:
            l.append(h)
    return l

# Renvoie l'état détaillé et la liste des raisons qui empêchent la recette.
func etat(id: String, pop, res, cons, jour: int, nombre := 1) -> Dictionary:
    var e := {"connue": true, "matieres": true, "outil": true, "batiment": true, "saison": true, "travailleur": true, "possible": false, "raisons": []}
    if not definitions.has(id):
        e["raisons"].append("Recette inconnue du catalogue.")
        return e
    var r: Dictionary = definitions[id]
    if not connues.has(id):
        e["connue"] = false
        e["raisons"].append("Le clan ne sait pas encore la faire%s." % ((" (découverte : %s)" % r["decouverte"]) if r["decouverte"] != "" else ""))
    for groupe in ["entrees", "combustible"]:
        for m in r[groupe]:
            var besoin: float = float(r[groupe][m]) * nombre
            if res.quantite(m) + 0.000001 < besoin:
                e["matieres"] = false
                e["raisons"].append("Il manque %.2f de %s." % [besoin - res.quantite(m), m])
    if r.get("repare", "") != "" and (res.equipement == null or not res.equipement.a_reparer(r["repare"])):
        e["matieres"] = false
        e["raisons"].append("Aucun outil à réparer : %s." % r["repare"])
    if r["outil"] != "" and res.quantite(r["outil"]) < 1.0:
        e["outil"] = false
        e["raisons"].append("Il faut un outil : %s." % r["outil"])
    if r["batiment"] != "" and cons.nombre(r["batiment"]) < 1:
        e["batiment"] = false
        e["raisons"].append("Il faut un bâtiment : %s." % r["batiment"])
    var saisons: Array = r.get("saisons", [])
    if not saisons.is_empty() and not saisons.has((jour / 30) % 12):
        e["saison"] = false
        e["raisons"].append("Pas en cette saison.")
    if _libres(pop, jour).is_empty():
        e["travailleur"] = false
        e["raisons"].append("Aucun adulte libre pour ce travail.")
    e["possible"] = e["raisons"].is_empty()
    return e

# ---------- Lancer et faire avancer ----------

# Renvoie "" si la commande est lancée, sinon la première raison du refus.
func commander(id: String, pop, res, cons, jour: int, nombre := 1) -> String:
    var e := etat(id, pop, res, cons, jour, nombre)
    if not e["possible"]:
        return e["raisons"][0]
    var r: Dictionary = definitions[id]
    for groupe in ["entrees", "combustible"]:
        for m in r[groupe]:
            res.retirer(m, float(r[groupe][m]) * nombre)
    commandes.append({"recette": id, "nombre": nombre, "reste": float(r["jours_travail"]) * nombre})
    return ""

# Chaque adulte libre donne une journée de travail, à une seule commande à la fois ;
# ce jour-là, il ne cueille pas. Un outil de recette s'use d'un jour.
func jour_passe(pop, res, jour: int) -> void:
    for h in pop.habitants:
        h.erase("occupe")
    if commandes.is_empty():
        return
    var ouvriers := _libres(pop, jour)
    for h in ouvriers:
        if commandes.is_empty():
            break
        var c: Dictionary = commandes[0]
        h["occupe"] = true
        var outil: String = definitions[c["recette"]]["outil"]
        if outil != "" and res.equipement != null:
            res.equipement.user(outil)
        c["reste"] = float(c["reste"]) - 1.0
        if float(c["reste"]) <= 0.000001:
            commandes.pop_front()
            _livrer(c, res)

func _livrer(c: Dictionary, res) -> void:
    var r: Dictionary = definitions[c["recette"]]
    var n := int(c["nombre"])
    for m in r["sorties"]:
        res.ajouter(m, float(r["sorties"][m]) * n)
    for m in r["sous_produits"]:
        res.ajouter(m, float(r["sous_produits"][m]) * n)
    if r.get("repare", "") != "" and res.equipement != null:
        for i in n:
            res.equipement.reparer(r["repare"])
    evenement.emit("Fabrication terminée : %s (x%d)." % [r["nom"], n])

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {"connues": connues, "commandes": commandes}

func depuis_dict(d: Dictionary) -> void:
    if d.is_empty():
        etat_initial()
        return
    connues = []
    for id in d.get("connues", []):
        connues.append(str(id))
    commandes = []
    for c in d.get("commandes", []):
        commandes.append({"recette": str(c["recette"]), "nombre": int(c.get("nombre", 1)), "reste": float(c["reste"])})
