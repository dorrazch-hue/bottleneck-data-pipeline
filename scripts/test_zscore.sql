-- ============================================================
-- Test de la classification z-score (DuckDB)
-- Vérifie : la somme premium+ordinaire = total fusionné (aucune perte),
-- et que la classification respecte bien le seuil z-score > 2
--
-- CAST explicite de z_score en DOUBLE : quand vins_premium.csv (ou
-- vins_ordinaires.csv) ne contient aucune ligne de données (cas où
-- aucun vin premium n'est détecté ce mois-ci), DuckDB n'a rien à
-- examiner pour deviner le type de la colonne et la traite par
-- défaut comme du texte (VARCHAR), ce qui fait planter toute
-- comparaison numérique. Le CAST force le bon type dans tous les cas.
-- ============================================================

CREATE OR REPLACE TABLE vins_premium AS
    SELECT * REPLACE (CAST(z_score AS DOUBLE) AS z_score)
    FROM read_csv_auto('vins_premium.csv');
CREATE OR REPLACE TABLE vins_ordinaires AS
    SELECT * REPLACE (CAST(z_score AS DOUBLE) AS z_score)
    FROM read_csv_auto('vins_ordinaires.csv');
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
