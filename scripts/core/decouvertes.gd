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

# ---------- Expériences (v0.3.17 E2) ----------
# Plus aucune découverte gratuite tirée au hasard chaque mois. Une découverte
# s'obtient par une EXPÉRIENCE : des adultes quittent leur métier pendant des
# semaines, des matières sont consommées, et l'essai peut échouer.
# Une expérience devient possible quand les conditions sont réunies ET que le
# clan en ressent le besoin (pression de son domaine >= 20).
# Chance de réussite = 10 % + savoir des essayeurs + pression + essais passés,
# au plus 80 %, réduite pour les techniques difficiles (âge du fer).
# Un échec apprend quelque chose : savoir des essayeurs +2, essai suivant +8 %.
const SEUIL_POSSIBLE := 20.0     # pression minimum pour avoir l'idée d'essayer
const SEUIL_URGENCE := 40.0      # l'ordinateur essaie quand la survie l'exige
const DUREE := {"pierre": 30, "fer": 45}
const ESSAYEURS := {"pierre": 1, "fer": 2}
const DIFFICULTE := {"pierre": 1.0, "fer": 0.75}
const PART_MATIERES := 0.2       # part des matières de la découverte consommée par essai

var en_cours := {}               # {id, essayeurs: [id habitant], fin, par}
var essais := {}                 # id -> nombre d'échecs
var annoncees := {}              # id -> déjà signalée comme possible
var observees := {}              # id -> niveau d'observation chez un autre clan (0 à 3)

# Une technique vue chez un autre clan devient une idée d'expérience, et l'essai
# a plus de chances (+7 % par niveau d'observation). Observer n'est pas maîtriser.
func observer(id: String, gain: float) -> void:
    if definitions.has(id) and not connait(id):
        observees[id] = minf(3.0, float(observees.get(id, 0.0)) + gain)

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

# auto : vrai pour l'ordinateur (et le joueur en mode automatique).
func mois_passe(pop, res, recettes, jour: int, pression = null, auto := true) -> void:
    for id in possibles(pop, res, recettes, jour, pression):
        if not annoncees.get(id, false):
            annoncees[id] = true
            evenement.emit("Expérience possible : %s (%d jours, %d personne(s), réussite %d %%)." % [definitions[id]["nom"], _duree(id), _nb(id), int(chance(id, pop, pression) * 100)])
    if auto and en_cours.is_empty():
        var choix := ""
        var max_p := -1.0
        for id in possibles(pop, res, recettes, jour, pression):
            var p := _pression(id, pression)
            var urgent := p >= SEUIL_URGENCE or (_domaine(id) == "" and rng.randf() < 0.05)
            if urgent and p > max_p:
                max_p = p
                choix = id
        if choix != "":
            lancer(choix, pop, res, recettes, jour, pression, "ordinateur")
    _entretenir(pop, recettes)

func _domaine(id: String) -> String:
    return str(load("res://scripts/core/pression.gd").DOMAINE_DECOUVERTE.get(id, ""))

func _pression(id: String, pression) -> float:
    var d := _domaine(id)
    if pression == null or d == "":
        return 0.0
    return float(pression.niveaux.get(d, 0.0))

func _epoque(id: String) -> String:
    return str(definitions[id].get("epoque", "pierre"))

func _duree(id: String) -> int:
    return int(DUREE.get(_epoque(id), 30))

func _nb(id: String) -> int:
    return int(ESSAYEURS.get(_epoque(id), 1))

# Ce que le clan peut essayer maintenant.
func possibles(pop, res, recettes, jour: int, pression) -> Array:
    var l: Array = []
    for id in definitions:
        if connait(id) or (not en_cours.is_empty() and en_cours["id"] == id):
            continue
        if not manque(id, pop, res, recettes, jour).is_empty():
            continue
        if _domaine(id) != "" and _pression(id, pression) < SEUIL_POSSIBLE and float(observees.get(id, 0.0)) < 1.0:
            continue
        l.append(id)
    return l

# Meilleurs essayeurs : adultes (ni chef ni ancien) qui ont le plus de savoir utile.
func _essayeurs(id: String, pop, jour: int) -> Array:
    var cond: Dictionary = definitions[id]["conditions"].get("savoirs", {})
    var candidats: Array = []
    for h in pop.habitants:
        if pop.age(h, jour) >= pop.AGE_ADULTE and not h["metier"] in ["chef", "ancien"] and not h.has("experience") and not h.has("expedition"):
            candidats.append(h)
    candidats.sort_custom(func(a, b):
        var sa := 0.0
        var sb := 0.0
        for s in cond:
            sa += pop.savoir(a, s)
            sb += pop.savoir(b, s)
        return sa > sb)
    return candidats.slice(0, _nb(id))

func chance(id: String, pop, pression) -> float:
    var cond: Dictionary = definitions[id]["conditions"].get("savoirs", {})
    var savoir := 0.0
    for h in pop.habitants:
        var s := 0.0
        for k in cond:
            s += pop.savoir(h, k)
        savoir = maxf(savoir, s / maxf(1.0, cond.size()))
    var c := 0.10 + savoir / 250.0 + _pression(id, pression) / 250.0 + 0.08 * int(essais.get(id, 0)) + 0.07 * float(observees.get(id, 0.0))
    return clampf(c, 0.05, 0.8) * float(DIFFICULTE.get(_epoque(id), 1.0))

# Lance une expérience. Renvoie "" si elle commence.
func lancer(id: String, pop, res, recettes, jour: int, pression, par := "joueur") -> String:
    if not en_cours.is_empty():
        return "Une expérience est déjà en cours."
    if not possibles(pop, res, recettes, jour, pression).has(id):
        return "Cette expérience n'est pas possible maintenant."
    var gens := _essayeurs(id, pop, jour)
    if gens.size() < _nb(id):
        return "Pas assez d'adultes disponibles."
    var mat: Dictionary = definitions[id]["conditions"].get("matieres", {})
    for m in mat:
        res.retirer(m, float(mat[m]) * PART_MATIERES, "experience")
    var ids: Array = []
    for h in gens:
        h["experience"] = id
        ids.append(int(h["id"]))
    en_cours = {"id": id, "essayeurs": ids, "fin": jour + _duree(id), "par": par}
    evenement.emit("Expérience lancée : %s (%s, %d jours)." % [definitions[id]["nom"], ", ".join(gens.map(func(h): return h["prenom"])), _duree(id)])
    return ""

# Chaque jour, APRÈS les recettes : les essayeurs ne travaillent pas à leur métier.
func jour_passe(pop, recettes, jour: int, pression) -> void:
    if en_cours.is_empty():
        return
    var gens: Array = []
    for h in pop.habitants:
        if en_cours["essayeurs"].has(int(h["id"])):
            h["occupe"] = true
            gens.append(h)
    if gens.is_empty():
        en_cours = {}
        return
    if jour < int(en_cours["fin"]):
        return
    var id: String = en_cours["id"]
    var reussi := rng.randf() < chance(id, pop, pression)
    for h in gens:
        h.erase("experience")
        if not reussi:
            for s in definitions[id]["conditions"].get("savoirs", {}):
                pop.donner_savoir(h, s, minf(100.0, pop.savoir(h, s) + 2.0))
    en_cours = {}
    if reussi:
        _decouvrir(id, pop, recettes, jour, "expérience de %s" % ", ".join(gens.map(func(h): return h["prenom"])))
    else:
        essais[id] = int(essais.get(id, 0)) + 1
        evenement.emit("L'expérience « %s » a échoué (essai n° %d). Les essayeurs ont appris : le prochain essai aura plus de chances." % [definitions[id]["nom"], int(essais[id])])

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
    return {"connues": connues, "graine": str(rng.seed), "etat": str(rng.state), "en_cours": en_cours, "essais": essais, "annoncees": annoncees, "observees": observees}

func depuis_dict(d: Dictionary) -> void:
    en_cours = d.get("en_cours", {})
    if en_cours.has("essayeurs"):
        en_cours["essayeurs"] = en_cours["essayeurs"].map(func(x): return int(x))
    essais = {}
    for k in d.get("essais", {}):
        essais[str(k)] = int(d["essais"][k])
    annoncees = d.get("annoncees", {})
    observees = d.get("observees", {})
    connues = {}
    for id in d.get("connues", {}):
        var x: Dictionary = d["connues"][id]
        connues[str(id)] = {"jour": int(x.get("jour", 0)), "origine": str(x.get("origine", "")), "mois_sans_pratique": int(x.get("mois_sans_pratique", 0))}
    rng.seed = int(d.get("graine", "4242"))
    rng.state = int(d.get("etat", "0"))
