extends RefCounted

# Connaissances collectives et découvertes (v0.3.12) : data/decouvertes.json.
# Trois niveaux à ne pas confondre :
#   savoir individuel  : ce qu'un habitant sait faire (population.gd, 0 à 100) ;
#   connaissance du clan : les découvertes faites (ce que le clan peut transmettre) ;
#   recettes connues   : les procédés réellement disponibles (recettes.gd).
# Une découverte ne tombe pas du ciel : il faut des prérequis, au moins un habitant
# assez habile, les matières en main, de la pratique, assez de monde, puis du temps
# (une chance par mois d'expérimentation). Elle ne transmet pas le savoir à tout le
# clan : seul celui qui découvre reçoit un début de savoir ; les autres apprennent
# en pratiquant à côté de lui. Une connaissance que plus personne ne pratique se
# perd après 10 ans. On peut aussi la recevoir d'ailleurs (transmettre()).

signal evenement(texte)

const FICHIER := "res://data/decouvertes.json"
const SEUIL_OUBLI := 10.0
const MOIS_OUBLI := 120

var definitions := {}
var connues := {}          # id -> {"jour": jour, "origine": texte, "mois_sans_pratique": n}
var rng := RandomNumberGenerator.new()

func _init() -> void:
    var d = JSON.parse_string(FileAccess.get_file_as_string(FICHIER))
    if typeof(d) == TYPE_DICTIONARY:
        definitions = d.get("decouvertes", {})
    rng.seed = 4242

func connait(id: String) -> bool:
    return connues.has(id)

# Conditions encore manquantes (vide = tout est réuni).
func manque(id: String, pop, res, recettes, jour: int) -> Array:
    var m := []
    var d: Dictionary = definitions[id]
    for p in d["prerequis"]:
        if not connait(p):
            m.append("il faut d'abord : %s" % definitions[p]["nom"])
    var c: Dictionary = d["conditions"]
    for s in c.get("savoirs", {}):
        var meilleur := 0.0
        for h in pop.habitants:
            meilleur = maxf(meilleur, pop.savoir(h, s))
        if meilleur < float(c["savoirs"][s]):
            m.append("personne n'a %d en %s (meilleur : %d)" % [int(c["savoirs"][s]), s, int(meilleur)])
    for r in c.get("matieres", {}):
        if res.quantite(r) < float(c["matieres"][r]):
            m.append("il faut %d de %s en stock" % [int(c["matieres"][r]), r])
    for r in c.get("pratique", {}):
        if int(recettes.faites.get(r, 0)) < int(c["pratique"][r]):
            m.append("il faut avoir fait %d fois : %s" % [int(c["pratique"][r]), r])
    if pop.habitants.size() < int(c.get("population_min", 0)):
        m.append("il faut %d habitants" % int(c["population_min"]))
    return m

# pression (pression.gd) : la difficulté vécue rend la découverte plus probable.
func mois_passe(pop, res, recettes, jour: int, pression = null) -> void:
    for id in definitions:
        if connait(id):
            continue
        if not manque(id, pop, res, recettes, jour).is_empty():
            continue
        var chance := float(definitions[id]["chance_mois"])
        if pression != null:
            chance *= pression.facteur(id)
        if rng.randf() < chance:
            _decouvrir(id, pop, recettes, jour, "expérimentation")
    _entretenir(pop, recettes)

func _decouvrir(id: String, pop, recettes, jour: int, origine: String) -> void:
    var d: Dictionary = definitions[id]
    connues[id] = {"jour": jour, "origine": origine, "mois_sans_pratique": 0}
    for r in d["debloque"]:
        recettes.apprendre(r)
    # Le savoir de départ va à la personne la plus proche de la découverte.
    var cond_savoirs: Dictionary = d["conditions"].get("savoirs", {})
    var inventeur := {}
    for h in pop.habitants:
        if pop.age(h, jour) < pop.AGE_ADULTE:
            continue
        var score := 0.0
        for s in cond_savoirs:
            score += pop.savoir(h, s)
        if inventeur.is_empty() or score > float(inventeur.get("_score", 0.0)):
            inventeur = h
            inventeur["_score"] = score
    var nom := "le clan"
    if not inventeur.is_empty():
        inventeur.erase("_score")
        for h in pop.habitants:
            h.erase("_score")
        for s in d.get("savoir_initial", {}):
            pop.donner_savoir(inventeur, s, maxf(pop.savoir(inventeur, s), float(d["savoir_initial"][s])))
        nom = "%s %s" % [inventeur["prenom"], inventeur["nom"]]
    evenement.emit("Découverte (%s) : %s, grâce à %s." % [origine, d["nom"], nom])

# Reçue d'un autre clan, d'un migrant ou d'un marchand (plus tard).
func transmettre(id: String, pop, recettes, jour: int, origine: String) -> void:
    if definitions.has(id) and not connait(id):
        _decouvrir(id, pop, recettes, jour, origine)

# Une connaissance vit tant que quelqu'un la pratique.
func _entretenir(pop, recettes) -> void:
    for id in connues.keys():
        var cle: String = definitions.get(id, {}).get("savoir_cle", "")
        if cle == "":
            continue
        var vivant := false
        for h in pop.habitants:
            if pop.savoir(h, cle) >= SEUIL_OUBLI:
                vivant = true
                break
        var info: Dictionary = connues[id]
        info["mois_sans_pratique"] = 0 if vivant else int(info["mois_sans_pratique"]) + 1
        if int(info["mois_sans_pratique"]) >= MOIS_OUBLI:
            connues.erase(id)
            for r in definitions[id]["debloque"]:
                recettes.oublier(r)
            evenement.emit("Savoir perdu : plus personne ne pratique %s." % definitions[id]["nom"])

func vers_dict() -> Dictionary:
    return {"connues": connues, "graine": str(rng.seed), "etat": str(rng.state)}

func depuis_dict(d: Dictionary) -> void:
    connues = {}
    for id in d.get("connues", {}):
        var x: Dictionary = d["connues"][id]
        connues[str(id)] = {"jour": int(x.get("jour", 0)), "origine": str(x.get("origine", "")), "mois_sans_pratique": int(x.get("mois_sans_pratique", 0))}
    rng.seed = int(d.get("graine", "4242"))
    rng.state = int(d.get("etat", "0"))
