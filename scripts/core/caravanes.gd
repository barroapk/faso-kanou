extends RefCounted

# Bateaux entre les îles (v0.3.15 B, archipel en v0.3.16 A2).
# Chaque clan vit sur son île : toute marchandise traverse la mer.
# Au départ, la marchandise du vendeur ET le paiement de l'acheteur sont
# retirés des stocks (motif « transport ») : ils sont réservés, personne ne
# peut les vendre une deuxième fois pendant le trajet.
# Pendant le trajet, un incident peut faire perdre une partie de la marchandise.
# À l'arrivée : l'acheteur reçoit ce qui reste, le vendeur est payé pour ce qui
# est arrivé, le reste du paiement retourne à l'acheteur.
# La perte est inscrite dans les deux comptabilités, avec le même numéro.

signal evenement(texte)

const VITESSE := 40.0           # km par jour (grande pirogue à voile et rames)
const DUREE_MIN := 1            # jours
const RISQUE_BASE := 0.05       # chance d'incident par traversée (tempête, chavirement)
const RISQUE_JOUR := 0.01       # + par jour en mer
const PERTE_MIN := 0.1          # part perdue lors d'un incident
const PERTE_MAX := 0.4
# Un clan ami ou allié offre escales et escortes : moins de pertes (jamais zéro).
# Les tempêtes ne dépendent pas de la diplomatie.
const RISQUE_RELATION := {"amitié": 0.8, "alliance": 0.65}

var en_route: Array = []
var rng := RandomNumberGenerator.new()

func _init() -> void:
    rng.seed = 9090

func duree(terr_a: Dictionary, terr_b: Dictionary) -> int:
    var dx := float(terr_a.get("x", 0.0)) - float(terr_b.get("x", 0.0))
    var dz := float(terr_a.get("z", 0.0)) - float(terr_b.get("z", 0.0))
    return maxi(DUREE_MIN, int(ceil(sqrt(dx * dx + dz * dz) / VITESSE)))

# Position de l'île du clan sur la carte de l'archipel (km).
func territoire(c) -> Dictionary:
    return c.agriculture.ile.get("carte", {"x": 0.0, "z": 0.0})

# Lance la caravane à partir d'un devis du marché. Renvoie "" si elle part.
func envoyer(a, id_a: String, b, id_b: String, d: Dictionary, jour: int, num: String) -> String:
    var produit: String = d["produit"]
    var q: float = d["quantite"]
    var p: String = d["paiement"].keys()[0]
    var qp: float = d["paiement"][p]
    if b.ressources.quantite(produit) + 0.000001 < q:
        return "Le vendeur n'a plus assez de %s." % produit
    if a.ressources.quantite(p) + 0.000001 < qp:
        return "L'acheteur n'a plus assez de %s." % p
    # Un bateau du vendeur (sinon de l'acheteur) fait l'aller-retour.
    var dist := Vector2(float(territoire(a)["x"]) - float(territoire(b)["x"]), float(territoire(a)["z"]) - float(territoire(b)["z"])).length()
    var bateau := {}
    for cl in [b, a]:
        var f = cl.get("flotte")
        if f == null or not bateau.is_empty():
            continue
        var v: float = f.vitesse_libre(jour, 2, q)
        if v > 0.0:
            var j := maxi(DUREE_MIN, int(ceil(dist / v)))
            bateau = f.reserver(jour, jour + 2 * j, 2, q, "commerce")
    if bateau.is_empty() and (a.get("flotte") != null or b.get("flotte") != null):
        return "Aucun bateau libre assez grand pour %d kg (ni chez le vendeur, ni chez l'acheteur)." % int(q)
    b.ressources.retirer(produit, q, "transport")
    a.ressources.retirer(p, qp, "transport")
    var jours := maxi(DUREE_MIN, int(ceil(dist / float(load("res://scripts/core/flotte.gd").TYPES[bateau.get("type", "pirogue")]["km_jour"]))))
    en_route.append({
        "id": num, "acheteur": id_a, "vendeur": id_b,
        "produit": produit, "quantite": q, "paiement": p, "prix": qp,
        "depart": jour, "arrivee": jour + jours,
        "risque": (RISQUE_BASE + RISQUE_JOUR * jours) * float(RISQUE_RELATION.get(d.get("etat", ""), 1.0)),
    })
    evenement.emit("Bateau %s : %.1f %s part de %s vers %s (%d jours de mer)." % [num, q, produit, id_b, id_a, jours])
    return ""

# trouver : Callable(id) -> clan. Appelé chaque jour.
func jour_passe(trouver: Callable, jour: int) -> void:
    var restants: Array = []
    for c in en_route:
        if jour < int(c["arrivee"]):
            restants.append(c)
            continue
        _arriver(c, trouver, jour)
    en_route = restants

func _arriver(c: Dictionary, trouver: Callable, jour: int) -> void:
    var a = trouver.call(c["acheteur"])
    var b = trouver.call(c["vendeur"])
    var q: float = c["quantite"]
    var perte := 0.0
    if rng.randf() < float(c["risque"]):
        perte = q * rng.randf_range(PERTE_MIN, PERTE_MAX)
    var arrive := q - perte
    var paye: float = float(c["prix"]) * arrive / q
    var rendu: float = float(c["prix"]) - paye
    # Un clan disparu : la marchandise ou le paiement retourne à l'autre.
    if a == null or a.population.habitants.is_empty():
        if b != null:
            b.ressources.ajouter(c["produit"], arrive, "transport")
        return
    if b == null or b.population.habitants.is_empty():
        a.ressources.ajouter(c["paiement"], float(c["prix"]), "transport")
        return
    a.ressources.ajouter(c["produit"], arrive, "echange")
    b.ressources.ajouter(c["paiement"], paye, "echange")
    if rendu > 0.0:
        a.ressources.ajouter(c["paiement"], rendu, "transport")
    var t := {"id": c["id"], "jour": jour, "a_donne": {c["paiement"]: paye},
        "b_donne": {c["produit"]: arrive}, "perte": {c["produit"]: perte}, "depart": c["depart"]}
    a.economie.transactions.append(t)
    b.economie.transactions.append(t.duplicate(true))
    if perte > 0.0:
        # Une perte en mer pousse les deux clans à mieux naviguer.
        for cl in [a, b]:
            if cl.get("pression") != null:
                cl.pression.noter("navigation", 100.0 * perte / q)
        evenement.emit("Bateau %s : tempête en mer, %.1f %s perdus. %s paie seulement ce qui est arrivé." % [c["id"], perte, c["produit"], c["acheteur"]])
    else:
        evenement.emit("Bateau %s arrivé : %.1f %s livrés à %s." % [c["id"], arrive, c["produit"], c["acheteur"]])

# Quantité en route, pour qu'un clan ne relance pas le même achat.
func en_attente(id_clan: String, produit: String) -> float:
    var q := 0.0
    for c in en_route:
        if c["acheteur"] == id_clan and c["produit"] == produit:
            q += float(c["quantite"])
    return q

func vers_dict() -> Dictionary:
    return {"en_route": en_route, "graine": rng.seed, "etat": rng.state}

func depuis_dict(d: Dictionary) -> void:
    en_route = d.get("en_route", [])
    if d.has("graine"):
        rng.seed = int(d["graine"])
        rng.state = int(d["etat"])
