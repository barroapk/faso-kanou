extends Node

const DOSSIER := "user://"
const FICHIER := "partie.json"
const VERSION := 4
const TEMPS = preload("res://scripts/core/temps.gd")
const POPULATION = preload("res://scripts/core/population.gd")
const RESSOURCES = preload("res://scripts/core/ressources.gd")
const CONSTRUCTION = preload("res://scripts/core/construction.gd")
const BESOINS = preload("res://scripts/core/besoins.gd")
const CONSEIL = preload("res://scripts/core/conseil.gd")
const CHEF = preload("res://scripts/core/chef.gd")
const MIGRATION = preload("res://scripts/core/migration.gd")
const RECETTES = preload("res://scripts/core/recettes.gd")
const EQUIPEMENT = preload("res://scripts/core/equipement.gd")
const DECOUVERTES = preload("res://scripts/core/decouvertes.gd")
const ECONOMIE = preload("res://scripts/core/economie.gd")
const CLAN = preload("res://scripts/core/clan.gd")
const DIPLOMATIE = preload("res://scripts/core/diplomatie.gd")
const MARCHE = preload("res://scripts/core/marche.gd")
const CARAVANES = preload("res://scripts/core/caravanes.gd")
const AGRICULTURE = preload("res://scripts/core/agriculture.gd")
const MONDE = preload("res://scripts/core/monde.gd")
const PRESSION = preload("res://scripts/core/pression.gd")
const TERRITOIRE = preload("res://scripts/core/territoire.gd")
const CLOTURES = preload("res://scripts/core/clotures.gd")
const ROUTES = preload("res://scripts/core/routes.gd")
const EXPEDITIONS = preload("res://scripts/core/expeditions.gd")
const GISEMENTS = preload("res://scripts/core/gisements.gd")

var temps
var population
var ressources
var construction
var besoins
var conseil
var chef
var migration
var recettes
var equipement
var decouvertes
var economie
var voisins: Array = []
var diplomatie
var marche
var caravanes
var agriculture
var pression
var territoire
var clotures
var routes
var expeditions
var gisements
var ile_joueur := ""
var ile_confirmee := false   # faux : l'écran de choix de l'île s'affiche
var graine_monde := 0        # tirée à chaque nouvelle partie, sauvegardée

func _ready() -> void:
    if not _charger(FICHIER) and not _charger(FICHIER + ".bak"):
        _nouvelle()
    _brancher()

func _creer_modules() -> void:
    temps = TEMPS.new()
    population = POPULATION.new()
    ressources = RESSOURCES.new()
    construction = CONSTRUCTION.new()
    besoins = BESOINS.new()
    conseil = CONSEIL.new()
    chef = CHEF.new()
    migration = MIGRATION.new()
    migration.initialiser(2026)
    recettes = RECETTES.new()
    equipement = EQUIPEMENT.new()
    ressources.equipement = equipement
    decouvertes = DECOUVERTES.new()
    construction.connaissances = decouvertes
    economie = ECONOMIE.new()
    diplomatie = DIPLOMATIE.new()
    marche = MARCHE.new()
    caravanes = CARAVANES.new()
    agriculture = AGRICULTURE.new()
    pression = PRESSION.new()
    territoire = TERRITOIRE.new()
    agriculture.territoire = territoire
    clotures = CLOTURES.new()
    agriculture.clotures = clotures
    routes = ROUTES.new()
    agriculture.routes = routes
    ressources.routes = routes
    expeditions = EXPEDITIONS.new()
    gisements = GISEMENTS.new()
    marche.caravanes = caravanes
    voisins = []
    ressources.construction = construction

func _nouvelle() -> void:
    _creer_modules()
    if ile_joueur == "" or not iles_au_choix().has(ile_joueur):
        ile_joueur = iles_au_choix()[0]
    _installer_ile()
    population.creer_clan_initial(temps.jour_total)
    construction.etat_initial()
    conseil.etat_initial(population, temps.jour_total)
    economie.commencer(ressources)
    _creer_voisins()

# Clans voisins (data/clans.json) et relations de départ.
func _creer_voisins() -> void:
    voisins = []
    var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/clans.json"))
    if typeof(d) != TYPE_DICTIONARY:
        return
    var ids := ["joueur"]
    var noms_pris := ["BARRO", "KONATÉ"]
    for cle in d.get("clans", {}):
        var c = CLAN.new()
        c.creer(cle, d["clans"][cle], temps.jour_total)
        voisins.append(c)
        ids.append(cle)
    # Toutes les autres îles sont déjà habitées (aucune île vide).
    if graine_monde == 0:
        graine_monde = randi_range(1, 999999)
    var rng := RandomNumberGenerator.new()
    rng.seed = graine_monde
    var iles: Dictionary = AGRICULTURE.catalogue_iles()
    for ile_id in iles:
        if ile_id == ile_joueur or str(iles[ile_id].get("clan", "")) != "":
            continue
        var fiche: Dictionary = MONDE.generer(ile_id, iles[ile_id], rng, noms_pris)
        var c = CLAN.new()
        c.creer("clan_" + ile_id, fiche, temps.jour_total)
        voisins.append(c)
        ids.append(c.id)
    diplomatie.etat_initial(ids)

# Tous les clans pour le marché : [id, objet]. Le joueur, c'est Civilisation.
func _clans() -> Array:
    var l: Array = [["joueur", self]]
    for c in voisins:
        l.append([c.id, c])
    return l

func _ids_voisins() -> Array:
    return voisins.map(func(c): return c.id)

func _clan(cle: String):
    return self if cle == "joueur" else voisin(cle)

# Le joueur achète (acheteur = "joueur") ou vend (vendeur = "joueur").
func devis_commerce(acheteur: String, vendeur: String, produit: String, q: float, paiement := "") -> Dictionary:
    var a = _clan(acheteur)
    var b = _clan(vendeur)
    if a == null or b == null:
        return {"possible": false, "raison": "Clan inconnu."}
    return marche.devis(a, b, produit, q, temps.jour_total, paiement)

func commercer(acheteur: String, vendeur: String, produit: String, q: float, paiement := "") -> String:
    var d := devis_commerce(acheteur, vendeur, produit, q, paiement)
    return marche.conclure(_clan(acheteur), acheteur, _clan(vendeur), vendeur, d, temps.jour_total, diplomatie)

# Îles libres, que le joueur peut choisir (data/iles.json, "clan" vide).
func iles_au_choix() -> Array:
    var l: Array = []
    var iles: Dictionary = AGRICULTURE.catalogue_iles()
    for id in iles:
        if str(iles[id].get("clan", "")) == "":
            l.append(id)
    return l

func _installer_ile() -> void:
    agriculture.choisir_ile(ile_joueur)
    routes.installer(agriculture.ile)
    expeditions.depart(ile_joueur)
    gisements.installer(agriculture.ile)
    # Le village de départ : 1 parcelle, plus ce qu'il faut pour les champs d'une ancienne sauvegarde.
    territoire.installer(ile_joueur, agriculture.ile, 1 + int(ceil(agriculture.surface_cultivee() / 30.0)), temps.jour_total)
    ressources.richesse = agriculture.ile.get("richesse", {})

# Expériences du joueur : ce qu'il peut essayer, et lancer un essai.
func experiences_possibles() -> Array:
    return decouvertes.possibles(population, ressources, recettes, temps.jour_total, pression)

func lancer_experience(id: String) -> String:
    return decouvertes.lancer(id, population, ressources, recettes, temps.jour_total, pression, "joueur")

# Territoire du joueur : acquérir une parcelle voisine.
func acquerir_parcelle(x: int, z: int) -> String:
    return territoire.acheter(Vector2i(x, z), ressources, temps.jour_total)

# Agriculture du joueur : créer un champ (hectares) et le semer.
func creer_champ(ha: float, parcelle := "") -> String:
    return agriculture.creer_champ(ha, parcelle)

# Clôtures du joueur : cible = "village" ou "champ_<id>".
func cloturer(cible: String, niveau: String) -> String:
    return clotures.construire(cible, niveau, agriculture, construction, ressources)

func changer_portes(cible: String, delta: int) -> String:
    return clotures.changer_portes(cible, delta, ressources)

# ---------- Expéditions et visites ----------

func _clans_par_ile() -> Dictionary:
    var d := {}
    for c in voisins:
        if c.vivant():
            d[c.agriculture.ile_id] = [c.id, c]
    return d

func prospecter() -> String:
    return gisements.prospecter(population, temps.jour_total)

func ouvrir_site(type: String) -> String:
    return gisements.ouvrir(type, ressources, routes, population)

func lancer_expedition(type: String, cible := "") -> String:
    return expeditions.lancer(type, cible, ile_joueur, population, ressources, temps.jour_total)

# Les clans de l'ordinateur se rendent aussi visite (environ une fois tous les
# 3 ans, quand ils ont des vivres) : même règle d'amitié et d'observation.
func _visites_ordinateur() -> void:
    var par_ile := _clans_par_ile()
    for c in voisins:
        if not c.vivant() or randf() > 0.03 or c.ressources.total_aliments() < 100.0:
            continue
        var autres: Array = par_ile.keys().filter(func(i): return i != c.agriculture.ile_id)
        if autres.is_empty():
            continue
        var cible: String = autres[randi() % autres.size()]
        var autre = par_ile[cible][1]
        c.expeditions_vivres(60.0)
        diplomatie.noter(c.id, autre.id, "visite", 4.0, "visite d'une délégation", temps.jour_total)
        var niveau: float = expeditions.OBSERVATION.get(diplomatie.etat(c.id, autre.id), 1.0)
        for t in autre.decouvertes.connues:
            c.decouvertes.observer(t, niveau)

# Routes du joueur : destination = "eau", "foret", "carriere", "mine", "port" ou "parcelle_x,z".
func construire_route(dest: String, niveau: String) -> String:
    return routes.construire(dest, niveau, ressources, territoire)

func amender_champ(id_champ: int) -> String:
    return agriculture.amender(id_champ, ressources)

func semer(id_champ: int, culture: String) -> String:
    return agriculture.semer(id_champ, culture, ressources, temps.jour_total, decouvertes.connait)

func voisin(cle: String):
    for c in voisins:
        if c.id == cle:
            return c
    return null

func _brancher() -> void:
    temps.nouveau_jour.connect(_jour_passe)
    temps.nouveau_mois.connect(_mois_passe)

# Le joueur choisit son île parmi les îles libres (les rivaux ont déjà la leur).
func nouvelle_partie(ile := "") -> void:
    ile_joueur = ile
    graine_monde = 0
    ile_confirmee = ile != ""
    _nouvelle()
    _brancher()
    sauvegarder()
    get_tree().reload_current_scene()

func travail_batisseurs() -> float:
    var t := 0.0
    for h in population.habitants:
        if h["metier"] == "bâtisseur":
            t += (0.6 + float(h["competence"]) / 100.0 * 0.8) * float(h.get("bonus_outil", 1.0))
    return t

# Décisions du joueur sur les propositions du chef (écran du chef, v0.3.4).
func appliquer_proposition(cle: String, index: int) -> String:
    besoins.actualiser(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), not construction.chantiers.is_empty())
    var raison: String = chef.appliquer_proposition(cle, index, besoins, temps.jour_total)
    if raison == "":
        population.repartir(temps.jour_total)
    return raison

# Lancer une fabrication (pour l'écran d'artisanat à venir).
func commander_recette(id: String, nombre := 1) -> String:
    return recettes.commander(id, population, ressources, construction, temps.jour_total, nombre)

func ignorer_alerte(cle: String) -> String:
    return chef.ignorer(cle, temps.jour_total)

func _jour_passe() -> void:
    var chantier_actif: bool = not construction.chantiers.is_empty()
    recettes.jour_passe(population, ressources, temps.jour_total)
    decouvertes.jour_passe(population, recettes, temps.jour_total, pression)
    expeditions.jour_passe(population, temps.jour_total, ile_joueur, _clans_par_ile(), "joueur", self, diplomatie)
    gisements.jour_passe(population, ressources, routes, temps.jour_total, expeditions.rng)
    equipement.jour_passe(population, chantier_actif)
    ressources.jour_passe(population, temps.jour_total, temps.saison_des_pluies(), chantier_actif)
    construction.jour_passe(travail_batisseurs())
    if construction.chantiers.is_empty():
        if clotures.en_travaux():
            clotures.jour_passe(travail_batisseurs())
        else:
            routes.jour_passe(travail_batisseurs())
    agriculture.jour_passe(population, ressources, construction, temps.jour_total, temps.saison_des_pluies())
    population.jour_passe(ressources.faim, ressources.soif, ressources.jours_sans_sel, temps.jour_total)
    pression.jour_passe(ressources)
    for c in voisins:
        c.jour_passe(temps.jour_total, temps.saison_des_pluies())
    caravanes.jour_passe(_clan, temps.jour_total)
    if temps.jour_total % chef.REVUE_JOURS == 0:
        besoins.actualiser(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), chantier_actif)
        chef.revue(conseil, population, besoins, temps.jour_total)
    if population.habitants.is_empty(): temps.vitesse = 0

func _mois_passe() -> void:
    construction.mois_passe(ressources)
    clotures.mois_passe(ressources, temps.mois())
    routes.mois_passe(ressources, temps.mois())
    var logement: float = construction.effet_total("logement")
    population.mois_passe(temps.jour_total, ressources.stocks["nourriture"] > 100.0, int(logement))
    conseil.mois_passe(population, temps.jour_total)
    besoins.mois_passe(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), not construction.chantiers.is_empty())
    if besoins.mode == "auto":
        agriculture.gerer_auto(population, ressources, temps.jour_total, decouvertes.connait)
        if decouvertes.connait("agriculture"):
            territoire.gerer_auto(agriculture, ressources, temps.jour_total, 4.0)
        routes.gerer_auto(ressources, territoire, agriculture)
    if agriculture.prochaine_recolte() > temps.jour_total:
        besoins.verrou["cultivateur"] = agriculture.prochaine_recolte()
    migration.mois_passe(population, ressources, construction, temps.jour_total)
    pression.mois_passe(population, ressources, equipement, temps.jour_total)
    decouvertes.mois_passe(population, ressources, recettes, temps.jour_total, pression, besoins.mode == "auto")
    economie.mois_passe(population, ressources, construction, equipement, temps.jour_total)
    for c in voisins:
        c.mois_passe(temps.jour_total, temps.saison_des_pluies())
    diplomatie.mois_passe()
    _visites_ordinateur()
    marche.mois_passe(_clans(), _ids_voisins(), temps.jour_total, diplomatie)
    population.repartir(temps.jour_total)
    sauvegarder()

func _process(delta: float) -> void:
    temps.avancer(delta)

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
        sauvegarder()

func sauvegarder() -> void:
    var donnees := {
        "version": VERSION,
        "temps": temps.vers_dict(),
        "population": population.vers_dict(),
        "ressources": ressources.vers_dict(),
        "construction": construction.vers_dict(),
        "besoins": besoins.vers_dict(),
        "conseil": conseil.vers_dict(),
        "chef": chef.vers_dict(),
        "migration": migration.vers_dict(),
        "recettes": recettes.vers_dict(),
        "equipement": equipement.vers_dict(),
        "decouvertes": decouvertes.vers_dict(),
        "economie": economie.vers_dict(),
        "voisins": voisins.map(func(c): return c.vers_dict()),
        "diplomatie": diplomatie.vers_dict(),
        "marche": marche.vers_dict(),
        "caravanes": caravanes.vers_dict(),
        "agriculture": agriculture.vers_dict(),
        "pression": pression.vers_dict(),
        "territoire": territoire.vers_dict(),
        "clotures": clotures.vers_dict(),
        "routes": routes.vers_dict(),
        "expeditions": expeditions.vers_dict(),
        "gisements": gisements.vers_dict(),
        "ile_joueur": ile_joueur,
        "ile_confirmee": ile_confirmee,
        "graine_monde": graine_monde,
    }
    var f := FileAccess.open(DOSSIER + FICHIER + ".tmp", FileAccess.WRITE)
    if f == null:
        push_error("Sauvegarde impossible")
        return
    f.store_string(JSON.stringify(donnees))
    f.close()
    var d := DirAccess.open(DOSSIER)
    if d.file_exists(FICHIER):
        d.rename(FICHIER, FICHIER + ".bak")
    d.rename(FICHIER + ".tmp", FICHIER)

func _charger(nom: String) -> bool:
    var chemin := DOSSIER + nom
    if not FileAccess.file_exists(chemin):
        return false
    var donnees = JSON.parse_string(FileAccess.get_file_as_string(chemin))
    if typeof(donnees) != TYPE_DICTIONARY:
        return false
    _creer_modules()
    temps.depuis_dict(donnees.get("temps", {}))
    population.depuis_dict(donnees.get("population", {}))
    ressources.depuis_dict(donnees.get("ressources", {}))
    construction.depuis_dict(donnees.get("construction", {}))
    besoins.depuis_dict(donnees.get("besoins", {}))
    conseil.depuis_dict(donnees.get("conseil", {}), population, temps.jour_total)
    chef.depuis_dict(donnees.get("chef", {}))
    migration.depuis_dict(donnees.get("migration", {}), 2026)
    recettes.depuis_dict(donnees.get("recettes", {}))
    equipement.depuis_dict(donnees.get("equipement", {}))
    decouvertes.depuis_dict(donnees.get("decouvertes", {}))
    economie.depuis_dict(donnees.get("economie", {}), ressources)
    marche.depuis_dict(donnees.get("marche", {}))
    caravanes.depuis_dict(donnees.get("caravanes", {}))
    agriculture.depuis_dict(donnees.get("agriculture", {}))
    pression.depuis_dict(donnees.get("pression", {}))
    territoire.depuis_dict(donnees.get("territoire", {}))
    clotures.depuis_dict(donnees.get("clotures", {}))
    routes.depuis_dict(donnees.get("routes", {}))
    expeditions.depuis_dict(donnees.get("expeditions", {}))
    gisements.depuis_dict(donnees.get("gisements", {}))
    if not donnees.has("routes"):   # ancienne sauvegarde : les champs déjà là ont leur sentier
        routes.sentiers_existants(agriculture.champs.map(func(c): return "parcelle_" + str(c.get("parcelle", ""))).filter(func(x): return x != "parcelle_"))
    ile_joueur = str(donnees.get("ile_joueur", agriculture.ile_id))
    ile_confirmee = bool(donnees.get("ile_confirmee", true))
    graine_monde = int(donnees.get("graine_monde", 0))
    _installer_ile()
    if donnees.has("voisins"):
        voisins = []
        var ids := ["joueur"]
        for v in donnees["voisins"]:
            var c = CLAN.new()
            c.depuis_dict(v, temps.jour_total)
            voisins.append(c)
            ids.append(c.id)
        diplomatie.depuis_dict(donnees.get("diplomatie", {}), ids)
    else:
        _creer_voisins()
    temps.vitesse = 1
    return true
