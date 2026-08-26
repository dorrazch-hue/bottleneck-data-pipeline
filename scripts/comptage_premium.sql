-- ============================================================
-- Comptage des vins premium détectés
-- Cette tâche réussit s'il y a au moins 1 vin premium, et échoue
-- volontairement (via error()) si aucun n'est détecté. Le Switch
-- qui suit se base sur l'état (réussite/échec) de cette tâche
-- pour router vers les bonnes extractions -- mécanisme identique
-- à celui déjà utilisé et validé pour tous les tests du pipeline.
-- ============================================================

CREATE OR REPLACE TABLE vins_premium AS SELECT * FROM read_csv_auto('vins_premium.csv');

SELECT
    CASE
        WHEN COUNT(*) = 0 THEN error('Aucun vin premium détecté ce mois-ci')
        ELSE COUNT(*)
    END AS nb_premium
FROM vins_premium;
