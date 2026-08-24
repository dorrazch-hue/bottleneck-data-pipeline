-- ============================================================
-- Test de la classification z-score (DuckDB)
-- Vérifie : la somme premium+ordinaire = total fusionné (aucune perte),
-- et que la classification respecte bien le seuil z-score > 2
-- ============================================================

CREATE OR REPLACE TABLE vins_premium AS SELECT * FROM read_csv_auto('vins_premium.csv');
CREATE OR REPLACE TABLE vins_ordinaires AS SELECT * FROM read_csv_auto('vins_ordinaires.csv');
CREATE OR REPLACE TABLE fusion AS SELECT * FROM read_csv_auto('fusion.csv');

SELECT CASE
    WHEN (SELECT COUNT(*) FROM vins_premium) + (SELECT COUNT(*) FROM vins_ordinaires) != (SELECT COUNT(*) FROM fusion)
        THEN error('Test échoué : la somme premium+ordinaire ne correspond pas au total fusionné')
    WHEN (SELECT COUNT(*) FROM vins_premium WHERE z_score <= 2) > 0
        THEN error('Test échoué : un vin classé premium a un z-score <= 2')
    WHEN (SELECT COUNT(*) FROM vins_ordinaires WHERE z_score > 2) > 0
        THEN error('Test échoué : un vin classé ordinaire a un z-score > 2')
    ELSE 'Test réussi : ' || (SELECT COUNT(*) FROM vins_premium) || ' premium / ' || (SELECT COUNT(*) FROM vins_ordinaires) || ' ordinaires, classification cohérente'
END AS resultat_test;
