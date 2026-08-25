-- ============================================================
-- Ré-export de fusion.csv (DuckDB)
-- Tâche dédiée et minimale : relit fusion.csv (déjà écrit sur le
-- disque partagé par la tâche jointure) et le réexporte immédiatement.
-- Ce script ne fait que ça, pour garantir que le fichier capturé par
-- Kestra (outputFiles) est bien complet avant transmission au
-- conteneur Python isolé de la tâche zscore.
-- ============================================================

CREATE OR REPLACE TABLE fusion AS SELECT * FROM read_csv_auto('fusion.csv');

COPY fusion TO 'fusion_export.csv' (HEADER, DELIMITER ',');
