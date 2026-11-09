extends RefCounted

# Conseil des cinq : les cinq habitants les plus influents du clan.
# Le joueur nomme le chef parmi eux, pour un mandat de 5 ans.
# Les notes sont calculées à partir de la vie réelle de chaque personne :
#   naturel  : vivacité d'esprit, caractère (fixés une fois pour toutes)
#   acquis   : âge, années d'adulte, compétence dans son métier
#   politique: influence, loyauté, années passées au conseil (évoluent)

signal evenement(texte)

const SIEGES := 5
const AGE_MIN := 20
const MANDAT_JOURS := 5 * 360
const CARACTERES := ["prudent", "ambitieux", "impulsif", "généreux", "autoritaire", "calme"]
const NOTES := ["intelligence", "gestion", "prevoyance", "influence", "loyaute", "experience"]

var membres: Array = []
var chef_id := -1
var mandat_fin := 0
var confiance := 70.0
var rng := RandomNumberGenerator.new()

func etat_initial(pop, jour: int) -> void:
    rng.seed = 5050
    membres = []
    for h in pop.habitants:
        _profil(h, pop)
    var familles := {}
    for h in pop.habitants:
        if h["metier"] == "ancien" or pop.age(h, jour) < AGE_MIN:
            continue
        var f: int = h["famille"]
        if not familles.has(f) or pop.age(h, jour) > pop.age(familles[f], jour):
            familles[f] = h
    for f in familles:
        membres.append(int(familles[f]["id"]))
    for h in pop.habitants:
        if h["metier"] == "ancien" and membres.size() < SIEGES:
            membres.append(int(h["id"]))
    _completer(pop, jour)
    for h in pop.habitants:
        if h["metier"] == "chef":
            chef_id = int(h["id"])
    mandat_fin = jour + MANDAT_JOURS

# ---------- Profil et notes ----------

func _profil(h: Dictionary, pop) -> void:
    if h.has("vivacite"):
        return
    h["vivacite"] = rng.randi_range(35, 85)
    h["caractere"] = CARACTERES[rng.randi() % CARACTERES.size()]
    var infl := 25.0
    if h["metier"] == "chef":
        infl = 65.0
    elif h["metier"] == "ancien":
        infl = 60.0
    h["influence"] = infl
    var loy := 60.0
    match h["caractere"]:
        "généreux", "calme":
            loy += 10.0
        "ambitieux":
            loy -= 15.0
        "impulsif":
            loy -= 5.0
    h["loyaute"] = loy
    h["annees_conseil"] = 0

func notes(h: Dictionary, pop, jour: int) -> Dictionary:
    var age: int = pop.age(h, jour)
    var adulte := maxi(0, age - pop.AGE_ADULTE)
    var viv := float(h.get("vivacite", 50))
    var conseil := float(h.get("annees_conseil", 0))
    var car: String = h.get("caractere", "calme")
    var declin := maxf(0.0, (age - 65) * 1.5)
    var intel := viv + minf(adulte, 20.0) * 0.75 - declin
    var gestion := 15.0 + viv * 0.3 + minf(adulte, 20.0) * 1.0 + minf(conseil, 10.0) * 3.0
    var prev := viv * 0.5 + minf(age, 60.0) * 0.6
    match car:
        "prudent":
            prev += 15.0
        "impulsif":
            prev -= 15.0
            gestion -= 10.0
        "autoritaire":
            gestion += 10.0
        "calme":
            prev += 5.0
    return {
        "intelligence": clampf(intel, 0.0, 100.0),
        "gestion": clampf(gestion, 0.0, 100.0),
        "prevoyance": clampf(prev - declin, 0.0, 100.0),
        "influence": clampf(float(h.get("influence", 25.0)), 0.0, 100.0),
        "loyaute": clampf(float(h.get("loyaute", 60.0)), 0.0, 100.0),
        "experience": clampf(minf(adulte, 30.0) * 2.0 + float(h["competence"]) * 0.4, 0.0, 100.0),
    }

func _poids(h: Dictionary, pop, jour: int) -> float:
    return float(h.get("influence", 25.0)) + float(h["competence"]) * 0.5 + minf(pop.age(h, jour), 50.0) * 0.3

# ---------- Membres et succession ----------

func habitant(pop, id: int) -> Dictionary:
    for h in pop.habitants:
        if int(h["id"]) == id:
            return h
    return {}

func _completer(pop, jour: int) -> void:
    while membres.size() < SIEGES:
        var meilleur := {}
        for h in pop.habitants:
            if membres.has(int(h["id"])) or pop.age(h, jour) < AGE_MIN:
                continue
            _profil(h, pop)
            if meilleur.is_empty() or _poids(h, pop, jour) > _poids(meilleur, pop, jour):
                meilleur = h
        if meilleur.is_empty():
            return
        membres.append(int(meilleur["id"]))
        meilleur["influence"] = maxf(float(meilleur["influence"]), 40.0)
        evenement.emit("%s %s entre au conseil." % [meilleur["prenom"], meilleur["nom"]])

func mois_passe(pop, jour: int) -> void:
    var vivants := []
    for id in membres:
        var h := habitant(pop, id)
        if not h.is_empty():
            vivants.append(id)
        else:
            evenement.emit("Un membre du conseil est mort. Son siège est libre.")
    membres = vivants
    _completer(pop, jour)
    if chef_id >= 0 and habitant(pop, chef_id).is_empty():
        chef_id = -1
        _interim(pop, jour)
    if chef_id >= 0 and jour == mandat_fin:
        var c := habitant(pop, chef_id)
        evenement.emit("Le mandat de %s se termine : renouvelez-le ou choisissez un autre chef." % c["prenom"])
    if jour > mandat_fin:
        confiance = maxf(0.0, confiance - 1.0)
    elif confiance < 70.0:
        confiance = minf(70.0, confiance + 1.0)
    if jour % 360 == 0:
        for id in membres:
            var h := habitant(pop, id)
            h["annees_conseil"] = int(h["annees_conseil"]) + 1
            h["influence"] = minf(100.0 if id == chef_id else 85.0, float(h["influence"]) + (3.0 if id == chef_id else 1.0))

func _interim(pop, jour: int) -> void:
    var meilleur := {}
    for id in membres:
        var h := habitant(pop, id)
        if meilleur.is_empty() or float(h["influence"]) > float(meilleur["influence"]):
            meilleur = h
    if meilleur.is_empty():
        return
    _installer(meilleur, pop)
    mandat_fin = jour
    evenement.emit("Le chef est mort. %s assure l'intérim : choisissez un nouveau chef." % meilleur["prenom"])

# ---------- Décisions du joueur ----------

# Renvoie "" si c'est fait, sinon la raison du refus.
func nommer(id: int, pop, jour: int) -> String:
    if not membres.has(id):
        return "Seul un membre du conseil peut devenir chef."
    var h := habitant(pop, id)
    if h.is_empty():
        return "Cette personne n'est plus en vie."
    if id == chef_id:
        return "C'est déjà le chef. Utilisez Renouveler."
    if chef_id >= 0 and jour < mandat_fin:
        confiance = maxf(0.0, confiance - 10.0)
        var ancien := habitant(pop, chef_id)
        if not ancien.is_empty():
            ancien["loyaute"] = maxf(0.0, float(ancien["loyaute"]) - 20.0)
    _installer(h, pop)
    mandat_fin = jour + MANDAT_JOURS
    evenement.emit("%s %s est nommé chef pour 5 ans." % [h["prenom"], h["nom"]])
    return ""

func renouveler(pop, jour: int) -> String:
    if chef_id < 0:
        return "Il n'y a pas de chef à renouveler."
    if jour < mandat_fin - 360:
        return "On ne peut renouveler que pendant la dernière année du mandat."
    mandat_fin = maxi(jour, mandat_fin) + MANDAT_JOURS
    var h := habitant(pop, chef_id)
    h["loyaute"] = minf(100.0, float(h["loyaute"]) + 5.0)
    evenement.emit("Le mandat de %s est renouvelé pour 5 ans." % h["prenom"])
    return ""

func _installer(h: Dictionary, pop) -> void:
    if chef_id >= 0:
        var ancien := habitant(pop, chef_id)
        if not ancien.is_empty() and ancien["metier"] == "chef":
            ancien["metier"] = "sans métier"
    if pop.postes.has(h["metier"]):
        pop.postes[h["metier"]] = maxi(0, int(pop.postes[h["metier"]]) - 1)
    h["metier"] = "chef"
    chef_id = int(h["id"])

func annees_restantes(jour: int) -> float:
    return maxf(0.0, (mandat_fin - jour) / 360.0)

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {"membres": membres, "chef_id": chef_id, "mandat_fin": mandat_fin, "confiance": confiance, "graine": str(rng.seed), "etat": str(rng.state)}

func depuis_dict(d: Dictionary, pop, jour: int) -> void:
    if d.is_empty():
        etat_initial(pop, jour)
        return
    membres = []
    for id in d.get("membres", []):
        membres.append(int(id))
    chef_id = int(d.get("chef_id", -1))
    mandat_fin = int(d.get("mandat_fin", jour + MANDAT_JOURS))
    confiance = float(d.get("confiance", 70.0))
    rng.seed = int(d.get("graine", "5050"))
    rng.state = int(d.get("etat", "0"))
    for h in pop.habitants:
        if h.has("vivacite"):
            h["vivacite"] = int(h["vivacite"])
            h["annees_conseil"] = int(h["annees_conseil"])
            h["influence"] = float(h["influence"])
            h["loyaute"] = float(h["loyaute"])
