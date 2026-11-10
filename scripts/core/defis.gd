extends RefCounted

# Ascension du clan (v0.3.23) : époques, défis et décisions.
# But : que le joueur ait toujours quelque chose à poursuivre, des surprises,
# des choix qui comptent, et qu'il VOIE sa progression.
# 1. ÉPOQUES : on ne change pas d'époque avec un compteur, mais en ACCOMPLISSANT
#    des choses (récolter, construire un port, explorer, se faire des amis...).
# 2. DÉFIS : tirés de la situation réelle du clan, à court, moyen et long terme.
#    Réussir donne de la renommée et la confiance du clan. Pas de tâches
#    artificielles : chaque défi répond à un vrai problème ou une vraie ambition.
# 3. DÉCISIONS : des situations imprévues (bêtes dans un champ, marchand étranger,
#    proposition d'alliance) avec des choix et des conséquences réelles.
#    Sans réponse à temps, le clan subit l'option par défaut.

signal evenement(texte)

const EPOQUES := ["Fondation", "Expansion", "Navigation", "Puissance", "Civilisation", "Ère moderne"]
const RECOMPENSE := {"court": 3, "moyen": 6, "long": 12}   # renommée (et confiance du clan)

var epoque := 0
var renommee := 0
var defis: Array = []            # {cle, horizon, texte, fin, depart}
var decisions: Array = []        # {cle, titre, texte, options: [texte], fin, donnees}
var occupes := {}                # id habitant -> jour de fin (veilles, corvées d'événement)
var rng := RandomNumberGenerator.new()

func _init() -> void:
    rng.seed = 2468

# ---------- 1. Époques ----------

# Conditions pour passer à l'époque suivante : [texte, accompli ?].
# Les MÊMES pour tous les clans (joueur et ordinateur).
func conditions(C) -> Array:
    return conditions_clan(epoque, C, "joueur", C.voisins.map(func(v): return v.id), C.diplomatie, C.expeditions.connues.size())

static func conditions_clan(epoque: int, C, id: String, autres: Array, diplomatie, iles_connues: int) -> Array:
    var amis := 0
    var allies := 0
    for a in autres:
        if a == id:
            continue
        var e: String = diplomatie.etat(id, a)
        if e in ["amitié", "alliance"]:
            amis += 1
        if e == "alliance":
            allies += 1
    match epoque:
        0:
            return [["Connaître l'agriculture", C.decouvertes.connait("agriculture")],
                ["Réussir une récolte", C.agriculture.recoltes > 0],
                ["Construire un grenier", C.construction.nombre("grenier") > 0],
                ["Atteindre 15 habitants", C.population.habitants.size() >= 15]]
        1:
            return [["Un port relié par la route", C.flotte.niveau_port(C.construction, C.routes) >= 1],
                ["Posséder 2 bateaux", C.flotte.bateaux.size() >= 2],
                ["Découvrir une autre île", iles_connues >= 2],
                ["Commercer par la mer", C.economie.transactions.size() > 0]]
        2:
            return [["Connaître 4 îles", iles_connues >= 5],
                ["Être ami ou allié de 2 clans", amis >= 2],
                ["Ouvrir une mine ou une carrière", C.gisements.ouverts().size() > 0],
                ["Atteindre 40 habitants", C.population.habitants.size() >= 40]]
        3:
            return [["Maîtriser le fer", C.decouvertes.connait("metallurgie")],
                ["Une route empierrée", C.routes.troncons.values().any(func(t): return t["niveau"] in ["route", "boulevard"] and float(t["travail_restant"]) <= 0.0)],
                ["Une alliance", allies >= 1],
                ["Atteindre 100 habitants", C.population.habitants.size() >= 100]]
    return [["L'ère moderne viendra plus tard", false]]

func _amis(C) -> int:
    var n := 0
    for v in C.voisins:
        if C.diplomatie.etat("joueur", v.id) in ["amitié", "alliance"]:
            n += 1
    return n

func _allies(C) -> int:
    var n := 0
    for v in C.voisins:
        if C.diplomatie.etat("joueur", v.id) == "alliance":
            n += 1
    return n

func _verifier_epoque(C) -> void:
    if epoque >= EPOQUES.size() - 1:
        return
    for c in conditions(C):
        if not c[1]:
            return
    epoque += 1
    renommee += 20
    C.conseil.confiance = minf(100.0, C.conseil.confiance + 15.0)
    evenement.emit("NOUVELLE ÉPOQUE : %s ! Le clan est fier de ce qu'il a accompli (renommée +20, confiance +15)." % EPOQUES[epoque])

# ---------- 2. Défis ----------

func _candidats(C) -> Array:
    var l: Array = []
    var a: Dictionary = C.ressources.autonomie(C.population, C.temps.jour_total)
    if float(a.get("eau", 99.0)) < 15.0:
        l.append({"cle": "eau_30", "horizon": "court", "texte": "Constituer 30 jours de réserve d'eau", "duree": 60})
    if float(a.get("nourriture", 99.0)) < 30.0:
        l.append({"cle": "nourriture_60", "horizon": "court", "texte": "Constituer 60 jours de nourriture", "duree": 120})
    if C.agriculture.champs.any(func(c): return not bool(c["defriche"])):
        l.append({"cle": "defricher", "horizon": "court", "texte": "Finir de défricher tous les champs", "duree": 90})
    if C.agriculture.prochaine_recolte() > 0 and C.construction.nombre("grenier") == 0:
        l.append({"cle": "grenier", "horizon": "court", "texte": "Construire un grenier avant la récolte", "duree": C.agriculture.prochaine_recolte() - C.temps.jour_total})
    for id in C.experiences_possibles():
        l.append({"cle": "savoir_" + id, "horizon": "moyen", "texte": "Découvrir : %s" % C.decouvertes.definitions[id]["nom"], "duree": 360})
        break
    if C.expeditions.connues.size() < 5:
        l.append({"cle": "iles_%d" % (C.expeditions.connues.size() + 1), "horizon": "moyen", "texte": "Découvrir une nouvelle île", "duree": 360})
    for t in C.gisements.connus:
        if not bool(C.gisements.connus[t]["ouvert"]):
            l.append({"cle": "site_" + t, "horizon": "moyen", "texte": "Ouvrir : %s" % C.gisements.TYPES[t]["nom"], "duree": 360})
            break
    if C.flotte.niveau_port(C.construction, C.routes) == 0:
        l.append({"cle": "port", "horizon": "moyen", "texte": "Construire un port relié par la route", "duree": 540})
    l.append({"cle": "epoque_%d" % (epoque + 1), "horizon": "long", "texte": "Atteindre l'époque : %s" % EPOQUES[mini(epoque + 1, EPOQUES.size() - 1)], "duree": 3600})
    if _amis(C) < 3:
        l.append({"cle": "amis_3", "horizon": "long", "texte": "Être ami ou allié de 3 clans", "duree": 3600})
    return l

func _reussi(C, cle: String) -> bool:
    var a: Dictionary = C.ressources.autonomie(C.population, C.temps.jour_total)
    if cle == "eau_30":
        return float(a.get("eau", 0.0)) >= 30.0
    if cle == "nourriture_60":
        return float(a.get("nourriture", 0.0)) >= 60.0
    if cle == "defricher":
        return not C.agriculture.champs.any(func(c): return not bool(c["defriche"]))
    if cle == "grenier":
        return C.construction.nombre("grenier") > 0
    if cle.begins_with("savoir_"):
        return C.decouvertes.connait(cle.trim_prefix("savoir_"))
    if cle.begins_with("iles_"):
        return C.expeditions.connues.size() >= int(cle.trim_prefix("iles_"))
    if cle.begins_with("site_"):
        return bool(C.gisements.connus.get(cle.trim_prefix("site_"), {}).get("ouvert", false))
    if cle == "port":
        return C.flotte.niveau_port(C.construction, C.routes) >= 1
    if cle.begins_with("epoque_"):
        return epoque >= int(cle.trim_prefix("epoque_"))
    if cle == "amis_3":
        return _amis(C) >= 3
    return false

func _maj_defis(C) -> void:
    var jour: int = C.temps.jour_total
    for d in defis.duplicate():
        if _reussi(C, d["cle"]):
            defis.erase(d)
            var r: int = RECOMPENSE[d["horizon"]]
            renommee += r
            C.conseil.confiance = minf(100.0, C.conseil.confiance + r * 0.5)
            evenement.emit("Défi réussi : %s ! Renommée +%d." % [d["texte"], r])
        elif jour > int(d["fin"]):
            defis.erase(d)
            evenement.emit("Défi manqué : %s. Le clan retiendra la leçon." % d["texte"])
    # Un défi par horizon : court, moyen, long.
    for horizon in ["court", "moyen", "long"]:
        if defis.any(func(d): return d["horizon"] == horizon):
            continue
        for c in _candidats(C):
            if c["horizon"] == horizon and not _reussi(C, c["cle"]):
                defis.append({"cle": c["cle"], "horizon": horizon, "texte": c["texte"], "depart": jour, "fin": jour + int(c["duree"])})
                evenement.emit("Nouveau défi (%s terme) : %s." % [horizon, c["texte"]])
                break

# ---------- 3. Décisions (situations imprévues) ----------

func _proposer(cle: String, titre: String, texte: String, options: Array, jours: int, jour: int, donnees := {}) -> void:
    if decisions.any(func(d): return d["cle"] == cle):
        return
    decisions.append({"cle": cle, "titre": titre, "texte": texte, "options": options, "fin": jour + jours, "donnees": donnees})
    evenement.emit("DÉCISION : %s — ouvrez l'écran du chef." % titre)

func _situations(C) -> void:
    var jour: int = C.temps.jour_total
    # Sécheresse (v0.3.26) : décidée en mai pour l'année, jamais deux ans de suite,
    # jamais la première année. Elle touche tout l'archipel.
    var an: int = C.temps.annee()
    if C.temps.mois() == 4 and an >= 2 and C.temps.annee_seche < an - 1 and rng.randf() < 0.15:
        C.temps.annee_seche = an
    if C.temps.mois() == 5 and C.temps.secheresse():
        _proposer("secheresse_%d" % an, "Les pluies ne viennent pas",
            "Le ciel reste sec : cette année il pleuvra peu. Les champs non irrigués donneront moins, l'eau manquera.",
            ["Rationner : chacun mange 20 % de moins pendant 120 jours", "Creuser des puits (3 adultes pendant 20 jours)", "Attendre la pluie"], 15, jour)
    # Des bêtes sauvages s'approchent d'un champ semé sans bonne clôture.
    for c in C.agriculture.champs:
        if c["etat"] == "seme" and C.clotures.protection("champ_%d" % int(c["id"])) < 0.3 and rng.randf() < 0.12:
            _proposer("betes_%d" % int(c["id"]), "Des bêtes sauvages autour du champ %d" % int(c["id"]),
                "Des phacochères ravagent les cultures la nuit. Sans veille, un quart de la récolte sera perdu.",
                ["Organiser des veilles (2 adultes pendant 10 jours)", "Laisser faire"], 10, jour, {"champ": int(c["id"])})
            break
    # Un marchand venu d'au-delà de l'archipel accoste (ses marchandises viennent du monde extérieur).
    if rng.randf() < 0.06:
        var a: Dictionary = C.ressources.autonomie(C.population, jour)
        var offre := {"produit": "sel", "quantite": 20.0, "prix": 260.0}
        if float(a.get("sel", 99.0)) > 120.0:
            offre = {"produit": "hache_fer", "quantite": 1.0, "prix": 30.0}
        _proposer("marchand", "Un marchand étranger accoste",
            "Venu d'au-delà de l'archipel, il propose %d %s contre %d kg de grain." % [int(offre["quantite"]), offre["produit"], int(offre["prix"])],
            ["Acheter", "Le renvoyer"], 7, jour, offre)
    # Un clan ami propose une alliance, contre une aide.
    for v in C.voisins:
        if v.vivant() and C.diplomatie.etat("joueur", v.id) == "amitié" and rng.randf() < 0.05:
            _proposer("alliance_" + v.id, "Le %s propose une alliance" % v.nom,
                "Il demande en gage 60 bois pour sceller l'alliance.", ["Accepter (60 bois)", "Refuser poliment"], 20, jour, {"clan": v.id})
            break

func choisir(C, index_decision: int, option: int) -> String:
    if index_decision < 0 or index_decision >= decisions.size():
        return "Décision inconnue."
    var d: Dictionary = decisions[index_decision]
    var r := _appliquer(C, d, option)
    if r == "":
        decisions.remove_at(index_decision)
    return r

func _appliquer(C, d: Dictionary, option: int) -> String:
    var jour: int = C.temps.jour_total
    var cle: String = d["cle"]
    if cle.begins_with("betes_"):
        var champ: Dictionary = C.agriculture.champ(int(d["donnees"]["champ"]))
        if option == 0:
            var gens := 0
            for h in C.population.habitants:
                if gens < 2 and C.population.age(h, jour) >= 14 and not h["metier"] in ["chef", "ancien"] and not occupes.has(int(h["id"])):
                    occupes[int(h["id"])] = jour + 10
                    gens += 1
            if gens < 2:
                return "Pas assez d'adultes disponibles pour veiller."
            evenement.emit("Les veilleurs ont protégé le champ : les bêtes sont reparties.")
        elif not champ.is_empty():
            champ["degats"] = minf(0.9, float(champ.get("degats", 0.0)) + 0.25)
            evenement.emit("Les bêtes ont ravagé une partie du champ %d." % int(d["donnees"]["champ"]))
    elif cle.begins_with("secheresse_"):
        if option == 0:
            C.ressources.ration = 0.8
            C.ressources.ration_jusqu = jour + 120
            C.pression.noter("conservation", 25.0)
            evenement.emit("Rationnement : le grain durera plus longtemps, mais le clan souffre.")
        elif option == 1:
            var gens := 0
            for h in C.population.habitants:
                if gens < 3 and C.population.age(h, jour) >= 14 and not h["metier"] in ["chef", "ancien"] and not occupes.has(int(h["id"])):
                    occupes[int(h["id"])] = jour + 20
                    gens += 1
            if gens < 3:
                return "Il faut 3 adultes disponibles."
            C.pression.noter("eau", 40.0)
            C.ressources.ajouter("eau", 300.0, "puits")
            evenement.emit("Les puiseurs creusent : un peu d'eau, et le clan cherche à maîtriser l'irrigation.")
        else:
            C.pression.noter("nourriture", 20.0)
            evenement.emit("Le clan attend la pluie en espérant que les réserves suffiront.")
    elif cle == "marchand":
        if option == 0:
            if C.ressources.total_aliments() < float(d["donnees"]["prix"]):
                return "Pas assez de grain pour payer."
            C.territoire._payer_nourriture(C.ressources, float(d["donnees"]["prix"]))
            C.ressources.ajouter(d["donnees"]["produit"], float(d["donnees"]["quantite"]), "importation")
            evenement.emit("Marché conclu avec le marchand étranger.")
    elif cle.begins_with("alliance_"):
        var autre = C.voisin(d["donnees"]["clan"])
        if autre == null:
            return ""
        if option == 0:
            if C.ressources.quantite("bois") < 60.0:
                return "Il faut 60 bois."
            C.ressources.retirer("bois", 60.0, "echange")
            autre.ressources.ajouter("bois", 60.0, "echange")
            C.diplomatie.signer_alliance("joueur", autre.id, jour)
            renommee += 5
            evenement.emit("Alliance scellée avec le %s." % autre.nom)
        else:
            C.diplomatie.noter("joueur", autre.id, "refus", -5.0, "alliance refusée", jour)
    return ""

# ---------- Rythme ----------

func jour_passe(C) -> void:
    var jour: int = C.temps.jour_total
    for h in C.population.habitants:
        if occupes.has(int(h["id"])):
            if jour > int(occupes[int(h["id"])]):
                occupes.erase(int(h["id"]))
            else:
                h["occupe"] = true
    # Sans réponse à temps : le clan subit la dernière option.
    for i in range(decisions.size() - 1, -1, -1):
        if jour > int(decisions[i]["fin"]):
            var d: Dictionary = decisions[i]
            decisions.remove_at(i)
            _appliquer(C, d, d["options"].size() - 1)
            evenement.emit("Faute de décision, le clan a subi : %s." % d["options"][-1])

func mois_passe(C) -> void:
    _verifier_epoque(C)
    _maj_defis(C)
    _situations(C)

func vers_dict() -> Dictionary:
    return {"epoque": epoque, "renommee": renommee, "defis": defis, "decisions": decisions, "occupes": occupes, "graine": rng.seed, "etat": rng.state}

func depuis_dict(d: Dictionary) -> void:
    epoque = int(d.get("epoque", 0))
    renommee = int(d.get("renommee", 0))
    defis = d.get("defis", [])
    decisions = d.get("decisions", [])
    occupes = {}
    for k in d.get("occupes", {}):
        occupes[int(k)] = int(d["occupes"][k])
    if d.has("graine"):
        rng.seed = int(d["graine"])
        rng.state = int(d["etat"])
