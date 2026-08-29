-- ============================================================
-- Vérifie s'il existe au moins un vin premium ce mois-ci.
-- Réussit s'il y en a au moins un ; échoue volontairement sinon
-- (allowFailure: true dans le YAML pour ne pas arrêter le pipeline).
-- C'est l'ÉTAT (succès/échec) de cette tâche, pas une valeur,
-- que le Switch qui suit utilise pour choisir sa branche --
-- mécanisme déjà validé ailleurs dans ce pipeline.
-- ============================================================

CREATE OR REPLACE TABLE vins_premium AS SELECT * FROM read_csv_auto('vins_premium.csv');

SELECT
    CASE
        WHEN COUNT(*) = 0 THEN error('Aucun vin premium détecté ce mois-ci')
        ELSE COUNT(*)
    END AS nb_premium
FROM vins_premium;
