-- ============================================================
-- Test de la jointure (fusion) (DuckDB)
-- Vérifie : la jointure produit des résultats, sans doublon (fan-out),
-- et correspond exactement au nombre de lignes de web_clean (source pilote)
-- ============================================================

CREATE OR REPLACE TABLE fusion AS SELECT * FROM read_csv_auto('fusion.csv');
CREATE OR REPLACE TABLE web_clean AS SELECT * FROM read_csv_auto('web_clean.csv');

SELECT CASE
    WHEN (SELECT COUNT(*) FROM fusion) = 0
        THEN error('Test échoué : la jointure ne produit aucune ligne')
    WHEN (SELECT COUNT(*) FROM fusion) != (SELECT COUNT(DISTINCT sku) FROM fusion)
        THEN error('Test échoué : doublons créés par la jointure (fan-out)')
    WHEN (SELECT COUNT(*) FROM fusion) != (SELECT COUNT(*) FROM web_clean)
        THEN error('Test échoué : la jointure produit un nombre de lignes différent de web_clean (perte ou duplication de lignes)')
    ELSE 'Test réussi : jointure cohérente, ' || (SELECT COUNT(*) FROM fusion) || ' lignes, aucun doublon'
END AS resultat_test;
