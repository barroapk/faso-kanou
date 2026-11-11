extends RefCounted

signal naissance(habitant)
signal deces(habitant)
signal union(mari, femme)
signal entree(habitant)
signal sortie(habitant)

const JOURS_PAR_AN := 360
const AGE_ADULTE := 14
const PRENOMS_H := ["Ousmane", "Issa", "Adama", "Moussa", "Salif", "Karim", "Boukary", "Noaga", "Idrissa", "Seydou"]
const PRENOMS_F := ["Aminata", "Fatimata", "Mariam", "Awa", "Salimata", "Rasmata", "Zalissa", "Assita", "Kadiatou", "Bintou"]

# ---------- Démographie (réglages) ----------
const AGE_UNION_F := 16
const AGE_UNION_H := 18
const AGE_MAX_UNION := 50
const ECART_AGE_MAX := 15
const P_UNION_MOIS := 0.05          # chance par mois qu'une célibataire trouve un conjoint
const TAUX_STERILITE := 0.10        # tiré une seule fois, à la formation du couple
const GROSSESSE_JOURS := 270
const REPOS_APRES_NAISSANCE := 18 * 30
# Chance de conception par mois selon l'âge de la mère.
const FECONDITE := [[16, 19, 0.08], [20, 29, 0.10], [30, 34, 0.08], [35, 39, 0.05], [40, 44, 0.02]]
const MORTALITE_AVANT_5 := 0.18     # cumulée de la naissance à 5 ans
const PART_PREMIERE_ANNEE := 0.6    # part de ces décès pendant la première année
const MORTALITE_AN := [[5, 14, 0.003], [15, 49, 0.006]]   # risque par an
const MORTALITE_EN_COUCHES := 0.005
const AUTORISER_COUSINS := true      # cousins germains de lignées différentes
const RISQUE_COUSINS := 1.3          # mortalité avant 5 ans multipliée pour leurs enfants

# ---------- Compétences individuelles (v0.3.11) ----------
# Chaque habitant a des savoirs (0 à 100) : h["savoirs"] = {savoir: niveau}.
# h["competence"] reste le niveau dans le savoir de son métier actuel
# (c'est lui qu'utilisent la production et le chef).
# Les métiers, leurs savoirs et les rôles secondaires viennent de data/metiers.json (v0.3.42).
const GAIN_PRATIQUE := 0.02        # par jour, de moins en moins vite près de 100 (10 -> ~50 en 10 ans)
const COEF_APPRENTI := 1.5         # travailler à côté d'un maître (60 et plus)
const NIVEAU_MAITRE := 60.0
const OUBLI_JOUR := 0.003          # savoir non pratiqué : environ -1 point par an
const PLANCHER_OUBLI := 0.5        # on n'oublie pas plus de la moitié de son meilleur niveau
const APPRENTISSAGE_ENFANT := 0.01 # de 8 à 13 ans, l'enfant initié apprend le métier d'un parent
const AGE_APPRENTISSAGE := 8
# Soins (v0.3.45) : un guérisseur soigne les plus affaiblis avec des plantes médicinales réelles.
const SOINS_PAR_GUERISSEUR := 3    # malades soignés par jour et par guérisseur
const PLANTES_PAR_SOIN := 0.05     # kg de plantes consommés par malade soigné
const SEUIL_SOINS := 80            # on soigne ceux dont la santé est sous ce niveau
const PART_GUERISSEURS := 0.2      # au plus un cinquième des adultes aptes
const CUEILLETTE_MIN_GUERISSEUR := 30.0   # connaître assez les plantes

var habitants: Array = []
var prochain_id := 1
var couples: Array = []
var prochain_couple := 1
var _archives := {}
var postes := {"chasseur": 1, "cueilleur": 2, "porteur d'eau": 1, "bâtisseur": 1}
var rng := RandomNumberGenerator.new()

func creer_clan_initial(jour: int, graine := 2026) -> void:
    rng.seed = graine
    habitants = []
    couples = []
    prochain_id = 1
    prochain_couple = 1
    # Fondateurs : 3 couples déclarés ; parents des adultes inconnus (-1).
    var ousmane := _ajouter("Ousmane", "Ouédraogo", "H", 35, 1, "chef", jour)
    var aminata := _ajouter("Aminata", "Ouédraogo", "F", 30, 1, "cueilleur", jour)
    var issa := _ajouter("Issa", "Ouédraogo", "H", 8, 1, "enfant", jour, true, "chasseur")
    var awa := _ajouter("Awa", "Ouédraogo", "F", 5, 1, "enfant", jour, true, "cueilleur")
    var adama := _ajouter("Adama", "Kaboré", "H", 28, 2, "chasseur", jour)
    var mariam := _ajouter("Mariam", "Kaboré", "F", 24, 2, "cueilleur", jour)
    var salif := _ajouter("Salif", "Kaboré", "H", 2, 2, "enfant", jour, true, "chasseur")
    var boukary := _ajouter("Boukary", "Zongo", "H", 26, 3, "bâtisseur", jour)
    var fatimata := _ajouter("Fatimata", "Zongo", "F", 22, 3, "porteur d'eau", jour)
    var tenga := _ajouter("Tenga", "Zongo", "H", 58, 3, "ancien", jour)
    for enfant in [issa, awa]:
        enfant["pere"] = ousmane["id"]
        enfant["mere"] = aminata["id"]
    salif["pere"] = adama["id"]
    salif["mere"] = mariam["id"]
    boukary["pere"] = tenga["id"]
    var c1 := _nouveau_couple(ousmane, aminata, jour - 12 * JOURS_PAR_AN)
    c1["enfants"] = [issa["id"], awa["id"]]
    c1["dernier_enfant"] = int(awa["naissance"])
    var c2 := _nouveau_couple(adama, mariam, jour - 4 * JOURS_PAR_AN)
    c2["enfants"] = [salif["id"]]
    c2["dernier_enfant"] = int(salif["naissance"])
    _nouveau_couple(boukary, fatimata, jour - 1 * JOURS_PAR_AN)

# Clan créé à partir d'une fiche (data/clans.json) : mêmes règles que le clan du joueur.
func creer_depuis_fiche(fiche: Dictionary, jour: int) -> void:
    rng.seed = int(fiche.get("graine", 2026))
    habitants = []
    couples = []
    _archives = {}
    prochain_id = 1
    prochain_couple = 1
    var liste := []
    for f in fiche["fondateurs"]:
        var h := _ajouter(f["prenom"], f["nom"], f["sexe"], int(f["age"]), int(f["famille"]), f["metier"], jour, true, f.get("initie", ""))
        liste.append(h)
    for i in fiche["fondateurs"].size():
        var f: Dictionary = fiche["fondateurs"][i]
        if int(f.get("pere", -1)) >= 0:
            liste[i]["pere"] = int(liste[int(f["pere"])]["id"])
        if int(f.get("mere", -1)) >= 0:
            liste[i]["mere"] = int(liste[int(f["mere"])]["id"])
    for c in fiche.get("couples", []):
        var k := _nouveau_couple(liste[int(c[0])], liste[int(c[1])], jour - int(c[2]) * JOURS_PAR_AN)
        for h in liste:
            if int(h["pere"]) == int(k["mari"]) and int(h["mere"]) == int(k["femme"]):
                k["enfants"].append(int(h["id"]))
                k["dernier_enfant"] = maxi(int(k["dernier_enfant"]), int(h["naissance"]))
    for m in fiche.get("postes", {}):
        postes[m] = int(fiche["postes"][m])

func _ajouter(prenom: String, nom: String, sexe: String, age_ans: int, famille: int, metier: String, jour: int, decaler := true, initie := "") -> Dictionary:
    var ecart := rng.randi_range(0, JOURS_PAR_AN - 1) if decaler else 0
    var h := {
        "id": prochain_id,
        "prenom": prenom,
        "nom": nom,
        "sexe": sexe,
        "naissance": jour - age_ans * JOURS_PAR_AN - ecart,
        "famille": famille,
        "metier": metier,
        "initie": initie,
        "sante": 100,
        "competence": float(clampi(age_ans * 2, 0, 70)),
        "pere": -1,
        "mere": -1,
        "savoirs": {},
        "savoirs_max": {},
    }
    # Savoir de départ : celui de son métier (niveau = âge x 2, 70 au plus) ;
    # tout adulte sait au moins un peu cueillir.
    if age_ans >= AGE_ADULTE:
        donner_savoir(h, "cueillette", float(clampi(int(age_ans * 1.5), 0, 50)))
    var sv := savoir_du_metier(metier)
    if sv != "":
        donner_savoir(h, sv, float(clampi(age_ans * 2, 0, 70)))
    maj_competence(h)
    prochain_id += 1
    habitants.append(h)
    return h

func age(h: Dictionary, jour: int) -> int:
    return int((jour - int(h["naissance"])) / JOURS_PAR_AN)

func nombre(m: String) -> int:
    var n := 0
    for h in habitants:
        if h["metier"] == m:
            n += 1
    return n

# peut_naitre : condition de nourriture (donnée par la civilisation).
# logement : nombre de places ; une grossesse compte déjà comme une place.
func mois_passe(jour: int, peut_naitre := true, logement := 1000000) -> void:
    _fermer_couples(jour)
    _deces_du_mois(jour)
    _fermer_couples(jour)
    _naissances(jour, logement)
    _former_couples(jour)
    _conceptions(jour, peut_naitre, logement)
    for h in habitants:
        if h["metier"] == "enfant" and age(h, jour) >= AGE_ADULTE:
            h["metier"] = "sans métier"
            maj_competence(h)

# ---------- Mortalité ----------

func risque_mois(h: Dictionary, jour: int) -> float:
    var a := age(h, jour)
    var coef := RISQUE_COUSINS if h.get("consanguin", false) else 1.0
    if a < 1:
        return (1.0 - pow(1.0 - MORTALITE_AVANT_5 * PART_PREMIERE_ANNEE, 1.0 / 12.0)) * coef
    if a < 5:
        var survie_1_4 := (1.0 - MORTALITE_AVANT_5) / (1.0 - MORTALITE_AVANT_5 * PART_PREMIERE_ANNEE)
        return (1.0 - pow(survie_1_4, 1.0 / 48.0)) * coef
    var r := 0.0
    for t in MORTALITE_AN:
        if a >= t[0] and a <= t[1]:
            r = 1.0 - pow(1.0 - t[2], 1.0 / 12.0)
    if a >= 50:
        r = 1.0 - pow(1.0 - 0.006, 1.0 / 12.0) + (a - 50) * 0.0008
    return r

func _deces_du_mois(jour: int) -> void:
    var morts := []
    for h in habitants:
        if rng.randf() < risque_mois(h, jour):
            morts.append(h)
    for h in morts:
        _mourir(h)

# ---------- Migrations (appelées par migration.gd) ----------

func faire_entrer(h: Dictionary) -> void:
    entree.emit(h)

# Départ du clan : la personne n'est pas morte, mais elle n'est plus là.
func faire_sortir(h: Dictionary, jour: int) -> void:
    _archiver(h)
    habitants.erase(h)
    var c := couple_actif(h)
    if not c.is_empty():
        c["fin"] = jour
    sortie.emit(h)

func _archiver(h: Dictionary) -> void:
    _archives[int(h["id"])] = {"id": h["id"], "nom": h["nom"], "famille": h["famille"], "pere": h.get("pere", -1), "mere": h.get("mere", -1), "metier": h["metier"]}

func nouveau_couple(mari: Dictionary, femme: Dictionary, debut: int) -> Dictionary:
    return _nouveau_couple(mari, femme, debut)

func _mourir(h: Dictionary) -> void:
    _archiver(h)
    habitants.erase(h)
    deces.emit(h)

# ---------- Couples ----------

func _nouveau_couple(mari: Dictionary, femme: Dictionary, debut: int) -> Dictionary:
    var c := {
        "id": prochain_couple,
        "mari": int(mari["id"]),
        "femme": int(femme["id"]),
        "debut": debut,
        "fin": -1,
        "enfants": [],
        "sterile": rng.randf() < TAUX_STERILITE,
        "dernier_enfant": -100000,
        "conception": -1,
    }
    prochain_couple += 1
    couples.append(c)
    return c

func par_id(id: int) -> Dictionary:
    for h in habitants:
        if int(h["id"]) == id:
            return h
    return {}

func couple_actif(h: Dictionary) -> Dictionary:
    var id := int(h["id"])
    for c in couples:
        if int(c["fin"]) < 0 and (int(c["mari"]) == id or int(c["femme"]) == id):
            return c
    return {}

# Un décès termine le couple ; le survivant devient veuf ou veuve.
# Un couple terminé n'est jamais réutilisé.
func _fermer_couples(jour: int) -> void:
    for c in couples:
        if int(c["fin"]) >= 0:
            continue
        if par_id(int(c["mari"])).is_empty() or par_id(int(c["femme"])).is_empty():
            c["fin"] = jour

func _parents(h: Dictionary) -> Array:
    var l := []
    for cle in ["pere", "mere"]:
        var id := int(h.get(cle, -1))
        if id >= 0:
            l.append(id)
    return l

func _grands_parents(h: Dictionary) -> Array:
    var l := []
    for id in _parents(h):
        l.append_array(_parents(_fiche(id)))
    return l

# Fiche d'un habitant vivant ou mort (les morts restent connus par leurs enfants).
func _fiche(id: int) -> Dictionary:
    var h := par_id(id)
    if not h.is_empty():
        return h
    return _archives.get(id, {})

static func _commun(a: Array, b: Array) -> bool:
    for x in a:
        if b.has(x):
            return true
    return false

# Parenté proche, toujours interdite : parent/enfant, grand-parent/petit-enfant,
# frère/sœur, demi-frère/demi-sœur, oncle/tante avec neveu/nièce.
func apparentes(a: Dictionary, b: Dictionary) -> bool:
    var ida := int(a["id"])
    var idb := int(b["id"])
    if ida == idb:
        return true
    var pa := _parents(a)
    var pb := _parents(b)
    var ga := _grands_parents(a)
    var gb := _grands_parents(b)
    if pa.has(idb) or pb.has(ida) or ga.has(idb) or gb.has(ida):
        return true
    if _commun(pa, pb):
        return true
    if _commun(pa, gb) or _commun(pb, ga):
        return true
    if not AUTORISER_COUSINS and _commun(ga, gb):
        return true
    return false

# Cousins germains (grands-parents communs) : permis, avec un risque pour l'enfant.
func cousins(a: Dictionary, b: Dictionary) -> bool:
    return _commun(_grands_parents(a), _grands_parents(b))

func union_permise(f: Dictionary, h: Dictionary, jour: int) -> bool:
    if f["sexe"] != "F" or h["sexe"] != "H":
        return false
    var af := age(f, jour)
    var ah := age(h, jour)
    if af < AGE_UNION_F or ah < AGE_UNION_H or af > AGE_MAX_UNION or ah > 60:
        return false
    if abs(af - ah) > ECART_AGE_MAX:
        return false
    if int(f["famille"]) == int(h["famille"]):
        return false
    if apparentes(f, h):
        return false
    return couple_actif(f).is_empty() and couple_actif(h).is_empty()

func _former_couples(jour: int) -> void:
    for f in habitants.duplicate():
        if f["sexe"] != "F" or not couple_actif(f).is_empty():
            continue
        var af := age(f, jour)
        if af < AGE_UNION_F or af > AGE_MAX_UNION:
            continue
        if rng.randf() >= P_UNION_MOIS:
            continue
        var candidats := []
        for h in habitants:
            if union_permise(f, h, jour):
                candidats.append(h)
        if candidats.is_empty():
            continue
        var mari: Dictionary = candidats[rng.randi() % candidats.size()]
        _nouveau_couple(mari, f, jour)
        union.emit(mari, f)

# ---------- Fécondité et naissances ----------

func fecondite_mois(c: Dictionary, mere: Dictionary, jour: int) -> float:
    var a := age(mere, jour)
    var p := 0.0
    for t in FECONDITE:
        if a >= t[0] and a <= t[1]:
            p = t[2]
    var duree := (jour - int(c["debut"])) / JOURS_PAR_AN
    if duree >= 20:
        p *= 0.7
    elif duree >= 10:
        p *= 0.85
    return p

func grossesses() -> int:
    var n := 0
    for c in couples:
        if int(c["conception"]) >= 0:
            n += 1
    return n

func _conceptions(jour: int, peut_naitre: bool, logement: int) -> void:
    if not peut_naitre:
        return
    for c in couples:
        if int(c["fin"]) >= 0 or c["sterile"] or int(c["conception"]) >= 0:
            continue
        if jour - int(c["dernier_enfant"]) < REPOS_APRES_NAISSANCE:
            continue
        if habitants.size() + grossesses() >= logement:
            return
        var mere := par_id(int(c["femme"]))
        if rng.randf() < fecondite_mois(c, mere, jour):
            c["conception"] = jour

func _naissances(jour: int, logement: int) -> void:
    for c in couples:
        var debut := int(c["conception"])
        if debut < 0 or jour - debut < GROSSESSE_JOURS:
            continue
        c["conception"] = -1
        var mere := par_id(int(c["femme"]))
        if mere.is_empty():
            continue
        var pere := _fiche(int(c["mari"]))
        var sexe := "H" if rng.randf() < 0.5 else "F"
        var liste: Array = PRENOMS_H if sexe == "H" else PRENOMS_F
        var parent: Dictionary = pere if sexe == "H" else mere
        var initie: String = parent.get("metier", "") if postes.has(parent.get("metier", "")) else ""
        var bebe := _ajouter(liste[rng.randi() % liste.size()], pere["nom"], sexe, 0, int(pere["famille"]), "enfant", jour, false, initie)
        bebe["pere"] = int(pere["id"])
        bebe["mere"] = int(mere["id"])
        if cousins(pere, mere):
            bebe["consanguin"] = true
        c["enfants"].append(int(bebe["id"]))
        c["dernier_enfant"] = jour
        naissance.emit(bebe)
        if rng.randf() < MORTALITE_EN_COUCHES:
            _mourir(mere)

func repartir(jour: int) -> void:
    for m in postes:
        var travailleurs := []
        for h in habitants:
            if h["metier"] == m:
                travailleurs.append(h)
        travailleurs.sort_custom(func(a, b): return float(a["competence"]) > float(b["competence"]))
        while travailleurs.size() > int(postes[m]):
            var h = travailleurs.pop_back()
            h["metier"] = "sans métier"
            maj_competence(h)
    for m in postes:
        var manque := int(postes[m]) - nombre(m)
        while manque > 0:
            var candidat = _meilleur_candidat(m, jour)
            if candidat == null:
                break
            candidat["metier"] = m
            maj_competence(candidat)
            manque -= 1

func _meilleur_candidat(m: String, jour: int):
    var meilleur = null
    var score_max := -1.0
    for h in habitants:
        if h["metier"] != "sans métier" or age(h, jour) < AGE_ADULTE or h.has("expedition"):
            continue
        var score := savoir(h, savoir_du_metier(m)) + (100.0 if h.get("initie", "") == m else 0.0)
        if score > score_max:
            score_max = score
            meilleur = h
    return meilleur

func changer_postes(m: String, delta: int, jour: int) -> void:
    postes[m] = maxi(0, int(postes.get(m, 0)) + delta)
    repartir(jour)

# Plafond de santé quand le sel manque : rien pendant 30 jours, puis -1 point
# tous les 6 jours, jusqu'à 60 au plus bas. Le manque de sel seul ne tue pas.
static func plafond_sante(jours_sans_sel: int) -> int:
    return 100 - clampi((jours_sans_sel - 30) / 6, 0, 40)

func jour_passe(faim: bool, soif: bool, jours_sans_sel := 0, jour := -1) -> void:
    pratiquer(jour)
    var morts := []
    var plafond := plafond_sante(jours_sans_sel)
    for h in habitants:
        var s := int(h["sante"])
        if soif:
            s -= 4
        elif faim:
            s -= 2
        else:
            s += 1
        if s > plafond:
            s = maxi(plafond, int(h["sante"]) - 1) if int(h["sante"]) > plafond else plafond
        h["sante"] = clampi(s, 0, 100)
        if h["sante"] == 0:
            morts.append(h)
    for h in morts:
        _mourir(h)

# ---------- Guérisseurs et soins (v0.3.45) ----------

func _aptes_guerison(jour: int) -> Array:
    var l: Array = []
    for h in habitants:
        if age(h, jour) < 16 or int(h["sante"]) < 50:
            continue
        if ["chef", "enfant"].has(h["metier"]):
            continue
        if h.has("role") and h["role"] != "guerisseur":
            continue
        if savoir(h, "cueillette") < CUEILLETTE_MIN_GUERISSEUR and savoir(h, "medecine") <= 0.0:
            continue
        l.append(h)
    return l

func nb_guerisseurs() -> int:
    return habitants.filter(func(h): return h.get("role", "") == "guerisseur").size()

func max_guerisseurs(jour: int) -> int:
    return int(floor(_aptes_guerison(jour).size() * PART_GUERISSEURS))

# Désigne n guérisseurs : les plus savants en médecine d'abord, puis ceux déjà en place.
func fixer_guerisseurs(jour: int, n: int) -> int:
    var l: Array = _aptes_guerison(jour)
    l.sort_custom(func(x, y):
        var cx: float = savoir(x, "medecine")
        var cy: float = savoir(y, "medecine")
        if cx != cy:
            return cx > cy
        var rx: bool = x.get("role", "") == "guerisseur"
        var ry: bool = y.get("role", "") == "guerisseur"
        if rx != ry:
            return rx
        return int(x["id"]) < int(y["id"]))
    for h in habitants:
        if h.get("role", "") == "guerisseur":
            h.erase("role")
    n = clampi(n, 0, max_guerisseurs(jour))
    for i in range(n):
        l[i]["role"] = "guerisseur"
        if savoir(l[i], "medecine") <= 0.0:
            donner_savoir(l[i], "medecine", 0.3 * savoir(l[i], "cueillette"))
    return n

# Chaque jour : soigne les plus affaiblis, tant qu'il y a des plantes. Renvoie le nombre de malades soignés.
# SOINS_PAR_GUERISSEUR est la capacité d'un guérisseur avec 25 % de son temps (le rôle).
# Infirmerie (v0.3.46) : places et bonus viennent des bâtiments ; elle ne sert à rien sans guérisseur,
# et ne fait jamais suivre plus de malades en plus que les guérisseurs n'en suivent déjà.
# Les membres d'une expédition ne sont pas soignés.
# Guérisseurs libres aujourd'hui, habitants à soigner, soins possibles par jour (utilisés aussi par le gouvernement).
func guerisseurs_dispos() -> Array:
    return habitants.filter(func(h): return h.get("role", "") == "guerisseur" and not h.get("occupe", false))

func a_soigner() -> Array:
    return habitants.filter(func(h): return int(h["sante"]) < SEUIL_SOINS and not h.has("expedition"))

func capacite_soins(places := 0) -> int:
    var base: int = guerisseurs_dispos().size() * SOINS_PAR_GUERISSEUR
    return base + mini(places, base)

func soigner(res, jour: int, places := 0, bonus := 0.0) -> int:
    var gs: Array = guerisseurs_dispos()
    if gs.is_empty():
        return 0
    var malades: Array = a_soigner()
    if malades.is_empty():
        return 0
    malades.sort_custom(func(a, b): return int(a["sante"]) < int(b["sante"]))
    var meilleur := 0.0
    for g in gs:
        meilleur = maxf(meilleur, savoir(g, "medecine"))
    var extra: int = 1 + int(round(2.0 * meilleur / 100.0))
    var plafond: int = plafond_sante(res.jours_sans_sel)
    var capacite: int = capacite_soins(places)
    var n := 0
    for m in malades:
        if n >= capacite:
            break
        if not res.retirer("plantes_medicinales", PLANTES_PAR_SOIN, "soin"):
            break
        var e: int = int(round(extra * (1.0 + bonus))) if n < places else extra
        var s: int = int(m["sante"])
        m["sante"] = maxi(s, mini(plafond, s + e))   # un soin ne fait jamais baisser la santé
        n += 1
    return n

# ---------- Savoirs ----------

static var _catalogue := {}

static func _charger() -> Dictionary:
    if _catalogue.is_empty():
        var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/metiers.json"))
        _catalogue = d if typeof(d) == TYPE_DICTIONARY else {"metiers": {}, "roles": {}}
    return _catalogue

static func savoir_du_metier(m: String) -> String:
    return str(_charger().get("metiers", {}).get(m, {}).get("savoir", ""))

# Rôle secondaire (protecteur...) : savoir pratiqué à côté, et part de temps prise sur le métier.
static func savoir_du_role(h: Dictionary) -> String:
    return str(_charger().get("roles", {}).get(str(h.get("role", "")), {}).get("savoir", ""))

static func part_libre(h: Dictionary) -> float:
    if not h.has("role"):
        return 1.0
    return 1.0 - float(_charger().get("roles", {}).get(str(h["role"]), {}).get("temps", 0.0))

func savoir(h: Dictionary, s: String) -> float:
    if s == "":
        return 0.0
    return float(h.get("savoirs", {}).get(s, 0.0))

func donner_savoir(h: Dictionary, s: String, niveau: float) -> void:
    if not h.has("savoirs"):
        h["savoirs"] = {}
        h["savoirs_max"] = {}
    h["savoirs"][s] = clampf(niveau, 0.0, 100.0)
    h["savoirs_max"][s] = maxf(float(h["savoirs_max"].get(s, 0.0)), h["savoirs"][s])

# Niveau dans le savoir du métier ; pour un enfant ou un ancien : son meilleur savoir.
func maj_competence(h: Dictionary) -> void:
    var s := savoir_du_metier(h["metier"])
    if s != "":
        h["competence"] = savoir(h, s)
        return
    var m := 0.0
    for x in h.get("savoirs", {}):
        m = maxf(m, float(h["savoirs"][x]))
    h["competence"] = m

# Ce que chaque personne pratique aujourd'hui : la tâche d'une recette (h["tache"]),
# sinon le savoir de son métier. Les enfants initiés apprennent dès 8 ans.
func pratiquer(jour: int) -> void:
    var maitres := {}
    var heros := {}               # savoir -> bonus du héros artisan présent qui l'exerce
    for h in habitants:
        if h.get("heros", {}).get("type", "") == "artisan" and not h.get("occupe", false) and not h.has("expedition"):
            var sh: String = savoir_du_metier(h["metier"])
            if sh != "":
                heros[sh] = [0.10, 0.15, 0.20][clampi(int(h["heros"]["niveau"]), 0, 2)]
    for h in habitants:
        var s: String = h.get("tache", savoir_du_metier(h["metier"]))
        if s != "" and savoir(h, s) >= NIVEAU_MAITRE:
            maitres[s] = true
    for h in habitants:
        if h["metier"] == "ancien":
            continue
        var pratique := ""
        if h["metier"] == "enfant":
            var ini: String = h.get("initie", "")
            if ini != "" and jour >= 0 and age(h, jour) >= AGE_APPRENTISSAGE:
                var si := savoir_du_metier(ini)
                if si != "" and savoir(h, si) < 25.0:
                    donner_savoir(h, si, savoir(h, si) + APPRENTISSAGE_ENFANT)
                pratique = si
        else:
            pratique = h.get("tache", savoir_du_metier(h["metier"]))
            if pratique != "":
                var n := savoir(h, pratique)
                var gain := GAIN_PRATIQUE * (1.0 - n / 100.0)
                if maitres.has(pratique) and n < NIVEAU_MAITRE:
                    gain *= COEF_APPRENTI
                if heros.has(pratique) and not h.has("heros"):
                    gain *= 1.0 + float(heros[pratique])
                donner_savoir(h, pratique, n + gain)
        var aussi: String = savoir_du_role(h)
        if aussi != "" and aussi != pratique:
            var na: float = savoir(h, aussi)
            var gr: float = float(_charger()["roles"][str(h["role"])].get("gain", 0.5))
            donner_savoir(h, aussi, na + GAIN_PRATIQUE * gr * (1.0 - na / 100.0))
        for s in h.get("savoirs", {}).keys():
            if s == pratique or s == aussi:
                continue
            var plancher := float(h["savoirs_max"].get(s, 0.0)) * PLANCHER_OUBLI
            if float(h["savoirs"][s]) > plancher:
                h["savoirs"][s] = maxf(plancher, float(h["savoirs"][s]) - OUBLI_JOUR)
        if h["metier"] != "enfant":
            maj_competence(h)

# Ancienne sauvegarde : le niveau connu devient le savoir du métier.
func _migrer_savoirs(h: Dictionary) -> void:
    if h.has("savoirs") and typeof(h["savoirs"]) == TYPE_DICTIONARY:
        var sv := {}
        var mx := {}
        for s in h["savoirs"]:
            sv[str(s)] = float(h["savoirs"][s])
        for s in h.get("savoirs_max", {}):
            mx[str(s)] = float(h["savoirs_max"][s])
        h["savoirs"] = sv
        h["savoirs_max"] = mx
        return
    h["savoirs"] = {}
    h["savoirs_max"] = {}
    var s := savoir_du_metier(h["metier"])
    if s != "":
        donner_savoir(h, s, float(h["competence"]))
    if not h["savoirs"].has("cueillette") and h["metier"] != "enfant":
        donner_savoir(h, "cueillette", minf(float(h["competence"]), 50.0))
    maj_competence(h)

func metiers_choisis() -> Array:
    var l: Array = []
    var m: Dictionary = _charger().get("metiers", {})
    for k in m:
        if bool(m[k].get("choisi", false)):
            l.append(k)
    return l

func nom_metier(h: Dictionary) -> String:
    var m: String = h["metier"]
    return str(_charger().get("metiers", {}).get(m, {}).get("feminin", m)) if h["sexe"] == "F" else m

func peut_changer(h: Dictionary, jour: int) -> bool:
    return age(h, jour) >= AGE_ADULTE and h["metier"] != "chef"

func changer_metier(h: Dictionary, m: String) -> void:
    var ancien: String = h["metier"]
    if ancien == m:
        return
    if postes.has(ancien):
        postes[ancien] = maxi(0, int(postes[ancien]) - 1)
    if postes.has(m):
        postes[m] = int(postes[m]) + 1
    h["metier"] = m
    maj_competence(h)

func vers_dict() -> Dictionary:
    return {"habitants": habitants, "prochain_id": prochain_id, "postes": postes, "couples": couples, "prochain_couple": prochain_couple, "archives": _archives.values(), "graine": str(rng.seed), "etat": str(rng.state)}

func depuis_dict(d: Dictionary) -> void:
    habitants = []
    for h in d.get("habitants", []):
        for cle in ["id", "naissance", "famille", "sante"]:
            h[cle] = int(h[cle])
        h["pere"] = int(h.get("pere", -1))
        h["mere"] = int(h.get("mere", -1))
        if h.has("consanguin"):
            h["consanguin"] = bool(h["consanguin"])
        h["competence"] = float(h.get("competence", 50.0))
        h["metier"] = _migrer_metier(h["metier"])
        h["initie"] = _migrer_metier(h.get("initie", ""))
        _migrer_savoirs(h)
        habitants.append(h)
    prochain_id = int(d.get("prochain_id", 1))
    couples = []
    for c in d.get("couples", []):
        var enfants := []
        for e in c.get("enfants", []):
            enfants.append(int(e))
        couples.append({"id": int(c["id"]), "mari": int(c["mari"]), "femme": int(c["femme"]), "debut": int(c["debut"]), "fin": int(c["fin"]), "enfants": enfants, "sterile": bool(c["sterile"]), "dernier_enfant": int(c["dernier_enfant"]), "conception": int(c["conception"])})
    prochain_couple = int(d.get("prochain_couple", couples.size() + 1))
    _archives = {}
    for x in d.get("archives", []):
        _archives[int(x["id"])] = {"id": int(x["id"]), "nom": str(x["nom"]), "famille": int(x["famille"]), "pere": int(x["pere"]), "mere": int(x["mere"]), "metier": str(x["metier"])}
    var p: Dictionary = d.get("postes", {})
    for m in postes:
        postes[m] = int(p.get(m, nombre(m)))
    rng.seed = int(d.get("graine", "2026"))
    rng.state = int(d.get("etat", "0"))

func _migrer_metier(m: String) -> String:
    match m:
        "cueilleuse":
            return "cueilleur"
        "porteuse d'eau":
            return "porteur d'eau"
    return m
