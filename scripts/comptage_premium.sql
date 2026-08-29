-- ============================================================
-- Comptage des vins premium détectés (purement informatif)
-- Cette tâche réussit TOUJOURS, y compris quand il n'y a aucun
-- vin premium (renvoie 0). La décision de brancher (Switch) est
-- déléguée à la tâche verification_premium_existe qui suit.
-- ============================================================

CREATE OR REPLACE TABLE vins_premium AS SELECT * FROM read_csv_auto('vins_premium.csv');

SELECT COUNT(*) AS nb_premium FROM vins_premium;
