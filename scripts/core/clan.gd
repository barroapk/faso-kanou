extends RefCounted

# Un clan voisin, dirigé par l'ordinateur (v0.3.14).
# Il utilise EXACTEMENT les mêmes modules que le clan du joueur : population,
# ressources, construction, besoins, conseil, recettes, outils, découvertes,
# comptabilité. Rien n'est produit autrement : seules les décisions changent
# (c'est l'ordinateur qui décide au lieu du joueur).

signal evenement(texte)

const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const CONSEIL = preload("res://scripts/core/conseil.gd")
const RECETTES = preload("res://scripts/core/recettes.gd")
const EQUIPEMENT = preload("res://scripts/core/equipement.gd")
const DECOUVERTES = preload("res://scripts/core/decouvertes.gd")
const ECONOMIE = preload("res://scripts/core/economie.gd")
const AGRICULTURE = preload("res://scripts/core/agriculture.gd")
const PRESSION = preload("res://scripts/core/pression.gd")
const TERRITOIRE = preload("res://scripts/core/territoire.gd")
const CLOTURES = preload("res://scripts/core/clotures.gd")
const ROUTES = preload("res://scripts/core/routes.gd")

var id := ""
var nom := ""
var origine := ""
var chef_fixe := {}
var regne := 0
var outils_voulus := {}

var population
var ressources
var construction
var besoins
var conseil
var recettes
var equipement
var decouvertes
var economie
var agriculture
var pression
var territoire
var clotures
var routes

func _modules() -> void:
    population = POPULATION.new()
    ressources = RESSOURCES.new()
    construction = CONSTRUCTION.new()
    besoins = BESOINS.new()
    besoins.mode = "auto"
    conseil = CONSEIL.new()
    recettes = RECETTES.new()
    equipement = EQUIPEMENT.new()
    ressources.equipement = equipement
    decouvertes = DECOUVERTES.new()
    construction.connaissances = decouvertes
    economie = ECONOMIE.new()
    agriculture = AGRICULTURE.new()
    pression = PRESSION.new()
    territoire = TERRITOIRE.new()
    agriculture.territoire = territoire
    clotures = CLOTURES.new()
    agriculture.clotures = clotures
    routes = ROUTES.new()
    agriculture.routes = routes
    ressources.routes = routes
    ressources.construction = construction

func _identite(cle: String, fiche: Dictionary) -> void:
    id = cle
    nom = fiche.get("nom", cle)
    origine = fiche.get("origine", "")
    chef_fixe = fiche.get("chef_fixe", {})
    outils_voulus = fiche.get("outils", {})
    agriculture.choisir_ile(fiche.get("ile", "kossi"))
    routes.installer(agriculture.ile)
    ressources.richesse = agriculture.ile.get("richesse", {})

func creer(cle: String, fiche: Dictionary, jour: int) -> void:
    _modules()
    _identite(cle, fiche)
    var graine := int(fiche.get("graine", 7000))
    population.creer_depuis_fiche(fiche, jour)
    construction.batiments = []
    construction.chantiers = []
    for i in int(fiche.get("huttes", 4)):
        construction.batiments.append({"type": "hutte", "niveau": 1, "etat": 100})
    for i in int(fiche.get("greniers", 0)):
        construction.batiments.append({"type": "grenier", "niveau": 1, "etat": 100})
    var st: Dictionary = fiche.get("stocks", {})
    for r in ["eau", "bois", "sel"]:
        ressources.stocks[r] = float(st.get(r, ressources.stocks[r]))
    for s in fiche.get("semences", {}):
        agriculture.semences[s] = float(fiche["semences"][s])
    var k: float = float(st.get("nourriture", 300.0)) / maxf(1.0, ressources.total_aliments())
    for a in ressources.aliments:
        ressources.aliments[a] = float(ressources.aliments[a]) * k
    ressources.stocks["nourriture"] = ressources.total_aliments()
    equipement.instances = []
    for o in outils_voulus:
        equipement.ajouter(o, int(outils_voulus[o]))
    decouvertes.rng.seed = graine + 2
    for d in fiche.get("connaissances", []):
        decouvertes.connues[d] = {"jour": jour, "origine": "savoir ancien du clan", "mois_sans_pratique": 0}
        for r in decouvertes.definitions[d]["debloque"]:
            if not recettes.connues.has(r):
                recettes.connues.append(r)
    # Territoire acquis au fil des années (1 parcelle + 1 par décennie), assez pour ses champs.
    territoire.installer(agriculture.ile_id, agriculture.ile, 1 + int(float(fiche.get("anciennete", 0)) / 10.0) + int(ceil(float(fiche.get("champs_ha", 0.0)) / 30.0)), jour)
    # Champs déjà défrichés d'un clan ancien qui cultive.
    if float(fiche.get("champs_ha", 0.0)) > 0.0:
        while agriculture.surface_cultivee() < float(fiche["champs_ha"]) - 0.1:
            if agriculture.creer_champ(float(fiche["champs_ha"]) - agriculture.surface_cultivee()) != "":
                break
        for ch in agriculture.champs:
            ch["defriche"] = true
    # Un clan installé avant le joueur a déjà ses sentiers (eau, forêt, champs).
    if int(fiche.get("anciennete", 0)) > 0 or not chef_fixe.is_empty():
        routes.sentiers_existants(["eau", "foret"] + agriculture.champs.map(func(c): return "parcelle_" + str(c["parcelle"])))
    conseil.etat_initial(population, jour, graine + 1)
    _appliquer_chef_fixe(false)
    economie.commencer(ressources)

func vivant() -> bool:
    return not population.habitants.is_empty()

func nom_du_chef() -> String:
    var h: Dictionary = conseil.habitant(population, conseil.chef_id)
    if h.is_empty():
        return "aucun"
    return "%s %s" % [h["nom"], h["prenom"]]

# Vivres d'une délégation envoyée en visite (prélevés sur la nourriture).
func expeditions_vivres(kgem: float) -> void:
    var total: float = ressources.total_aliments()
    for a in ressources.aliments.keys():
        var part: float = float(ressources.aliments[a]) * ressources.facteur(a) / total
        ressources.retirer(a, kgem * part / ressources.facteur(a), "expedition")

func travail_batisseurs() -> float:
    var t := 0.0
    for h in population.habitants:
        if h["metier"] == "bâtisseur":
            t += (0.6 + float(h["competence"]) / 100.0 * 0.8) * float(h.get("bonus_outil", 1.0))
    return t

# ---------- Temps ----------

func jour_passe(jour: int, pluie: bool) -> void:
    if not vivant():
        return
    var chantier: bool = not construction.chantiers.is_empty()
    recettes.jour_passe(population, ressources, jour)
    decouvertes.jour_passe(population, recettes, jour, pression)
    equipement.jour_passe(population, chantier)
    ressources.jour_passe(population, jour, pluie, chantier)
    construction.jour_passe(travail_batisseurs())
    if construction.chantiers.is_empty():
        if clotures.en_travaux():
            clotures.jour_passe(travail_batisseurs())
        else:
            routes.jour_passe(travail_batisseurs())
    agriculture.jour_passe(population, ressources, construction, jour, pluie)
    population.jour_passe(ressources.faim, ressources.soif, ressources.jours_sans_sel, jour)
    pression.jour_passe(ressources)

func mois_passe(jour: int, pluie: bool) -> void:
    if not vivant():
        return
    construction.mois_passe(ressources)
    clotures.mois_passe(ressources, (jour / 30) % 12)
    routes.mois_passe(ressources, (jour / 30) % 12)
    population.mois_passe(jour, ressources.stocks["nourriture"] > 100.0, int(construction.effet_total("logement")))
    conseil.mois_passe(population, jour)
    _gouverner(jour)
    besoins.mois_passe(population, ressources, construction, jour, pluie, not construction.chantiers.is_empty())
    _gerer(jour)
    agriculture.gerer_auto(population, ressources, jour, decouvertes.connait)
    if decouvertes.connait("agriculture"):
        territoire.gerer_auto(agriculture, ressources, jour, 4.0)
    routes.gerer_auto(ressources, territoire, agriculture)
    if agriculture.prochaine_recolte() > jour:
        besoins.verrou["cultivateur"] = agriculture.prochaine_recolte()
    pression.mois_passe(population, ressources, equipement, jour)
    decouvertes.mois_passe(population, ressources, recettes, jour, pression)
    economie.mois_passe(population, ressources, construction, equipement, jour)
    population.repartir(jour)
    if not vivant():
        evenement.emit("Le clan %s a disparu." % nom)

# ---------- Décisions de l'ordinateur ----------

# Chef : renouveler un bon chef, sinon nommer le meilleur gestionnaire du conseil.
# Un clan à chef fixe (BARRO FASO) choisit d'abord dans la famille fondatrice.
func _gouverner(jour: int) -> void:
    if conseil.chef_id < 0:
        return
    if conseil.interim or jour >= conseil.mandat_fin:
        var meilleur := -1
        var score_max := -1.0
        for mid in conseil.membres:
            var h: Dictionary = conseil.habitant(population, mid)
            if h.is_empty():
                continue
            var n: Dictionary = conseil.notes(h, population, jour)
            var score: float = float(n["gestion"]) + float(n["intelligence"]) + float(n["influence"]) * 0.5
            if not chef_fixe.is_empty() and int(h["famille"]) == 1:
                score += 50.0
                if h["sexe"] == "H":
                    score += 30.0   # « Clavers » est un prénom d'homme
            if score > score_max:
                score_max = score
                meilleur = mid
        if conseil.interim or meilleur != conseil.chef_id:
            if meilleur >= 0:
                conseil.nommer(meilleur, population, jour)
        else:
            conseil.renouveler(population, jour)
    _appliquer_chef_fixe(true)

# Le chef de BARRO FASO porte toujours le nom « BARRO Clavers ».
func _appliquer_chef_fixe(annoncer: bool) -> void:
    if chef_fixe.is_empty() or conseil.chef_id < 0:
        return
    var h: Dictionary = conseil.habitant(population, conseil.chef_id)
    if h.is_empty() or (h["prenom"] == chef_fixe["prenom"] and h["nom"] == chef_fixe["nom"]):
        return
    if not h.has("nom_naissance"):
        h["nom_naissance"] = "%s %s" % [h["nom"], h["prenom"]]
    h["prenom"] = chef_fixe["prenom"]
    h["nom"] = chef_fixe["nom"]
    regne += 1
    if annoncer:
        evenement.emit("%s devient chef de %s sous le nom de %s %s." % [h["nom_naissance"], nom, chef_fixe["nom"], chef_fixe["prenom"]])

# Logement, outils, sel : comme un joueur prudent, avec les mêmes règles.
func _gerer(jour: int) -> void:
    # Avant la récolte : un grenier si la récolte attendue ne tiendra pas.
    if construction.chantiers.is_empty() and agriculture.prochaine_recolte() > jour:
        var attendu := 0.0
        for ch in agriculture.champs:
            if ch["etat"] == "seme":
                attendu += float(agriculture.cultures[ch["culture"]]["rendement"]) * float(ch["ha"]) * float(ch["fertilite"])
        if ressources.stocks["nourriture"] + attendu > ressources.capacite("nourriture"):
            construction.lancer("grenier", -1, ressources)
    if construction.chantiers.is_empty():
        for p in besoins.problemes:
            if p["type"] == "logement" and p["solutions"].size() > 0:
                besoins.appliquer(p["solutions"][0])
                break
    if ressources.quantite("pierre") < 20.0:
        recettes.commander("ramasser_pierre", population, ressources, construction, jour)
    for o in outils_voulus:
        if equipement.nombre(o) < int(outils_voulus[o]):
            recettes.commander(equipement.definitions[o]["recette"], population, ressources, construction, jour)
        elif equipement.etat_moyen(o) < 0.3 and equipement.a_reparer(o):
            recettes.commander(equipement.definitions[o]["reparation"], population, ressources, construction, jour)
    if ressources.stocks["sel"] < 5.0 and ressources.quantite("cendres") >= 10.0:
        if ressources.quantite("canari") < 1.0:
            if ressources.quantite("argile") < 8.0:
                recettes.commander("creuser_argile", population, ressources, construction, jour)
            recettes.commander("canari", population, ressources, construction, jour)
        else:
            recettes.commander("sel_vegetal", population, ressources, construction, jour)

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {
        "id": id, "nom": nom, "origine": origine,
        "chef_fixe": chef_fixe, "regne": regne, "outils_voulus": outils_voulus,
        "population": population.vers_dict(),
        "ressources": ressources.vers_dict(),
        "construction": construction.vers_dict(),
        "besoins": besoins.vers_dict(),
        "conseil": conseil.vers_dict(),
        "recettes": recettes.vers_dict(),
        "equipement": equipement.vers_dict(),
        "decouvertes": decouvertes.vers_dict(),
        "economie": economie.vers_dict(),
        "agriculture": agriculture.vers_dict(),
        "pression": pression.vers_dict(),
        "territoire": territoire.vers_dict(),
        "clotures": clotures.vers_dict(),
        "routes": routes.vers_dict(),
    }

func depuis_dict(d: Dictionary, jour: int) -> void:
    _modules()
    id = str(d.get("id", ""))
    nom = str(d.get("nom", id))
    origine = str(d.get("origine", ""))
    chef_fixe = d.get("chef_fixe", {})
    regne = int(d.get("regne", 0))
    outils_voulus = {}
    for o in d.get("outils_voulus", {}):
        outils_voulus[str(o)] = int(d["outils_voulus"][o])
    population.depuis_dict(d.get("population", {}))
    ressources.depuis_dict(d.get("ressources", {}))
    construction.depuis_dict(d.get("construction", {}))
    besoins.depuis_dict(d.get("besoins", {}))
    conseil.depuis_dict(d.get("conseil", {}), population, jour)
    recettes.depuis_dict(d.get("recettes", {}))
    equipement.depuis_dict(d.get("equipement", {}))
    decouvertes.depuis_dict(d.get("decouvertes", {}))
    economie.depuis_dict(d.get("economie", {}), ressources)
    agriculture.depuis_dict(d.get("agriculture", {}))
    pression.depuis_dict(d.get("pression", {}))
    territoire.depuis_dict(d.get("territoire", {}))
    clotures.depuis_dict(d.get("clotures", {}))
    routes.depuis_dict(d.get("routes", {}))
    routes.installer(agriculture.ile)
    if not d.has("routes"):
        routes.sentiers_existants(["eau", "foret"] + agriculture.champs.map(func(c): return "parcelle_" + str(c.get("parcelle", ""))).filter(func(x): return x != "parcelle_"))
    territoire.installer(agriculture.ile_id, agriculture.ile, 1 + int(ceil(agriculture.surface_cultivee() / 30.0)), jour)
    ressources.richesse = agriculture.ile.get("richesse", {})
