-- ============================================================
-- Test du calcul de CA (DuckDB)
-- Vérifie : CA total non nul/positif, aucun CA produit négatif,
-- cohérence entre la somme du détail par produit et le total
-- ============================================================

CREATE OR REPLACE TABLE ca_par_produit AS SELECT * FROM read_csv_auto('ca_par_produit.csv');
CREATE OR REPLACE TABLE ca_total AS SELECT * FROM read_csv_auto('ca_total.csv');

SELECT CASE
    WHEN (SELECT chiffre_affaires_total FROM ca_total) IS NULL
        THEN error('Test échoué : CA total est NULL')
    WHEN (SELECT chiffre_affaires_total FROM ca_total) <= 0
        THEN error('Test échoué : CA total est nul ou négatif')
    WHEN (SELECT COUNT(*) FROM ca_par_produit WHERE chiffre_affaires < 0) > 0
        THEN error('Test échoué : au moins un produit a un CA négatif')
    WHEN ABS((SELECT SUM(chiffre_affaires) FROM ca_par_produit) - (SELECT chiffre_affaires_total FROM ca_total)) > 0.01
        THEN error('Test échoué : incohérence entre la somme du détail par produit et le total')
    ELSE 'Test réussi : CA total = ' || (SELECT chiffre_affaires_total FROM ca_total) || ' euros, cohérent'
END AS resultat_test;
