extends RefCounted

# Raids (v0.3.48, étape 1) : un clan envoie un petit groupe de combattants, par bateau,
# prendre des VIVRES chez un autre clan. Ce n'est ni une conquête ni une guerre totale :
#  - un raid doit être POSSIBLE : cible visitée, pas une alliance, combattants disponibles,
#    bateau libre, vivres pour l'aller-retour, réserves du clan préservées, butin qui vaut le voyage,
#    force bien supérieure à la défense ESTIMÉE (on ne connaît jamais la défense exacte) ;
#  - les vivres du voyage sont vraiment retirés du stock (motif « raid ») ;
#  - à l'arrivée, la force réelle des survivants affronte la défense réelle du village ;
#  - butin = une part des vivres de la cible, limitée par ce que le groupe peut porter ;
#    il est retiré à la cible à l'arrivée et ajouté au retour (perdu si le clan disparaît) ;
#  - morts et blessés des deux côtés ; relation détériorée entre les deux clans ;
#  - le bateau et les combattants restent absents tout le voyage (mobilisation de guerre.gd).
# Même moteur pour le joueur et les clans de l'ordinateur (le déclenchement par l'IA viendra plus tard).

signal evenement(texte)

const RATIO_MIN := 1.3         # force / défense estimée minimale
const INCERTITUDE := 0.2       # la défense estimée se trompe de 20 % au plus
const EQUIPE_MIN := 2
const BUTIN_PART := 0.15       # part des vivres de la cible qu'un raid réussi peut prendre
const CHARGE_KG := 20.0        # ce que porte un guerrier
const VIVRES_JOUR := 1.0       # kg de nourriture par guerrier et par jour de voyage
const BUTIN_MIN_FOIS := 2.0    # le butin attendu doit valoir au moins 2 fois les vivres du voyage
const RESERVE_JOURS := 30.0    # le clan garde 30 jours de vivres après le départ
const HISTORIQUE_MAX := 30
const DELAI_POURPARLERS := 2   # jours pour répondre quand le joueur est concerné
const PART_RANCON := 0.5       # une rançon offerte vaut la moitié du butin attendu
const ACCEPTE_MIN := 0.4       # l'attaquant accepte si l'offre vaut au moins 40 % du butin attendu

var en_cours: Array = []
var historique: Array = []
var rng := RandomNumberGenerator.new()

func _init() -> void:
    rng.seed = 4242

static func _nom(c, cle: String) -> String:
    var n = c.get("nom") if c != null else null
    return "notre clan" if cle == "joueur" or n == null or str(n) == "" else str(n)

# Imprécision stable (même jour du mois = même estimation) : -1 à +1.
static func _bruit(cle: String, jour: int) -> float:
    return float(absi(hash("%s|%d" % [cle, jour / 30])) % 2001) / 1000.0 - 1.0

# Peut-on lancer un raid de att vers dst ? Renvoie un rapport complet.
func evaluer(att, att_id: String, dst, dst_id: String, jour: int, caravanes, connu := true, diplo = null) -> Dictionary:
    var r := {"possible": false, "raison": "", "n": 0, "force": 0.0, "defense_estimee": 0.0, "ratio": 0.0, "jours": 0, "vivres": 0.0, "butin": 0.0, "kg": 0.0}
    if att == null or dst == null or att_id == dst_id:
        r["raison"] = "Cible invalide."
        return r
    if dst.has_method("vivant") and not dst.vivant():
        r["raison"] = "Ce clan n'existe plus."
        return r
    if not connu:
        r["raison"] = "Cible inconnue : il faut d'abord visiter ce clan."
        return r
    if diplo != null and diplo.etat(att_id, dst_id) == "alliance":
        r["raison"] = "On n'attaque pas un allié : rompez d'abord l'alliance."
        return r
    for x in en_cours:
        if x["att"] == att_id and x["etat"] != "fini":
            r["raison"] = "Un raid est déjà en cours."
            return r
    var pop = att.population
    var res = att.ressources
    var disponibles: Array = att.guerre.combattants(pop, res, jour)
    var n: int = att.guerre.plafond(pop, res, jour)
    if n < EQUIPE_MIN:
        r["raison"] = "Pas assez de combattants disponibles (il en faut %d au moins sans affaiblir le clan)." % EQUIPE_MIN
        return r
    # Le plus grand groupe que porte un bateau libre.
    var vitesse := 0.0
    while n >= EQUIPE_MIN:
        vitesse = att.flotte.vitesse_libre(jour, n, float(n) * CHARGE_KG * 2.0)
        if vitesse > 0.0:
            break
        n -= 1
    if vitesse <= 0.0:
        r["raison"] = att.flotte.raison_aucun(jour, EQUIPE_MIN, float(EQUIPE_MIN) * CHARGE_KG * 2.0)
        return r
    var a: Dictionary = caravanes.territoire(att)
    var b: Dictionary = caravanes.territoire(dst)
    var km: float = Vector2(float(a["x"]) - float(b["x"]), float(a["z"]) - float(b["z"])).length()
    var jours: int = maxi(1, int(ceil(km / vitesse)))
    var vivres: float = float(n) * VIVRES_JOUR * float(2 * jours + 1)
    if res.total_aliments() - vivres < float(res._conso_jour(pop, jour, "nourriture")) * RESERVE_JOURS:
        r["raison"] = "Les vivres du voyage (%d kg) feraient passer nos réserves sous %d jours." % [int(vivres), int(RESERVE_JOURS)]
        return r
    var groupe: Array = disponibles.slice(0, n)
    var force: float = att.guerre.force_groupe(groupe, att.equipement, res)
    var defense: float = float(dst.guerre.defense(dst.population, dst.equipement, dst.clotures, dst.ressources, jour))
    var estimee: float = maxf(0.1, defense * (1.0 + INCERTITUDE * _bruit(dst_id, jour)))
    var butin: float = minf(float(dst.ressources.total_aliments()) * BUTIN_PART, float(n) * CHARGE_KG)
    r["n"] = n
    r["force"] = force
    r["defense_estimee"] = estimee
    r["ratio"] = force / estimee
    r["jours"] = jours
    r["vivres"] = vivres
    r["butin"] = butin
    r["kg"] = float(n) * CHARGE_KG * 2.0
    if butin < vivres * BUTIN_MIN_FOIS:
        r["raison"] = "Le butin attendu (%d kg) ne vaut pas le voyage (%d kg de vivres)." % [int(butin), int(vivres)]
        return r
    if r["ratio"] < RATIO_MIN:
        r["raison"] = "Trop risqué : force %.1f contre une défense estimée à %.1f (il faut %.1f fois plus)." % [force, estimee, RATIO_MIN]
        return r
    r["possible"] = true
    return r

# Lance le raid : vivres retirés, bateau réservé, combattants mobilisés. "" si le raid part.
func lancer(att, att_id: String, dst, dst_id: String, jour: int, caravanes, connu := true, diplo = null) -> String:
    var e: Dictionary = evaluer(att, att_id, dst, dst_id, jour, caravanes, connu, diplo)
    if not bool(e["possible"]):
        return str(e["raison"])
    var jours: int = int(e["jours"])
    var n: int = int(e["n"])
    if not att.ressources.retirer_vivres(float(e["vivres"]), "raid"):
        return "Pas assez de vivres pour le voyage."
    var bateau: Dictionary = att.flotte.reserver(jour, jour + 2 * jours, n, float(e["kg"]), "raid")
    if bateau.is_empty():
        att.ressources.ajouter_vivres(float(e["vivres"]), "raid")
        return "Aucun bateau libre."
    var ids: Array = att.guerre.mobiliser(att.population, att.ressources, jour, n, 2 * jours)
    if ids.is_empty():
        att.ressources.ajouter_vivres(float(e["vivres"]), "raid")
        bateau["occupe_jusqu"] = jour - 1
        return "Aucun combattant disponible."
    en_cours.append({"att": att_id, "dst": dst_id, "ids": ids, "depart": jour, "arrivee": jour + jours, "retour": jour + 2 * jours, "force": float(e["force"]) * float(ids.size()) / float(maxi(1, n)), "butin": 0.0, "etat": "en_route", "issue": "", "morts_att": 0, "morts_def": 0, "blesses_att": 0, "blesses_def": 0, "kg": float(e["kg"]), "offre": 0.0, "limite": 0, "alerte": false})
    _dire(att_id, dst_id, "Raid : %d guerriers de %s partent vers %s (%d jours de mer)." % [ids.size(), _nom(att, att_id), _nom(dst, dst_id), jours])
    return ""

# Chaque jour : arrivée (combat) puis retour. `clan_de` : Callable(cle) -> clan.
func jour_passe(clan_de: Callable, jour: int, diplo = null) -> void:
    for x in en_cours.duplicate():
        if x["etat"] == "en_route" and x["dst"] == "joueur" and not bool(x["alerte"]) and jour >= int(x["arrivee"]) - 1:
            x["alerte"] = true
            _dire(x["att"], x["dst"], "Raid : des pirogues de guerre de %s approchent de notre île, arrivée dans %d jour(s)." % [_nom(clan_de.call(x["att"]), x["att"]), maxi(0, int(x["arrivee"]) - jour)])
        if x["etat"] == "en_route" and jour >= int(x["arrivee"]):
            _arrivee(x, clan_de.call(x["att"]), clan_de.call(x["dst"]), jour, diplo)
        if x["etat"] == "pourparlers" and jour >= int(x["limite"]):
            _par_defaut(x, clan_de.call(x["att"]), clan_de.call(x["dst"]), jour, diplo)
        if x["etat"] == "retour" and jour >= int(x["retour"]):
            _rentrer(x, clan_de.call(x["att"]), jour)
        if x["etat"] == "fini":
            en_cours.erase(x)
            historique.append(x)
            while historique.size() > HISTORIQUE_MAX:
                historique.pop_front()

# Butin qu'un raid réussi prendrait aujourd'hui.
func _attendu(dst, vivants: int) -> float:
    return minf(float(dst.ressources.total_aliments()) * BUTIN_PART, float(vivants) * CHARGE_KG)

# Arrivée : avant le combat, des pourparlers sont possibles.
#  - cible = joueur : il choisit (résister ou offrir une rançon) ;
#  - cible = clan de l'ordinateur : il offre une rançon s'il se sait plus faible (force >= 1,5 fois sa défense) ;
#  - attaquant = joueur : il accepte l'offre ou attaque quand même.
func _arrivee(x: Dictionary, att, dst, jour: int, diplo) -> void:
    if att == null or dst == null or (att.has_method("vivant") and not att.vivant()) or (dst.has_method("vivant") and not dst.vivant()):
        _resoudre(x, att, dst, jour, diplo)
        return
    var groupe: Array = _presents(att.population, x["ids"])
    if x["dst"] == "joueur":
        x["etat"] = "pourparlers"
        x["limite"] = jour + DELAI_POURPARLERS
        _dire(x["att"], x["dst"], "Raid : les guerriers de %s ont débarqué (%d). Résister ou offrir une rançon ? Réponse sous %d jours, sinon nous résistons." % [_nom(att, x["att"]), groupe.size(), DELAI_POURPARLERS])
        return
    var A: float = float(x["force"]) * float(groupe.size()) / float(maxi(1, x["ids"].size()))
    var D: float = maxf(0.1, float(dst.guerre.defense(dst.population, dst.equipement, dst.clotures, dst.ressources, jour)))
    var offre: float = 0.0
    if A / D >= 1.5:
        offre = minf(_attendu(dst, groupe.size()) * PART_RANCON, float(dst.ressources.total_aliments()))
    if offre < 1.0:
        _resoudre(x, att, dst, jour, diplo)
        return
    x["offre"] = offre
    if x["att"] == "joueur":
        x["etat"] = "pourparlers"
        x["limite"] = jour + DELAI_POURPARLERS
        _dire(x["att"], x["dst"], "Raid : %s nous offre %d kg de vivres pour éviter le combat. Accepter ou attaquer ? Réponse sous %d jours, sinon nous acceptons." % [_nom(dst, x["dst"]), int(offre), DELAI_POURPARLERS])
        return
    _traiter_offre(x, att, dst, jour, diplo, true)

# Sans réponse du joueur : le défenseur résiste, l'attaquant accepte l'offre.
func _par_defaut(x: Dictionary, att, dst, jour: int, diplo) -> void:
    if x["dst"] == "joueur":
        _resoudre(x, att, dst, jour, diplo)
    else:
        _traiter_offre(x, att, dst, jour, diplo, true)

# L'attaquant accepte (ou refuse) l'offre. L'offre doit valoir assez par rapport au butin attendu.
func _traiter_offre(x: Dictionary, att, dst, jour: int, diplo, accepte: bool) -> void:
    var groupe: Array = _presents(att.population, x["ids"])
    var offre: float = float(x["offre"])
    if not accepte or groupe.is_empty() or offre < ACCEPTE_MIN * _attendu(dst, groupe.size()) or not dst.ressources.retirer_vivres(offre, "rançon"):
        x["offre"] = 0.0
        _resoudre(x, att, dst, jour, diplo)
        return
    x["etat"] = "retour"
    x["butin"] = offre
    x["issue"] = "negocie"
    if diplo != null:
        diplo.noter(x["att"], x["dst"], "raid", -10.0, "rançon payée à %s" % _nom(att, x["att"]), jour)
    _dire(x["att"], x["dst"], "Raid : accord entre %s et %s, rançon de %d kg de vivres, sans combat." % [_nom(att, x["att"]), _nom(dst, x["dst"]), int(offre)])

# Réponse du joueur au raid en attente. Défenseur : "resister" ou "offrir". Attaquant : "accepter" ou "attaquer".
func repondre(clan_de: Callable, jour: int, diplo, choix: String) -> String:
    for x in en_cours:
        if x["etat"] != "pourparlers" or (x["att"] != "joueur" and x["dst"] != "joueur"):
            continue
        var att = clan_de.call(x["att"])
        var dst = clan_de.call(x["dst"])
        if x["dst"] == "joueur":
            if choix == "resister":
                _resoudre(x, att, dst, jour, diplo)
                return ""
            if choix == "offrir":
                var n: int = _presents(att.population, x["ids"]).size()
                var offre: float = minf(_attendu(dst, n) * PART_RANCON, float(dst.ressources.total_aliments()))
                if offre < 1.0:
                    return "Nous n'avons pas de vivres à offrir."
                x["offre"] = offre
                _traiter_offre(x, att, dst, jour, diplo, true)
                if x["etat"] == "retour" and x["issue"] == "negocie":
                    return ""
                return "Ils ont refusé l'offre (%d kg) : le combat a lieu." % int(offre)
        else:
            if choix == "accepter":
                _traiter_offre(x, att, dst, jour, diplo, true)
                return ""
            if choix == "attaquer":
                _traiter_offre(x, att, dst, jour, diplo, false)
                return ""
        return "Choix inconnu."
    return "Aucun raid n'attend de réponse."

# Le raid qui attend la réponse du joueur ({} s'il n'y en a pas).
func en_attente() -> Dictionary:
    for x in en_cours:
        if x["etat"] == "pourparlers" and (x["att"] == "joueur" or x["dst"] == "joueur"):
            return x
    return {}

func _presents(pop, ids: Array) -> Array:
    return pop.habitants.filter(func(h): return ids.has(int(h["id"])))

# Les pertes : mort avec la probabilité p, blessure grave (santé -30) jusqu'à 3p.
func _pertes(pop, groupe: Array, p: float) -> Array:
    var morts := 0
    var blesses := 0
    for h in groupe.duplicate():
        var u: float = rng.randf()
        if u < p:
            pop._mourir(h)
            morts += 1
        elif u < p * 3.0:
            h["sante"] = maxi(10, int(h["sante"]) - 30)
            blesses += 1
    return [morts, blesses]

func _resoudre(x: Dictionary, att, dst, jour: int, diplo) -> void:
    x["etat"] = "retour"
    if att == null or (att.has_method("vivant") and not att.vivant()):
        x["etat"] = "fini"
        x["issue"] = "perdu"
        return
    var groupe: Array = _presents(att.population, x["ids"])
    if groupe.is_empty() or dst == null or (dst.has_method("vivant") and not dst.vivant()):
        x["issue"] = "annule"
        return
    var A: float = float(x["force"]) * float(groupe.size()) / float(maxi(1, x["ids"].size())) * rng.randf_range(0.85, 1.15)
    var D: float = maxf(0.1, float(dst.guerre.defense(dst.population, dst.equipement, dst.clotures, dst.ressources, jour)))
    var ratio: float = A / D
    var issue := "defaite"
    var part := 0.0
    if ratio >= 1.5:
        issue = "victoire"
        part = 1.0
    elif ratio >= 1.0:
        issue = "partiel"
        part = 0.5
    elif ratio >= 0.6:
        issue = "repousse"
    var partage: float = D / (A + D)
    var defenseurs: Array = dst.guerre.combattants(dst.population, dst.ressources, jour)
    var pa: Array = _pertes(att.population, groupe, 0.30 * partage * partage)
    var pd: Array = _pertes(dst.population, defenseurs, 0.30 * (1.0 - partage) * (1.0 - partage))
    x["morts_att"] = pa[0]
    x["blesses_att"] = pa[1]
    x["morts_def"] = pd[0]
    x["blesses_def"] = pd[1]
    var vivants: int = groupe.size() - int(pa[0])
    var butin := 0.0
    if part > 0.0 and vivants > 0:
        var voulu: float = minf(float(dst.ressources.total_aliments()) * BUTIN_PART * part, float(vivants) * CHARGE_KG)
        if voulu > 0.5 and dst.ressources.retirer_vivres(voulu, "pillage"):
            butin = voulu
    x["butin"] = butin
    x["issue"] = issue
    if diplo != null:
        var effet: float = -30.0 if part > 0.0 else -20.0
        diplo.noter(x["att"], x["dst"], "raid", effet, "raid de %s" % _nom(att, x["att"]), jour)
    var txt: String = {"victoire": "victoire", "partiel": "succès partiel", "repousse": "attaque repoussée", "defaite": "défaite"}[issue]
    _dire(x["att"], x["dst"], "Raid de %s sur %s : %s (force %.1f contre défense %.1f). Butin %d kg, morts %d contre %d, blessés %d contre %d." % [_nom(att, x["att"]), _nom(dst, x["dst"]), txt, A, D, int(butin), x["morts_att"], x["morts_def"], x["blesses_att"], x["blesses_def"]])

func _rentrer(x: Dictionary, att, jour: int) -> void:
    x["etat"] = "fini"
    if att == null or (att.has_method("vivant") and not att.vivant()):
        return
    if float(x["butin"]) > 0.0:
        att.ressources.ajouter_vivres(float(x["butin"]), "pillage")
    var survivants: int = _presents(att.population, x["ids"]).size()
    _dire(x["att"], x["dst"], "Raid : %d guerrier(s) de %s rentrent, %d kg de vivres rapportés." % [survivants, _nom(att, x["att"]), int(x["butin"])])

# Seuls les raids qui touchent le joueur entrent dans son histoire.
func _dire(a: String, b: String, texte: String) -> void:
    if a == "joueur" or b == "joueur":
        evenement.emit(texte)

func texte(cle: String) -> String:
    var l: PackedStringArray = []
    for x in en_cours:
        if x["etat"] == "pourparlers":
            l.append("Pourparlers avec %s : réponse avant le jour %d." % [x["dst"] if x["att"] == cle else x["att"], int(x["limite"])])
        elif x["att"] == cle:
            l.append("En route vers %s : arrivée au jour %d, retour au jour %d." % [x["dst"], int(x["arrivee"]), int(x["retour"])])
    var n := 0
    for i in range(historique.size() - 1, -1, -1):
        var x: Dictionary = historique[i]
        if x["att"] != cle and x["dst"] != cle:
            continue
        l.append("Jour %d : %s -> %s, %s, butin %d kg, morts %d/%d." % [int(x["depart"]), x["att"], x["dst"], x["issue"], int(x["butin"]), int(x["morts_att"]), int(x["morts_def"])])
        n += 1
        if n >= 3:
            break
    return "\n".join(l)

func vers_dict() -> Dictionary:
    return {"en_cours": en_cours, "historique": historique}

func depuis_dict(d: Dictionary) -> void:
    en_cours = []
    historique = []
    for src in [["en_cours", en_cours], ["historique", historique]]:
        for x in d.get(src[0], []):
            var y: Dictionary = x.duplicate()
            y["ids"] = x.get("ids", []).map(func(i): return int(i))
            for k in ["depart", "arrivee", "retour", "morts_att", "morts_def", "blesses_att", "blesses_def", "limite"]:
                y[k] = int(x.get(k, 0))
            y["alerte"] = bool(x.get("alerte", false))
            for k in ["force", "butin", "kg", "offre"]:
                y[k] = float(x.get(k, 0.0))
            src[1].append(y)
