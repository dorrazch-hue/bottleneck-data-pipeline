# BottleNeck — Automatisation du pipeline de données

Automatisation, avec [Kestra](https://kestra.io), de la chaîne de nettoyage, jointure, calcul de chiffre d'affaires et détection des vins premium pour BottleNeck, marchand de vin.

## Contenu du dépôt

```
.
├── docker-compose.yml          # Installation de Kestra + PostgreSQL
├── .env.example                 # Modèle des variables d'environnement (à copier en .env)
├── bottleneck_pipeline.yaml     # Le workflow Kestra complet (à importer)
├── logigramme_bottleneck.drawio # Diagramme de flux du pipeline (à ouvrir sur app.diagrams.net)
├── journal_de_bord.md           # Journal détaillé du développement (choix techniques, bugs rencontrés, solutions)
└── scripts/
    ├── nettoyage_erp.sql
    ├── nettoyage_web.sql
    ├── nettoyage_liaison.sql
    ├── test_erp.sql
    ├── test_web.sql
    ├── test_liaison.sql
    ├── jointure.sql
    ├── test_jointure.sql
    ├── calcul_ca.sql
    ├── test_ca.sql
    ├── zscore_vins.py
    ├── test_zscore.sql
    └── extraction_rapport_ca.sql
```

## 1. Prérequis

- [Docker](https://www.docker.com/) et Docker Compose installés et lancés

## 2. Lancer Kestra

```bash
git clone https://github.com/dorrazch-hue/bottleneck-data-pipeline.git
cd bottleneck-data-pipeline
cp .env.example .env
```

Ouvrez `.env` et remplacez les valeurs par les vôtres (mot de passe PostgreSQL, email/mot de passe de connexion à Kestra).

```bash
docker compose up -d
docker compose ps   # vérifier que les 2 conteneurs sont "Up"
```

Ouvrez ensuite [http://localhost:8080](http://localhost:8080). Au premier lancement, Kestra vous demande de créer un compte : utilisez les mêmes identifiants que ceux mis dans `.env`.

## 3. Déposer les fichiers sources

Les 3 fichiers bruts fournis par l'ERP et le CMS (`erp.xlsx`, `web.xlsx`, `liaison.xlsx`) ne sont **pas** dans ce dépôt (données de l'entreprise). Pour les déposer :

1. Dans Kestra : **Namespaces** → créez/ouvrez le namespace **`bottleneck`**
2. Onglet **Namespace Files**
3. **Import** → sélectionnez vos 3 fichiers `erp.xlsx`, `web.xlsx`, `liaison.xlsx` (à la racine, pas dans un sous-dossier)
4. Créez un sous-dossier **`scripts`**, et importez-y tous les fichiers du dossier `scripts/` de ce dépôt

Chaque mois, il suffit de remplacer ces 3 fichiers par les nouveaux exports pour que le pipeline traite les données à jour.

## 4. Importer le workflow

1. Dans Kestra : **Flows** → **Create**
2. Effacez le contenu par défaut, collez le contenu de `bottleneck_pipeline.yaml`
3. **Save**

## 5. Lancer le pipeline

- **Manuellement** : bouton **Execute** sur la page du flow
- **Automatiquement** : le trigger `declenchement_mensuel` déclenche une exécution tous les 15 du mois à 9h — rien à faire, Kestra s'en charge tant qu'il tourne

## 6. Récupérer les résultats

Une fois l'exécution terminée (statut vert), allez dans l'onglet **Outputs** de l'exécution :

| Fichier | Contenu |
|---|---|
| `rapport_ca_bottleneck.xlsx` | Chiffre d'affaires par produit + chiffre d'affaires total |
| `vins_premium.csv` | Vins avec z-score > 2 |
| `vins_ordinaires.csv` | Les autres vins |

## Architecture technique (résumé)

- **Nettoyage** (erp / web / liaison) en parallèle, chacun suivi d'un test de qualité
- **Jointure** des 3 fichiers nettoyés, puis test de cohérence
- **Calcul du CA** par produit et total, puis test
- **Détection z-score** (script Python) des vins premium/ordinaires, puis test
- **Extraction finale** du rapport CA en XLSX
- Chaque tâche dispose d'un **retry automatique** (3 tentatives) en cas d'indisponibilité passagère d'un service
- En cas d'échec définitif, un **handler d'erreur** (`errors:`) journalise une alerte
- Un **Switch** final vérifie la complétion du pipeline

Le détail des choix techniques et des difficultés rencontrées (et comment elles ont été résolues) est documenté dans [`journal_de_bord.md`](./journal_de_bord.md).
