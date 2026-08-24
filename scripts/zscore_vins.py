"""
Détection des vins premium (millésimes) et ordinaires par z-score
Sur les données fusionnées (fusion.csv, 714 lignes)

z-score = (prix du vin - moyenne des prix) / (écart-type des prix)
Un vin est considéré "premium" si son z-score > 2
"""

import os
import pandas as pd

# Se positionner dans le dossier de travail partagé de Kestra si on tourne
# dans un conteneur séparé (WORKING_DIR n'existe que dans ce cas précis)
if "WORKING_DIR" in os.environ:
    os.chdir(os.environ["WORKING_DIR"])

# Chargement des données fusionnées (produites par jointure.sql)
df = pd.read_csv("fusion.csv")

# Calcul du z-score sur la colonne price
moyenne_prix = df["price"].mean()
ecart_type_prix = df["price"].std()  # écart-type échantillon (ddof=1, défaut pandas)

df["z_score"] = (df["price"] - moyenne_prix) / ecart_type_prix

# Classification : premium si z-score > 2, sinon ordinaire
df["categorie"] = df["z_score"].apply(lambda z: "premium" if z > 2 else "ordinaire")

# Séparation en 2 jeux de données
vins_premium = df[df["categorie"] == "premium"].sort_values("z_score", ascending=False)
vins_ordinaires = df[df["categorie"] == "ordinaire"].sort_values("z_score", ascending=False)

# Export des 2 extractions finales
vins_premium.to_csv("vins_premium.csv", index=False)
vins_ordinaires.to_csv("vins_ordinaires.csv", index=False)

# Vérification (utile pour le test de cohérence du z-score qui suivra cette tâche)
print(f"Nombre total de produits analysés : {len(df)}")
print(f"Moyenne des prix : {moyenne_prix:.2f} €")
print(f"Écart-type des prix : {ecart_type_prix:.2f} €")
print(f"Nombre de vins premium (z-score > 2) : {len(vins_premium)}")
print(f"Nombre de vins ordinaires : {len(vins_ordinaires)}")
