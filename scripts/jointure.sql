-- ============================================================
-- Jointure des 3 fichiers nettoyés (DuckDB)
-- web_clean (714) -> liaison_clean (825) -> erp_clean (825)
-- Résultat attendu : 714 lignes
-- ============================================================
-- La jointure est pilotée par web_clean (714 produits web uniques).
-- liaison_clean fait le pont entre sku (web) et product_id (erp).
-- Les 91 lignes de liaison sans id_web ne matchent aucun sku : elles
-- sont naturellement exclues par l'INNER JOIN, sans traitement spécial.

INSTALL excel;
LOAD excel;

-- Recharge des 3 tables nettoyées (produites par les scripts de nettoyage précédents)
CREATE OR REPLACE TABLE erp_clean AS SELECT * FROM read_csv_auto('erp_clean.csv');
CREATE OR REPLACE TABLE liaison_clean AS SELECT * FROM read_csv_auto('liaison_clean.csv');
CREATE OR REPLACE TABLE web_clean AS SELECT * FROM read_csv_auto('web_clean.csv');

CREATE OR REPLACE TABLE fusion AS
SELECT
    w.sku,
    w.post_title,
    w.total_sales,
    w.average_rating,
    e.product_id,
    e.price,
    e.stock_quantity,
    e.stock_status
FROM web_clean w
JOIN liaison_clean l ON w.sku = l.id_web
JOIN erp_clean e ON l.product_id = e.product_id;

-- Vérification rapide (utile pour le test de cohérence de jointure qui suivra cette tâche)
-- Placée AVANT le COPY final (voir remarque plus bas sur l'ordre)
SELECT
    COUNT(*) AS nb_lignes,
    COUNT(DISTINCT sku) AS nb_sku_uniques,
    COUNT(DISTINCT product_id) AS nb_product_id_uniques
FROM fusion;

-- Export du résultat fusionné (sera utilisé pour le calcul du CA et le z-score)
-- IMPORTANT : cette instruction COPY doit être la toute dernière du script.
-- Kestra capture le fichier de sortie (outputFiles) après la fin du script ;
-- placer une requête après COPY perturbait cette capture (fichier vide reçu
-- par la tâche zscore).
COPY fusion TO 'fusion.csv' (HEADER, DELIMITER ',');
