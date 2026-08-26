"""
Comptage des vins premium détectés, exposé comme sortie Kestra simple
et fiable, pour servir de condition robuste au Switch qui route ensuite
vers les bonnes extractions.
"""

import json

with open("/app/vins_premium.csv", encoding="utf-8") as f:
    nb_premium = sum(1 for _ in f) - 1  # moins la ligne d'en-tête

sortie = json.dumps({"outputs": {"nb_premium": nb_premium}})
print("::" + sortie + "::")
print("Nombre de vins premium comptés :", nb_premium)
