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
const BUDGET = preload("res://scripts/core/budget.gd")
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
const FLOTTE = preload("res://scripts/core/flotte.gd")
const DEFIS = preload("res://scripts/core/defis.gd")
const RIVAL = preload("res://scripts/core/rival.gd")
const HEROS = preload("res://scripts/core/heros.gd")
const HISTOIRE = preload("res://scripts/core/histoire.gd")
const ELEVAGE = preload("res://scripts/core/elevage.gd")
const GUERRE = preload("res://scripts/core/guerre.gd")
const RAID = preload("res://scripts/core/raid.gd")
const GOUVERNEMENT = preload("res://scripts/core/gouvernement.gd")
const FINANCES = preload("res://scripts/core/finances.gd")
const INSTITUTIONS = preload("res://scripts/core/institutions.gd")
const RAPPORTS = preload("res://scripts/core/rapports.gd")
const MISSIONS = preload("res://scripts/core/missions.gd")
const SATISFACTION = preload("res://scripts/core/satisfaction.gd")
const TRAVAIL = preload("res://scripts/core/travail.gd")

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
var budget
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
var flotte
var defis
var rival
var heros
var histoire
var elevage
var guerre
var raids
var gouvernement
var finances
var institutions
var rapports
var missions
var satisfaction
var travail
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
    budget = BUDGET.new()
    ressources.budget = budget
    finances = FINANCES.new()
    finances.eco = economie
    ressources.finances = finances
    budget.finances = finances
    institutions = INSTITUTIONS.new()
    rapports = RAPPORTS.new()
    missions = MISSIONS.new()
    satisfaction = SATISFACTION.new()
    travail = TRAVAIL.new()
    ressources.travail = travail
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
    flotte = FLOTTE.new()
    flotte.depart()
    expeditions.flotte = flotte
    defis = DEFIS.new()
    rival = RIVAL.new()
    heros = HEROS.new()
    population.deces.connect(heros.sur_depart.bind(true))
    population.sortie.connect(heros.sur_depart.bind(false))
    elevage = ELEVAGE.new()
    guerre = GUERRE.new()
    raids = RAID.new()
    gouvernement = GOUVERNEMENT.new()
    raids.sur_renommee = func(d): defis.renommee = maxi(0, int(defis.renommee) + int(d))
    besoins.elevage = elevage
    besoins.agriculture = agriculture
    besoins.recettes = recettes
    histoire = HISTOIRE.new()
    histoire.observer(self)
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
    # Les surprises (décisions, expéditions) dépendent de la partie, pas toujours les mêmes.
    defis.rng.seed = graine_monde + 11
    expeditions.rng.seed = graine_monde + 12
    rival.rng.seed = graine_monde + 13
    heros.rng.seed = graine_monde + 14
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
    # Réputation du joueur, si l'autre clan le connaît : frais -1 ou -2 points.
    var autre = b if acheteur == "joueur" else a
    var remise := 0.0
    if autre != self and nous_connait(autre):
        remise = 0.02 if reputation() >= 75 else (0.01 if reputation() >= 50 else 0.0)
    return marche.devis(a, b, produit, q, temps.jour_total, paiement, diplomatie.etat(acheteur, vendeur), remise)
# Qui connaît qui (v0.3.32c) : le joueur, les îles découvertes ; l'ordinateur,
# les îles que ses délégations ont visitées. Pas de connaissance magique.
func _connaissances_marche() -> void:
    var moi: Array = [self]
    for v in voisins:
        if int(expeditions.connues.get(v.agriculture.ile_id, 0)) >= 1:
            moi.append(v)
    marche.connus = {get_instance_id(): moi}
    for v in voisins:
        var l: Array = [v]
        for w in voisins:
            if w != v and v.iles_connues.has(w.agriculture.ile_id):
                l.append(w)
        if v.iles_connues.has(ile_joueur):
            l.append(self)
        marche.connus[v.get_instance_id()] = l
# Vendre un surplus réel au clan connu qui en offre le plus (v0.3.32c).
# Les réserves vitales restent protégées ; rien n'est créé.
# Pâture : nos parcelles qui ne sont pas des champs (v0.3.36).
func paturage_ha() -> float:
    var champs := 0.0
    for ch in agriculture.champs:
        champs += float(ch["ha"])
    return maxf(0.0, territoire.surface_possedee() - champs)
# Achat d'animaux vivants à un clan connu (v0.3.38). Le vendeur garde toujours
# un mâle et une femelle adultes, et ne vend ni gestantes ni allaitantes.
# L'acheteur paie en grain (sans passer sous 30 jours de nourriture). Les bêtes
# voyagent sur un bateau du vendeur ; risque de perte en mer comme les caravanes.
const PRIX_BETE := {"pintade": 8.0, "chevre": 60.0, "zebu": 300.0}
const POIDS_BETE := {"pintade": 1.5, "chevre": 30.0, "zebu": 300.0}
var livraisons: Array = []       # {esp, sexes, arrivee, risque, vendeur}
func vendables(v, esp: String) -> Array:
    var j: int = temps.jour_total
    var el = v.elevage
    var l: Array = el.animaux.filter(func(a): return a["esp"] == esp and not (a["sexe"] == "f" and (int(a["gest_fin"]) >= 0 or j < int(a["lact_fin"]))))
    for sexe in ["m", "f"]:
        var ad: Array = l.filter(func(a): return a["sexe"] == sexe and el.adulte(a, j))
        var tous: Array = el.animaux.filter(func(a): return a["esp"] == esp and a["sexe"] == sexe and el.adulte(a, j))
        if tous.size() <= 1 and not ad.is_empty():
            l.erase(ad[0])
        elif not ad.is_empty() and tous.size() - ad.size() < 1:
            l.erase(ad[0])
    return l.filter(func(a): return el.adulte(a, j))
func vendeur_animaux(esp: String) -> String:
    for v in voisins:
        if v.vivant() and int(expeditions.connues.get(v.agriculture.ile_id, 0)) >= 1 and diplomatie.etat("joueur", v.id) != "hostilité" and vendables(v, esp).size() > 0:
            return v.id
    return ""
func acheter_animaux(esp: String) -> String:
    var vid := vendeur_animaux(esp)
    if vid == "":
        return "Aucun clan connu ne peut vendre de %s sans affaiblir son troupeau." % esp
    var v = voisin(vid)
    var l: Array = vendables(v, esp)
    var lot: Array = []
    for sexe in ["m", "f"]:
        for a in l:
            if a["sexe"] == sexe:
                lot.append(a)
                break
    var prix: float = PRIX_BETE[esp] * lot.size()
    var j: int = temps.jour_total
    var conso: float = ressources._conso_jour(population, j, "nourriture")
    if ressources.total_aliments() - prix < conso * 30.0:
        return "Payer %d kg de grain ferait passer nos réserves sous 30 jours." % int(prix)
    var dist: int = caravanes.duree(caravanes.territoire(self), caravanes.territoire(v))
    var bateau: Dictionary = v.flotte.reserver(j, j + 2 * dist, 2, POIDS_BETE[esp] * lot.size(), "commerce")
    if bateau.is_empty():
        return "Le %s n'a pas de bateau libre pour transporter ces bêtes." % v.nom
    var paye: float = elevage._retirer_grain(ressources, prix)
    v.ressources.ajouter("mil", paye, "vente_animaux")
    var sexes: Array = []
    for a in lot:
        sexes.append(a["sexe"])
        v.elevage.animaux.erase(a)
    livraisons.append({"esp": esp, "sexes": sexes, "arrivee": j + dist, "risque": caravanes.RISQUE_BASE + caravanes.RISQUE_JOUR * dist, "vendeur": v.nom})
    diplomatie.noter("joueur", vid, "echange", 2.0, "achat d'animaux", j)
    return ""
func _livrer_animaux() -> void:
    var j: int = temps.jour_total
    for l in livraisons.duplicate():
        if j < int(l["arrivee"]):
            continue
        livraisons.erase(l)
        var arrives := 0
        for s in l["sexes"]:
            if elevage.rng.randf() >= float(l["risque"]):
                elevage.ajouter(l["esp"], s, j)
                arrives += 1
        elevage.evenement.emit("Bétail du %s arrivé : %d sur %d bête(s)." % [l["vendeur"], arrives, l["sexes"].size()])
func abattre(esp: String) -> String:
    return elevage.abattre(esp, ressources, temps.jour_total)
func vendre_surplus(produit: String) -> String:
    var jour: int = temps.jour_total
    var q: float = marche.disponible(self, produit, jour)
    if q <= 0.01:
        return "Pas de surplus de %s : nos réserves vitales passent d'abord." % produit
    var meilleur := ""
    var total := 0.0
    var raison := "Aucun clan connu n'en veut pour l'instant."
    for v in voisins:
        if not v.vivant() or int(expeditions.connues.get(v.agriculture.ile_id, 0)) < 1:
            continue
        var d := devis_commerce(v.id, "joueur", produit, q)
        if d.get("possible", false) and float(d["total"]) > total:
            total = float(d["total"])
            meilleur = v.id
        elif not d.get("possible", false):
            raison = d.get("raison", raison)
    if meilleur == "":
        return raison
    return commercer(meilleur, "joueur", produit, q)

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

# Décisions du joueur face aux situations imprévues.
func choisir_decision(index: int, option: int) -> String:
    return defis.choisir(self, index, option)

# Port et flotte du joueur.
func construire_bateau(type: String) -> String:
    return flotte.commander(type, ressources, construction, routes)

func prospecter() -> String:
    return gisements.prospecter(population, temps.jour_total)

func ouvrir_site(type: String) -> String:
    return gisements.ouvrir(type, ressources, routes, population)

func lancer_expedition(type: String, cible := "") -> String:
    return expeditions.lancer(type, cible, ile_joueur, population, ressources, temps.jour_total)

# Les clans de l'ordinateur avancent d'époque avec les MÊMES conditions que le
# joueur. Toute l'île les voit progresser : c'est la rivalité de l'archipel.
func _epoques_ordinateur() -> void:
    var ids: Array = ["joueur"] + voisins.map(func(v): return v.id)
    for c in voisins:
        if not c.vivant() or c.epoque >= DEFIS.EPOQUES.size() - 2:
            continue
        var ok := true
        for cond in DEFIS.conditions_clan(c.epoque, c, c.id, ids, diplomatie, 1 + c.iles_connues.size()):
            if not cond[1]:
                ok = false
                break
        if ok:
            c.epoque += 1
            var t := "Le %s entre dans l'époque : %s !" % [c.nom, DEFIS.EPOQUES[c.epoque]]
            if c.epoque > defis.epoque:
                t += " Il prend de l'avance sur nous."
            defis.evenement.emit(t)

# Classement de l'archipel (connu du joueur : son clan et les îles visitées).
# Réputation (v0.3.32d) : calculée à chaque fois, jamais sauvegardée. 0 à 100.
# Époque atteinte x 8 (max 40) ; héros vivant présent 5/10/15 ; monuments
# achevés 5 (max 15) ; ancêtres 2 (max 10) ; faits uniques : découvertes
# connues et îles connues, 1 chacun (max 20).
const NIVEAUX_REPUTATION := ["clan obscur", "clan connu", "clan respecté", "clan illustre"]
func reputation(id := "joueur") -> int:
    var r := 0
    if id == "joueur":
        r += mini(40, 8 * int(defis.epoque))
        var hv = heros.heros(population)
        if hv != null:
            r += [5, 10, 15][clampi(int(hv["heros"]["niveau"]), 0, 2)]
        r += mini(15, 5 * construction.nombre("monument"))
        r += mini(10, 2 * heros.ancetres.size())
        var iles := 0
        for k in expeditions.connues:
            if k != ile_joueur and int(expeditions.connues[k]) >= 1:
                iles += 1
        r += mini(20, decouvertes.connues.size() + iles)
    else:
        var v = voisin(id)
        if v == null:
            return 0
        r += mini(40, 8 * int(v.epoque))
        r += mini(15, 5 * v.construction.nombre("monument"))
        r += mini(20, v.decouvertes.connues.size() + v.iles_connues.size())
    return mini(100, r)
func niveau_reputation(r: int) -> String:
    return NIVEAUX_REPUTATION[clampi(r / 25, 0, 3)]
# L'autre clan nous connaît-il ? (il a visité notre île, ou nous l'avons visité)
func nous_connait(v) -> bool:
    return v.iles_connues.has(ile_joueur) or expeditions.visites.has(v.id)
func classement() -> Array:
    var l: Array = [{"nom": "Notre clan", "epoque": defis.epoque, "habitants": population.habitants.size(), "reputation": reputation()}]
    for c in voisins:
        if c.vivant() and int(expeditions.connues.get(c.agriculture.ile_id, 0)) >= 2:
            l.append({"nom": c.nom, "epoque": c.epoque, "habitants": c.population.habitants.size(), "reputation": reputation(c.id)})
    l.sort_custom(func(a, b): return a["epoque"] > b["epoque"] or (a["epoque"] == b["epoque"] and a["habitants"] > b["habitants"]))
    return l

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
        c.iles_connues[cible] = true
        var niveau: float = expeditions.OBSERVATION.get(diplomatie.etat(c.id, autre.id), 1.0)
        for t in autre.decouvertes.connues:
            c.decouvertes.observer(t, niveau)

# Routes du joueur : destination = "eau", "foret", "carriere", "mine", "port" ou "parcelle_x,z".
func construire_route(dest: String, niveau: String) -> String:
    return routes.construire(dest, niveau, ressources, territoire)

func amender_champ(id_champ: int) -> String:
    return agriculture.amender(id_champ, ressources)

# Épandre le fumier : du vrai fumier et du vrai travail (un adulte occupé).
func amender_fumier(id_champ: int) -> String:
    var c: Dictionary = agriculture.champ(id_champ)
    if c.is_empty():
        return "Champ inconnu."
    var jours := maxi(1, int(ceil(float(c["ha"]) * agriculture.JOURS_FUMIER_HA)))
    var qui = null
    for h in population.habitants:
        if population.age(h, temps.jour_total) >= 14 and not h["metier"] in ["chef", "ancien"] and not h.has("expedition") and not defis.occupes.has(int(h["id"])):
            qui = h
            break
    if qui == null:
        return "Aucun adulte disponible pour épandre le fumier."
    var r: String = agriculture.amender_fumier(id_champ, ressources)
    if r == "":
        defis.occupes[int(qui["id"])] = temps.jour_total + jours
    return r
func semer(id_champ: int, culture: String) -> String:
    return agriculture.semer(id_champ, culture, ressources, temps.jour_total, decouvertes.connait)

# Raids du joueur (v0.3.48) : un clan visité, un petit groupe, un bateau, des vivres à prendre.
func evaluer_raid(cible: String) -> Dictionary:
    var v = voisin(cible)
    if v == null:
        return {"possible": false, "raison": "Clan inconnu."}
    return raids.evaluer(self, "joueur", v, cible, temps.jour_total, caravanes, int(expeditions.connues.get(v.agriculture.ile_id, 0)) >= 2, diplomatie)

# Un clan de l'ordinateur sait-il où se trouve sa cible ?
func _raid_connait(a: String, b: String) -> bool:
    var va = voisin(a)
    if va == null:
        return false
    if b == "joueur":
        return nous_connait(va)
    var vb = voisin(b)
    return vb != null and va.iles_connues.has(vb.agriculture.ile_id)

func repondre_raid(choix: String) -> String:
    return raids.repondre(Callable(self, "_clan"), temps.jour_total, diplomatie, choix)

func lancer_raid(cible: String) -> String:
    var v = voisin(cible)
    if v == null:
        return "Clan inconnu."
    return raids.lancer(self, "joueur", v, cible, temps.jour_total, caravanes, int(expeditions.connues.get(v.agriculture.ile_id, 0)) >= 2, diplomatie)

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

# ---------- Relations : cadeaux et aide entre alliés (v0.3.69) ----------
const RESERVE_CADEAU_JOURS := 30.0     # le joueur garde 30 jours de vivres après un cadeau
const RESERVE_ALLIE_JOURS := 60.0      # un allié ne donne que ce qui dépasse 60 jours de ses vivres
const AIDE_JOURS := 5.0                # une aide couvre 5 jours de besoin du bénéficiaire
const AIDE_MIN_KG := 10.0

func voisin_connu(v) -> bool:
    return v.vivant() and int(expeditions.connues.get(v.agriculture.ile_id, 0)) >= 1

# Quantité de référence d'un cadeau complet : 5 jours de vivres du clan qui reçoit (20 kg au moins).
func reference_cadeau(vid: String) -> float:
    var v = _clan(vid)
    if v == null:
        return 20.0
    return maxf(20.0, AIDE_JOURS * float(v.ressources._conso_jour(v.population, temps.jour_total, "nourriture")))

# Le joueur offre des vivres : retirés de son stock, ajoutés chez le voisin, relation améliorée
# (+10 au plus, selon la quantité). La mémoire des événements n'est jamais effacée.
func offrir_vivres(vid: String, kg: float) -> String:
    var v = _clan(vid)
    var j: int = temps.jour_total
    if v == null or not voisin_connu(v):
        return "Ce clan n'est pas connu."
    var repos: int = diplomatie.repos_restant("cadeau", "joueur", vid, j, diplomatie.CADEAU_REPOS)
    if repos > 0:
        return "Un cadeau a déjà été fait à ce clan : encore %d jour(s) à attendre." % repos
    var libre: float = float(v.ressources.capacite("nourriture")) - float(v.ressources.total_aliments())
    kg = minf(kg, libre)
    if kg < 1.0:
        return "Leur grenier est plein : ils ne peuvent rien recevoir."
    var reserve: float = RESERVE_CADEAU_JOURS * float(ressources._conso_jour(population, j, "nourriture"))
    if ressources.total_aliments() - kg < reserve:
        return "Il vous resterait moins de %d jours de vivres." % int(RESERVE_CADEAU_JOURS)
    if not ressources.retirer_vivres(kg, "cadeau"):
        return "Pas assez de vivres."
    v.ressources.ajouter_vivres(kg, "cadeau")
    var gain: float = diplomatie.gain_cadeau(kg, reference_cadeau(vid))
    diplomatie.noter("joueur", vid, "cadeau", gain, "cadeau de %d kg de vivres" % int(round(kg)), j)
    diplomatie.noter_repos("cadeau", "joueur", vid, j)
    return ""

# Chaque mois : un allié aide le joueur seulement si le joueur connaît une famine réelle, si l'allié
# garde 60 jours de vivres pour lui, avec un plafond et un repos de 60 jours par clan. Transfert réel.
# Un allié qui ne peut pas aider n'est pas un traître : rien ne se rompt.
func _aides_allies() -> void:
    if not ressources.faim:
        return
    var j: int = temps.jour_total
    for v in voisins:
        if not voisin_connu(v) or diplomatie.etat("joueur", v.id) != "alliance":
            continue
        if diplomatie.repos_restant("aide", "joueur", v.id, j, diplomatie.AIDE_REPOS) > 0:
            continue
        var surplus: float = float(v.ressources.total_aliments()) - RESERVE_ALLIE_JOURS * float(v.ressources._conso_jour(v.population, j, "nourriture"))
        var besoin: float = AIDE_JOURS * float(ressources._conso_jour(population, j, "nourriture"))
        var libre: float = float(ressources.capacite("nourriture")) - float(ressources.total_aliments())
        var kg: float = minf(minf(besoin, surplus), libre)
        if kg < AIDE_MIN_KG:
            continue
        if not v.ressources.retirer_vivres(kg, "aide"):
            continue
        ressources.ajouter_vivres(kg, "aide")
        diplomatie.noter("joueur", v.id, "aide", 2.0, "aide alimentaire de %d kg en pleine famine" % int(round(kg)), j)
        diplomatie.noter_repos("aide", "joueur", v.id, j)
        diplomatie.evenement.emit("Aide alimentaire : %s vous envoie %d kg de vivres." % [v.nom, int(round(kg))])

func ignorer_alerte(cle: String) -> String:
    return chef.ignorer(cle, temps.jour_total)

func _jour_passe() -> void:
    finances.jour_passe(self, temps.jour_total)
    var chantier_actif: bool = not construction.chantiers.is_empty()
    # Règle 4 : dix jours avant la fin du mois, prévision de l'entretien (une estimation, pas une garantie).
    if temps.jour_total % 30 == 20:
        var prev: Dictionary = construction.prevision_entretien(ressources, 10)
        if besoins.reagir_entretien(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), chantier_actif, prev, 10):
            population.repartir(temps.jour_total)
    guerre.bonus_gouv = institutions.bonus("defense", self)
    ressources.travail_du_jour = {}    # qui a réellement travaillé aujourd'hui (rempli par tous les producteurs)
    if temps.jour_total % 7 == 0:
        besoins.controle_hebdo(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), chantier_actif)
    recettes.jour_passe(population, ressources, temps.jour_total)
    missions.jour_passe(self, temps.jour_total)
    decouvertes.jour_passe(population, recettes, temps.jour_total, pression)
    # Réputation : délégations mieux reçues (+0 à 20 %), première rencontre (+0 à 5).
    expeditions.bonus_reputation = float(reputation()) / 100.0
    expeditions.jour_passe(population, temps.jour_total, ile_joueur, _clans_par_ile(), "joueur", self, diplomatie)
    gisements.jour_passe(population, ressources, routes, temps.jour_total, expeditions.rng)
    defis.jour_passe(self)
    equipement.jour_passe(population, chantier_actif)
    guerre.jour_passe(population, temps.jour_total)
    raids.jour_passe(Callable(self, "_clan"), temps.jour_total, diplomatie)
    gouvernement.verifier(self)
    ressources.sel_attendu = caravanes.en_attente("joueur", "sel")    # D-2 : signalé, jamais compté dans le stock
    ressources.jour_passe(population, temps.jour_total, temps.saison_des_pluies(), chantier_actif)
    construction.jour_passe(travail_batisseurs())
    if construction.chantiers.is_empty():
        if clotures.en_travaux():
            clotures.jour_passe(travail_batisseurs())
        elif routes.en_travaux():
            routes.jour_passe(travail_batisseurs())
        elif routes.a_reparer() != "":
            routes.reparer(travail_batisseurs(), ressources)
        else:
            flotte.jour_passe(travail_batisseurs())
    agriculture.jour_passe(population, ressources, construction, temps.jour_total, temps.saison_des_pluies())
    elevage.elevage_connu = decouvertes.connait("elevage")
    elevage.capture(population, temps.jour_total)
    _livrer_animaux()
    besoins.paturage_ha = paturage_ha()
    elevage.jour_passe(ressources, population, temps.jour_total, temps.saison_des_pluies(), besoins.paturage_ha)
    travail.fin_de_jour(population, ressources.travail_du_jour, temps.jour_total)
    population.jour_passe(ressources.faim, ressources.soif, ressources.jours_sans_sel, temps.jour_total)
    var besoin_soins: float = float(population.a_soigner().size())
    institutions.noter_besoin("sante", besoin_soins)
    var soins: float = float(population.soigner(ressources, temps.jour_total, int(construction.effet_total("soin_places")), minf(1.0, construction.effet_total("soin_bonus")), institutions.bonus("sante", self)))
    institutions.noter("sante", soins)
    satisfaction.jour(self, besoin_soins, soins)
    pression.jour_passe(ressources)
    for c in voisins:
        c.ressources.sel_attendu = caravanes.en_attente(c.id, "sel")
        c.jour_passe(temps.jour_total, temps.saison_des_pluies())
    caravanes.jour_passe(_clan, temps.jour_total)
    if temps.jour_total % chef.REVUE_JOURS == 0:
        besoins.actualiser(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), chantier_actif)
        chef.revue(conseil, population, besoins, temps.jour_total)
    if population.habitants.is_empty(): temps.vitesse = 0

func _mois_passe() -> void:
    construction.mois_passe(ressources)
    # Règle 6 (clan du joueur) : le Premier ministre propose la réparation, il ne la lance pas.
    var ruine: int = construction.premiere_ruine()
    if ruine >= 0:
        var rep: Dictionary = construction.cout_reparation(ruine)
        besoins.evenement.emit("Le Premier ministre propose de réparer : %s (%s, %d jours de travail). Voir Construire." % [construction.definitions[construction.batiments[ruine]["type"]]["nom"], construction.texte_cout(rep["cout"]), int(rep["travail"])])
    clotures.mois_passe(ressources, temps.mois())
    routes.mois_passe(ressources, temps.mois())
    flotte.mois_passe(ressources, temps.mois())
    var logement: float = construction.effet_total("logement")
    var couv: float = satisfaction.valeur("nourriture")
    population.mois_passe(temps.jour_total, true, int(logement), couv / 100.0 if couv >= 0.0 else 1.0)
    conseil.mois_passe(population, temps.jour_total)
    besoins.mois_passe(population, ressources, construction, temps.jour_total, temps.saison_des_pluies(), not construction.chantiers.is_empty())
    if besoins.mode == "auto":
        agriculture.gerer_auto(population, ressources, temps.jour_total, decouvertes.connait, besoins.conversion_permise)
        if decouvertes.connait("agriculture"):
            territoire.gerer_auto(agriculture, ressources, temps.jour_total, 4.0)
        routes.gerer_auto(ressources, territoire, agriculture)
    if agriculture.prochaine_recolte() > temps.jour_total:
        besoins.verrou["cultivateur"] = agriculture.prochaine_recolte()
    migration.mois_passe(population, ressources, construction, temps.jour_total)
    pression.mois_passe(population, ressources, equipement, temps.jour_total)
    decouvertes.mois_passe(population, ressources, recettes, temps.jour_total, pression, besoins.mode == "auto")
    budget.mois_passe(ressources, population, temps.jour_total, economie)
    economie.mois_passe(population, ressources, construction, equipement, temps.jour_total)
    for c in voisins:
        c.mois_passe(temps.jour_total, temps.saison_des_pluies())
    preload("res://scripts/core/echanges_animaux.gd").mois(voisins, temps.jour_total)
    diplomatie.mois_passe(temps.jour_total)
    raids.mois_passe()
    institutions.mois_passe(self, temps.jour_total)
    satisfaction.mois_passe(self, temps.jour_total)
    ressources.facteur_stabilite = satisfaction.facteur_productivite()
    _aides_allies()
    rapports.mois_passe(self, temps.jour_total)
    travail.nouveau_mois()
    raids.decider(_clans(), temps.jour_total, caravanes, diplomatie, Callable(self, "_raid_connait"))
    _visites_ordinateur()
    defis.mois_passe(self)
    _epoques_ordinateur()
    rival.mois_passe(self)
    heros.mois_passe(self)
    elevage.mois_passe(ressources, population, temps.jour_total)
    histoire.mois_passe(self)
    _connaissances_marche()
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
        "budget": budget.vers_dict(),
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
        "flotte": flotte.vers_dict(),
        "defis": defis.vers_dict(),
        "rival": rival.vers_dict(),
        "heros": heros.vers_dict(),
        "histoire": histoire.vers_dict(),
        "elevage": elevage.vers_dict(),
        "guerre": guerre.vers_dict(),
        "raids": raids.vers_dict(),
        "gouvernement": gouvernement.vers_dict(),
        "finances": finances.vers_dict(),
        "institutions": institutions.vers_dict(),
        "rapports": rapports.vers_dict(),
        "missions": missions.vers_dict(),
        "satisfaction": satisfaction.vers_dict(),
        "travail": travail.vers_dict(),
        "livraisons": livraisons,
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
    budget.depuis_dict(donnees.get("budget", {}))
    marche.depuis_dict(donnees.get("marche", {}))
    caravanes.depuis_dict(donnees.get("caravanes", {}))
    agriculture.depuis_dict(donnees.get("agriculture", {}))
    pression.depuis_dict(donnees.get("pression", {}))
    territoire.depuis_dict(donnees.get("territoire", {}))
    clotures.depuis_dict(donnees.get("clotures", {}))
    routes.depuis_dict(donnees.get("routes", {}))
    expeditions.depuis_dict(donnees.get("expeditions", {}))
    gisements.depuis_dict(donnees.get("gisements", {}))
    flotte.depuis_dict(donnees.get("flotte", {}))
    defis.depuis_dict(donnees.get("defis", {}))
    rival.depuis_dict(donnees.get("rival", {}))
    heros.depuis_dict(donnees.get("heros", {}))
    heros.appliquer(self)
    histoire.depuis_dict(donnees.get("histoire", {}))
    elevage.depuis_dict(donnees.get("elevage", {}))
    guerre.depuis_dict(donnees.get("guerre", {}))
    raids.depuis_dict(donnees.get("raids", {}))
    gouvernement.depuis_dict(donnees.get("gouvernement", {}))
    finances.depuis_dict(donnees.get("finances", {}))
    institutions.depuis_dict(donnees.get("institutions", {}))
    guerre.bonus_gouv = institutions.bonus("defense", self)
    rapports.depuis_dict(donnees.get("rapports", {}))
    missions.depuis_dict(donnees.get("missions", {}))
    satisfaction.depuis_dict(donnees.get("satisfaction", {}))
    travail.depuis_dict(donnees.get("travail", {}))
    ressources.facteur_stabilite = satisfaction.facteur_productivite()
    livraisons = donnees.get("livraisons", [])
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
