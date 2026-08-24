-- ============================================================
-- Test de liaison_clean (DuckDB)
-- Vérifie : absence de doublons + absence de valeurs manquantes sur product_id
-- Fait échouer la tâche (via error()) si un contrôle échoue
-- ============================================================

CREATE OR REPLACE TABLE liaison_clean AS SELECT * FROM read_csv_auto('liaison_clean.csv');

SELECT CASE
    WHEN (SELECT COUNT(*) FROM liaison_clean) != (SELECT COUNT(DISTINCT product_id) FROM liaison_clean)
        THEN error('Test échoué : doublons détectés sur product_id dans liaison_clean')
    WHEN (SELECT COUNT(*) FROM liaison_clean WHERE product_id IS NULL) > 0
        THEN error('Test échoué : valeurs manquantes détectées sur product_id dans liaison_clean')
    ELSE 'Test réussi : liaison_clean ne contient ni doublon ni valeur manquante sur product_id'
END AS resultat_test;
