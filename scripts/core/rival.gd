extends RefCounted

# Le grand rival : BARRO FASO (v0.3.25).
# Le premier voyage d'exploration mène toujours à Wobé, l'île de BARRO FASO.
# BARRO FASO ne cherche JAMAIS à détruire ni à anéantir le joueur.
# Selon la relation, il aide un peu ou met des bâtons dans les roues.

signal evenement(texte)

const ID := "barro_faso"
const ILE := "wobe"

var defi_lance := -1
var derniere_epoque_joueur := 0
var rng := RandomNumberGenerator.new()

func _init() -> void:
    rng.seed = 7007

func connu(C) -> bool:
    return int(C.expeditions.connues.get(ILE, 0)) >= 1

func mois_passe(C) -> void:
    var b = C.voisin(ID)
    if b == null or not b.vivant() or not connu(C):
        return
    var jour: int = C.temps.jour_total
    var chef: String = b.nom_du_chef()
    # Défi perdu : BARRO FASO a atteint l'époque visée avant nous.
    if defi_lance >= 0 and b.epoque >= defi_lance and C.defis.epoque < defi_lance:
        evenement.emit("%s a gagné son défi : il entre le premier dans l'époque %s." % [chef, C.defis.EPOQUES[defi_lance]])
        defi_lance = -1
    # La course aux époques.
    if C.defis.epoque > derniere_epoque_joueur:
        derniere_epoque_joueur = C.defis.epoque
        if b.epoque < C.defis.epoque:
            C.defis.renommee += 10
            evenement.emit("Nous avons devancé BARRO FASO : %s le reconnaît à contrecœur (renommée +10) !" % chef)
            if defi_lance == C.defis.epoque:
                C.defis.renommee += 10
                C.diplomatie.noter("joueur", ID, "defi", 4.0, "défi relevé", jour)
                evenement.emit("Défi gagné contre %s : il salue notre clan (renommée +10)." % chef)
            defi_lance = -1
    if rng.randf() > 0.25:
        return
    var etat: String = C.diplomatie.etat("joueur", ID)
    if etat in ["amitié", "alliance"]:
        _aider(C, b, chef, jour)
    elif etat == "neutralité":
        if defi_lance < 0 and C.defis.epoque < C.defis.EPOQUES.size() - 2:
            defi_lance = C.defis.epoque + 1
            evenement.emit("%s nous défie : « Mon clan atteindra l'époque %s avant le vôtre ! »" % [chef, C.defis.EPOQUES[defi_lance]])
    else:
        _gener(C, b, chef, jour)

func _aider(C, b, chef: String, jour: int) -> void:
    match rng.randi() % 3:
        0:
            if b.ressources.total_aliments() > 400.0:
                b.expeditions_vivres(40.0)
                C.ressources.ajouter("mil", 40.0, "don")
                evenement.emit("%s nous envoie 40 kg de mil en signe d'amitié." % chef)
        1:
            for t in b.decouvertes.connues:
                if not C.decouvertes.connait(t):
                    C.decouvertes.observer(t, 1.0)
                    evenement.emit("%s partage ce qu'il sait : %s (expérience facilitée)." % [chef, b.decouvertes.definitions[t]["nom"]])
                    break
        _:
            evenement.emit("%s nous conseille : « Gardez toujours 90 jours de grain avant la saison sèche. »" % chef)

func _gener(C, b, chef: String, jour: int) -> void:
    match rng.randi() % 3:
        0:
            for bt in C.flotte.bateaux:
                if int(bt["occupe_jusqu"]) >= jour:
                    bt["occupe_jusqu"] = int(bt["occupe_jusqu"]) + 5
                    if not C.expeditions.en_cours.is_empty():
                        C.expeditions.en_cours["retour"] = int(C.expeditions.en_cours["retour"]) + 5
                    evenement.emit("Les pirogues de %s ont gêné notre bateau en mer : 5 jours de retard." % chef)
                    return
            evenement.emit("%s se moque de notre petite flotte." % chef)
        1:
            var autres: Array = C.voisins.filter(func(v): return v.vivant() and v.id != ID)
            if not autres.is_empty():
                var v = autres[rng.randi() % autres.size()]
                C.diplomatie.noter("joueur", v.id, "rumeur", -4.0, "rumeur de BARRO FASO", jour)
                evenement.emit("%s répand des rumeurs sur nous auprès du %s (relation -4)." % [chef, v.nom])
        _:
            C.diplomatie.noter("joueur", ID, "provocation", -2.0, "provocation", jour)
            evenement.emit("%s nous provoque : « Votre clan ne sera jamais qu'un campement. »" % chef)

func vers_dict() -> Dictionary:
    return {"defi": defi_lance, "epoque_joueur": derniere_epoque_joueur, "graine": rng.seed, "etat": rng.state}

func depuis_dict(d: Dictionary) -> void:
    defi_lance = int(d.get("defi", -1))
    derniere_epoque_joueur = int(d.get("epoque_joueur", 0))
    if d.has("graine"):
        rng.seed = int(d["graine"])
        rng.state = int(d["etat"])
