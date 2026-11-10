-- =====================================================================
--  Démonstration de l'utilité des index avec EXPLAIN ANALYZE
--  1) on insère un gros volume de données factices (identifiants >= 900000)
--  2) on compare les plans d'exécution SANS puis AVEC index
--  3) on supprime les données factices : la base revient à son état initial
-- =====================================================================
SET search_path TO conferences, public;

-- ---------- 1) Données factices en volume ----------
INSERT INTO pays(id_pays, nom_pays) VALUES (900000, 'TEST_pays');
INSERT INTO ville(id_ville, nom_ville, id_pays) VALUES (900000, 'TEST_ville', 900000);
INSERT INTO organisme(id_organisme, nom, adresse, email_contact)
       VALUES (900000, 'TEST_org', 'adresse', 'org@test.fr');

-- 50 000 conférences réparties entre 2000 et 2030
INSERT INTO conference(id_conf, intitule, date_debut, date_fin, texte_introductif, id_ville, id_organisme)
SELECT 900000 + g,
       'TEST_conference ' || g,
       DATE '2000-01-01' + (g % 11000),
       DATE '2000-01-01' + (g % 11000) + 2,
       'intro', 900000, 900000
FROM generate_series(1, 50000) g;

-- 20 000 thèmes, dont 10 contiennent "spatial"
INSERT INTO theme(id_theme, libelle)
SELECT 900000 + g,
       CASE WHEN g % 2000 = 0 THEN 'TEST_Spatial topic ' || g
            ELSE 'TEST_theme ' || md5(g::text) END
FROM generate_series(1, 20000) g;

-- Mettre à jour les statistiques et vider la "liste d'attente" de l'index GIN
VACUUM ANALYZE conference;
VACUUM ANALYZE theme;

-- ---------- 2a) Requête 1 SANS index (on interdit les index) ----------
\echo '=== Requête 1 SANS index : "Seq Scan" (lecture de toute la table)'
SET enable_indexscan = off; SET enable_bitmapscan = off;
EXPLAIN ANALYZE
SELECT id_conf, intitule, date_debut FROM conference
WHERE date_debut >= date_trunc('year', CURRENT_DATE)
  AND date_debut <  date_trunc('year', CURRENT_DATE) + INTERVAL '1 year';
RESET enable_indexscan; RESET enable_bitmapscan;

-- ---------- 2b) Requête 1 AVEC index ----------
\echo '=== Requête 1 AVEC index : "Bitmap Index Scan on idx_conference_date_debut"'
EXPLAIN ANALYZE
SELECT id_conf, intitule, date_debut FROM conference
WHERE date_debut >= date_trunc('year', CURRENT_DATE)
  AND date_debut <  date_trunc('year', CURRENT_DATE) + INTERVAL '1 year';

-- ---------- 2c) Recherche par mot-clé SANS index ----------
\echo '=== Mot-clé SANS index : "Seq Scan"'
SET enable_indexscan = off; SET enable_bitmapscan = off;
EXPLAIN ANALYZE SELECT id_theme, libelle FROM theme WHERE libelle ILIKE '%spatial%';
RESET enable_indexscan; RESET enable_bitmapscan;

-- ---------- 2d) Recherche par mot-clé AVEC index ----------
\echo '=== Mot-clé AVEC index : "Bitmap Index Scan on idx_theme_libelle_trgm"'
EXPLAIN ANALYZE SELECT id_theme, libelle FROM theme WHERE libelle ILIKE '%spatial%';

-- ---------- 3) Nettoyage ----------
DELETE FROM theme      WHERE id_theme >= 900000;
DELETE FROM conference WHERE id_conf  >= 900000;
DELETE FROM organisme  WHERE id_organisme = 900000;
DELETE FROM ville      WHERE id_ville = 900000;
DELETE FROM pays       WHERE id_pays = 900000;
VACUUM ANALYZE;
\echo '=== Données de test supprimées'