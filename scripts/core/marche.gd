extends RefCounted

# Marché entre clans (v0.3.15 A).
# Le marché CALCULE les prix et VÉRIFIE les échanges. Il ne crée jamais ni
# ressource ni monnaie : tout ce qui est reçu a été retiré des stocks de l'autre.
#
# Prix de référence : la valeur du catalogue, en kg de mil.
# Prix local d'un clan : référence × facteur de rareté.
#   facteur = racine(jours visés / jours de réserve), borné entre 0,5 et 3.
#   Beaucoup de réserve -> prix bas (offre). Peu de réserve -> prix haut (demande).
# Un échange se fait si l'acheteur estime le produit au moins autant que le
# vendeur ; le prix est alors la moyenne des deux estimations.
# Réserves protégées : un clan ne vend jamais sous ses jours visés.

signal evenement(texte)

const ECONOMIE = preload("res://scripts/core/economie.gd")

const JOURS_VISES := {"nourriture": 90.0, "eau": 30.0, "bois": 30.0, "sel": 60.0}
const FACTEUR_MIN := 0.5
const FACTEUR_MAX := 3.0
const SEUIL_ACHAT := 30.0      # l'ordinateur achète sous 30 jours de réserve
const MONNAIE := "or_alluvionnaire"

var valeurs := {}              # prix de référence (kg de mil)
var compteur := 0              # numéro des transactions
var caravanes = null           # si présent, la marchandise voyage (v0.3.15 B)
# Prix de l'archipel (v0.3.32c) : chaque clan ne voit que les clans qu'il connaît.
# connus[id d'instance du clan] = [clans connus, lui compris]. Recalculé chaque mois.
var connus := {}

func _init() -> void:
    valeurs = ECONOMIE.new().valeurs

# ---------- Outils ----------

# Ressource vitale suivie pour ce produit (un aliment compte comme « nourriture »).
func _vitale(c, id: String) -> String:
    if JOURS_VISES.has(id):
        return id
    if c.ressources._lieu(id) == "aliments":
        return "nourriture"
    return ""

func _jours(c, v: String, jour: int) -> float:
    return float(c.ressources.autonomie(c.population, jour).get(v, 9999.0))

func valeur_ref(id: String) -> float:
    return float(valeurs.get(id, 0.0))

func facteur(c, id: String, jour: int) -> float:
    var v := _vitale(c, id)
    if v == "":
        return 1.0
    var j := _jours(c, v, jour)
    var local := FACTEUR_MAX if j <= 0.0 else clampf(sqrt(float(JOURS_VISES[v]) / j), FACTEUR_MIN, FACTEUR_MAX)
    # Prix = moyenne (géométrique) de la rareté chez soi et dans l'archipel connu.
    return sqrt(local * facteur_archipel(c, v, jour))
# Rareté dans l'archipel connu du clan : réserves totales / consommation totale
# (pondéré par la consommation : un produit peu consommé ne paraît pas rare).
# Ce n'est jamais stocké : recalculé à chaque devis.
func facteur_archipel(c, v: String, jour: int) -> float:
    if not v in ["nourriture", "eau", "bois"]:
        return 1.0
    var stock := 0.0
    var conso := 0.0
    for k in connus.get(c.get_instance_id(), [c]):
        if k.population.habitants.is_empty():
            continue
        var cj: float = k.ressources._conso_jour(k.population, jour, v)
        stock += _jours(k, v, jour) * cj
        conso += cj
    if conso <= 0.0:
        return 1.0
    if stock <= 0.0:
        return FACTEUR_MAX
    return clampf(sqrt(float(JOURS_VISES[v]) / (stock / conso)), FACTEUR_MIN, FACTEUR_MAX)

func prix_local(c, id: String, jour: int) -> float:
    return valeur_ref(id) * facteur(c, id, jour)

# Quantité qu'un clan peut céder sans toucher à sa réserve vitale.
func disponible(c, id: String, jour: int) -> float:
    var q: float = c.ressources.quantite(id)
    var v := _vitale(c, id)
    if v == "":
        return q
    var j := _jours(c, v, jour)
    if j <= float(JOURS_VISES[v]):
        return 0.0
    return q * (1.0 - float(JOURS_VISES[v]) / j)

# Place libre chez l'acheteur (eau, bois, sel ont une capacité de stockage).
func place(c, id: String) -> float:
    if c.ressources._lieu(id) == "stocks":
        return maxf(0.0, c.ressources.capacite(id) - c.ressources.quantite(id))
    return 1.0e12

# ---------- Devis ----------

# a = acheteur, b = vendeur (objets clan : population, ressources, economie).
# paiement = "cauris" ou un produit de troc ; "" = choisir automatiquement.
# Diplomatie et commerce (v0.3.32) : frais selon la relation, retenus sur le
# vendeur (rien ne disparaît). Hostilité : commerce ordinaire interdit.
const FRAIS := {"rivalité": 0.10, "neutralité": 0.05, "amitié": 0.03, "alliance": 0.01}
func devis(a, b, id: String, q: float, jour: int, paiement := "", etat := "neutralité", remise := 0.0) -> Dictionary:
    var d := {"possible": false, "raison": "", "produit": id, "quantite": q, "paiement": {}, "etat": etat}
    if etat == "hostilité":
        d["raison"] = "Commerce impossible : nos relations avec ce clan sont hostiles."
        return d
    if valeur_ref(id) <= 0.0:
        d["raison"] = "Ce produit n'a pas de valeur connue."
        return d
    q = minf(q, minf(disponible(b, id, jour), place(a, id)))
    if q <= 0.001:
        d["raison"] = "Le vendeur ne peut rien céder sans mettre ses réserves en danger."
        return d
    var p_vendeur := prix_local(b, id, jour)
    var p_acheteur := prix_local(a, id, jour)
    if p_acheteur < p_vendeur:
        d["raison"] = "Le vendeur en veut %.2f kg de mil, l'acheteur n'en offre que %.2f." % [p_vendeur, p_acheteur]
        return d
    # Les frais (selon la relation) sont retenus sur ce que reçoit le vendeur,
    # au profit de l'acheteur qui l'accueille au port : rien ne disparaît (v0.3.32c).
    var frais := maxf(0.01, float(FRAIS.get(etat, 0.05)) - remise)   # plancher 1 % (v0.3.32d)
    var pu := (p_vendeur + p_acheteur) / 2.0 * (1.0 - frais)
    if paiement == "":
        paiement = _choisir_paiement(a, b, id, jour)
    if paiement == "" or paiement == id:
        d["raison"] = "L'acheteur n'a rien à offrir en échange."
        return d
    # Valeur du paiement : moyenne des deux estimations (comme pour le produit).
    var pp := (prix_local(a, paiement, jour) + prix_local(b, paiement, jour)) / 2.0
    if pp <= 0.0:
        d["raison"] = "Ce moyen de paiement n'a pas de valeur."
        return d
    var dispo_paie := disponible(a, paiement, jour)
    var place_paie := place(b, paiement)
    # On réduit la quantité si l'acheteur ne peut pas tout payer.
    var q_max := minf(dispo_paie, place_paie) * pp / pu
    q = minf(q, q_max)
    if q <= 0.001:
        d["raison"] = "L'acheteur ne peut pas payer."
        return d
    d["possible"] = true
    d["quantite"] = q
    d["prix_unitaire"] = pu
    d["total"] = q * pu
    d["paiement"] = {paiement: q * pu / pp}
    return d

# Monnaie si possible, sinon le produit que l'acheteur a le plus en trop
# (en valeur), qui ne soit pas vital pour lui.
func _choisir_paiement(a, b, id: String, jour: int) -> String:
    if disponible(a, MONNAIE, jour) > 0.0:
        return MONNAIE
    var meilleur := ""
    var v_max := 0.0
    for p in _produits(a):
        if p == id or valeur_ref(p) <= 0.0 or _vitale(a, p) != "":
            continue
        var v := disponible(a, p, jour) * valeur_ref(p)
        if v > v_max and place(b, p) > 0.0:
            v_max = v
            meilleur = p
    return meilleur

func _produits(c) -> Array:
    var l: Array = []
    for k in c.ressources.objets:
        l.append(k)
    for k in c.ressources.aliments:
        l.append(k)
    for k in ["bois", "sel"]:
        l.append(k)
    return l

# ---------- Conclure ----------

# Fait l'échange (retire chez l'un, ajoute chez l'autre) et l'inscrit dans les
# deux comptabilités avec le même numéro. Renvoie "" si c'est fait.
func conclure(a, id_a: String, b, id_b: String, d: Dictionary, jour: int, diplomatie = null) -> String:
    if not d.get("possible", false):
        return d.get("raison", "Échange impossible.")
    if diplomatie != null and diplomatie.etat(id_a, id_b) == "hostilité":
        return "Commerce impossible : nos relations avec ce clan sont hostiles."
    compteur += 1
    var num := "T%d-%d" % [jour, compteur]
    var err := ""
    if caravanes != null:
        err = caravanes.envoyer(a, id_a, b, id_b, d, jour, num)
    else:
        err = ECONOMIE.echanger(a.economie, a.ressources, b.economie, b.ressources, d["paiement"], {d["produit"]: d["quantite"]}, jour, num)
    if err != "":
        compteur -= 1
        return err
    var p: String = d["paiement"].keys()[0]
    var texte := "%s achète %.1f %s à %s contre %.1f %s." % [id_a, d["quantite"], d["produit"], id_b, d["paiement"][p], p]
    if diplomatie != null:
        diplomatie.noter(id_a, id_b, "echange", 2.0, texte, jour)
    evenement.emit(texte)
    return ""

# ---------- L'ordinateur achète ce qui lui manque ----------

# clans : Array de [id, objet]. Un clan de l'ordinateur sous 30 jours de
# nourriture, d'eau ou de bois essaie d'acheter chez les autres.
func mois_passe(clans: Array, ids_ordinateur: Array, jour: int, diplomatie) -> void:
    for ca in clans:
        if not ids_ordinateur.has(ca[0]) or ca[1].population.habitants.is_empty():
            continue
        for v in ["eau", "nourriture", "bois"]:
            var j := _jours(ca[1], v, jour)
            if j >= SEUIL_ACHAT:
                continue
            for cb in clans:
                if cb[0] == ca[0] or not ids_ordinateur.has(cb[0]) or cb[1].population.habitants.is_empty():
                    continue
                if diplomatie != null and diplomatie.etat(ca[0], cb[0]) == "hostilité":
                    continue
                var id: String = v if v != "nourriture" else _aliment_a_vendre(cb[1], jour)
                if id == "":
                    continue
                var conso: float = ca[1].ressources._conso_jour(ca[1].population, jour, v)
                var q := conso * (SEUIL_ACHAT - j)
                if caravanes != null:
                    q -= caravanes.en_attente(ca[0], id)
                if q <= 0.0:
                    break
                var d := devis(ca[1], cb[1], id, q, jour, "", diplomatie.etat(ca[0], cb[0]) if diplomatie != null else "neutralité")
                if conclure(ca[1], ca[0], cb[1], cb[0], d, jour, diplomatie) == "":
                    break

func _aliment_a_vendre(c, jour: int) -> String:
    var meilleur := ""
    var q_max := 0.0
    for a in c.ressources.aliments:
        var q := disponible(c, a, jour)
        if q > q_max:
            q_max = q
            meilleur = a
    return meilleur

# ---------- Sauvegarde ----------

func vers_dict() -> Dictionary:
    return {"compteur": compteur}

func depuis_dict(d: Dictionary) -> void:
    compteur = int(d.get("compteur", 0))
