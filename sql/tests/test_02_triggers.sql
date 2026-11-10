-- =====================================================================
--  Tests des triggers de 02_triggers.sql
--  Chaque test "doit échouer" affiche une ERROR : c'est le comportement attendu.
--  Le script est encadré par BEGIN/ROLLBACK : il ne laisse AUCUNE donnée.
-- =====================================================================
SET search_path TO conferences;
BEGIN;

-- Jeu de données minimal
INSERT INTO pays(id_pays, nom_pays) VALUES (100, 'France');
INSERT INTO ville(id_ville, nom_ville, id_pays) VALUES (100, 'Lyon', 100);
INSERT INTO organisme(id_organisme, nom, adresse, email_contact)
       VALUES (100, 'ECL', '36 av. Guy de Collongue, Ecully', 'contact@ec-lyon.fr');
INSERT INTO conference(id_conf, intitule, date_debut, date_fin, texte_introductif, id_ville, id_organisme) VALUES
  (100, 'Conférence A',  '2027-06-10', '2027-06-12', 'intro', 100, 100),
  (101, 'Workshop A1',   '2027-06-08', '2027-06-09', 'intro', 100, 100),
  (102, 'Workshop lointain', '2027-09-01', '2027-09-02', 'intro', 100, 100);
INSERT INTO personne(id_personne, nom, prenom, email) VALUES
  (100, 'Martin', 'Alice', 'alice@ec-lyon.fr'),
  (101, 'Durand', 'Bob',   'bob@ec-lyon.fr');
INSERT INTO session(id_conf, num_session, intitule_session) VALUES (100, 1, 'Spatial data');
INSERT INTO membre_pc(id_personne, id_conf) VALUES (100, 100);   -- Alice est membre du PC

\echo '=== CI-1 : Alice (membre PC) évalue la session -> OK'
INSERT INTO evalue VALUES (100, 100, 1);

\echo '=== CI-1 : Bob (PAS membre PC) évalue la session -> doit échouer'
SAVEPOINT s; INSERT INTO evalue VALUES (101, 100, 1); ROLLBACK TO s;

\echo '=== CI-1 : retirer Alice du PC alors qu''elle évalue -> doit échouer'
SAVEPOINT s; DELETE FROM membre_pc WHERE id_personne = 100 AND id_conf = 100; ROLLBACK TO s;

\echo '=== CI-2 : workshop A1 rattaché à la conférence A -> OK'
INSERT INTO workshop VALUES (101, 100);

\echo '=== CI-2a : rattacher un workshop à un workshop -> doit échouer'
SAVEPOINT s; INSERT INTO workshop VALUES (102, 101); ROLLBACK TO s;

\echo '=== CI-2b : la conférence A (qui a des workshops) devient workshop -> doit échouer'
SAVEPOINT s; INSERT INTO workshop VALUES (100, 102); ROLLBACK TO s;

\echo '=== CI-2c : workshop 3 mois après la conférence -> doit échouer'
SAVEPOINT s; INSERT INTO workshop VALUES (102, 100); ROLLBACK TO s;

INSERT INTO categorie_soumission(id_categorie, libelle) VALUES (100, 'Regular paper');

\echo '=== CI-3 : spécification avec échéances avant la conférence -> OK'
INSERT INTO specification(id_conf, id_categorie, nb_pages_max, date_limite_soumission,
                          date_notification, date_limite_version_finale)
VALUES (100, 100, 12, '2027-02-01', '2027-04-01', '2027-05-01');

\echo '=== CI-3 : version finale APRÈS le début de la conférence -> doit échouer'
SAVEPOINT s;
UPDATE specification SET date_limite_version_finale = '2027-06-15'
WHERE id_conf = 100 AND id_categorie = 100;
ROLLBACK TO s;

INSERT INTO theme(id_theme, libelle, id_theme_parent) VALUES
  (100, 'Spatial databases', NULL),
  (101, 'GIS',               100),
  (102, 'R-tree indexing',   101),
  (103, 'Temporal databases', NULL);

\echo '=== CI-4 : Spatial databases devient sous-thème de R-tree (cycle) -> doit échouer'
SAVEPOINT s; UPDATE theme SET id_theme_parent = 102 WHERE id_theme = 100; ROLLBACK TO s;

\echo '=== Fonction fn_themes_descendants(''spatial'') -> 3 thèmes attendus'
SELECT * FROM fn_themes_descendants('spatial') ORDER BY id_theme;

ROLLBACK;