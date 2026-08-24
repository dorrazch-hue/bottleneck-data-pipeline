-- ============================================================
-- Test de erp_clean (DuckDB)
-- Vérifie : absence de doublons + absence de valeurs manquantes
-- Fait échouer la tâche (via error()) si un contrôle échoue,
-- ce qui permet à Kestra de router vers le chemin d'erreur (KO)
-- ============================================================

CREATE OR REPLACE TABLE erp_clean AS SELECT * FROM read_csv_auto('erp_clean.csv');

SELECT CASE
    WHEN (SELECT COUNT(*) FROM erp_clean) != (SELECT COUNT(DISTINCT product_id) FROM erp_clean)
        THEN error('Test échoué : doublons détectés sur product_id dans erp_clean')
    WHEN (SELECT COUNT(*) FROM erp_clean WHERE product_id IS NULL OR price IS NULL OR stock_quantity IS NULL OR stock_status IS NULL) > 0
        THEN error('Test échoué : valeurs manquantes détectées dans erp_clean')
    ELSE 'Test réussi : erp_clean ne contient ni doublon ni valeur manquante'
END AS resultat_test;
