-- ============================================================
-- Test de web_clean (DuckDB)
-- Vérifie : absence de doublons + absence de valeurs manquantes sur sku
-- Fait échouer la tâche (via error()) si un contrôle échoue
-- ============================================================

CREATE OR REPLACE TABLE web_clean AS SELECT * FROM read_csv_auto('web_clean.csv');

SELECT CASE
    WHEN (SELECT COUNT(*) FROM web_clean) != (SELECT COUNT(DISTINCT sku) FROM web_clean)
        THEN error('Test échoué : doublons détectés sur sku dans web_clean')
    WHEN (SELECT COUNT(*) FROM web_clean WHERE sku IS NULL) > 0
        THEN error('Test échoué : valeurs manquantes détectées sur sku dans web_clean')
    WHEN (SELECT COUNT(*) FROM web_clean WHERE total_sales IS NULL) > 0
        THEN error('Test échoué : total_sales non convertible en nombre pour au moins une ligne')
    ELSE 'Test réussi : web_clean ne contient ni doublon ni valeur manquante sur sku, total_sales valide'
END AS resultat_test;
