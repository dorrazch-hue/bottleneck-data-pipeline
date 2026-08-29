"""
Détection des vins premium (millésimes) et ordinaires par z-score
Sur les données fusionnées (fusion.csv)

z-score = (prix du vin - moyenne des prix) / (écart-type des prix)
Un vin est considéré "premium" si son z-score > 2

Version sans dépendance externe (uniquement la bibliothèque standard
Python : csv, statistics, os).
"""

import csv
import statistics
import os

# Découverte importante : les tâches SQL DuckDB de Kestra tournent toutes
# dans le même processus Java et partagent donc son dossier courant /app
# pour les chemins relatifs -- contrairement aux tâches Python (Process
# runner), qui ont leur propre dossier temporaire séparé. C'est là que
# jointure.sql écrit réellement fusion.csv.
CANDIDATS = ["/app/fusion.csv", "fusion.csv"]
fusion_path = next((p for p in CANDIDATS if os.path.exists(p)), None)
if fusion_path is None:
    raise FileNotFoundError(f"fusion.csv introuvable. Emplacements testés : {CANDIDATS}")

working_dir = os.path.dirname(fusion_path) or "."

# Chargement des données fusionnées (produites par jointure.sql)
with open(fusion_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

# Calcul du z-score sur la colonne price
prices = [float(r["price"]) for r in rows]
moyenne_prix = statistics.mean(prices)
ecart_type_prix = statistics.stdev(prices)  # écart-type échantillon (comme pandas .std() par défaut)

for r in rows:
    z = (float(r["price"]) - moyenne_prix) / ecart_type_prix
    r["z_score"] = z
    r["categorie"] = "premium" if z > 999 else "ordinaire"

# Séparation en 2 jeux de données, triés par z-score décroissant
vins_premium = sorted([r for r in rows if r["categorie"] == "premium"], key=lambda r: r["z_score"], reverse=True)
vins_ordinaires = sorted([r for r in rows if r["categorie"] == "ordinaire"], key=lambda r: r["z_score"], reverse=True)

fieldnames = list(rows[0].keys())

# Export des 2 extractions finales, dans le même dossier que fusion.csv
# (/app), pour que test_zscore (une tâche SQL DuckDB) les retrouve
with open(os.path.join(working_dir, "vins_premium.csv"), "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(vins_premium)

with open(os.path.join(working_dir, "vins_ordinaires.csv"), "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(vins_ordinaires)

# Vérification (utile pour le test de cohérence du z-score qui suivra cette tâche)
print(f"fusion.csv trouvé ici : {fusion_path}")
print(f"Nombre total de produits analysés : {len(rows)}")
print(f"Moyenne des prix : {moyenne_prix:.2f} €")
print(f"Écart-type des prix : {ecart_type_prix:.2f} €")
print(f"Nombre de vins premium (z-score > 2) : {len(vins_premium)}")
print(f"Nombre de vins ordinaires : {len(vins_ordinaires)}")
