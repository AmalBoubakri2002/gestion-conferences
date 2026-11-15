-- =====================================================================
--  Tests des triggers de 02_triggers.sql
--  Chaque test "doit échouer" affiche une ERROR : c'est le comportement
--  attendu (9 ERROR au total, toutes volontaires).
--  Identifiants >= 900100 et libellés TEST_ : aucun conflit avec les
--  données du notebook, le script marche sur une base vide OU remplie.
--  Le script est encadré par BEGIN/ROLLBACK : il ne laisse AUCUNE donnée.
-- =====================================================================
SET search_path TO conferences;
BEGIN;

-- Jeu de données minimal
INSERT INTO pays(id_pays, nom_pays) VALUES (900100, 'TEST_France');
INSERT INTO ville(id_ville, nom_ville, id_pays) VALUES (900100, 'TEST_Lyon', 900100);
INSERT INTO organisme(id_organisme, nom, adresse, email_contact)
       VALUES (900100, 'TEST_ECL', '36 av. Guy de Collongue, Ecully', 'contact@test.fr');
INSERT INTO conference(id_conf, intitule, date_debut, date_fin, texte_introductif, id_ville, id_organisme) VALUES
  (900100, 'TEST Conférence A',      '2027-06-10', '2027-06-12', 'intro', 900100, 900100),
  (900101, 'TEST Workshop A1',       '2027-06-08', '2027-06-09', 'intro', 900100, 900100),
  (900102, 'TEST Workshop lointain', '2027-09-01', '2027-09-02', 'intro', 900100, 900100);
INSERT INTO personne(id_personne, nom, prenom, email) VALUES
  (900100, 'Martin', 'Alice', 'alice@test.fr'),
  (900101, 'Durand', 'Bob',   'bob@test.fr');
INSERT INTO session(id_conf, num_session, intitule_session) VALUES (900100, 1, 'Spatial data');
INSERT INTO membre_pc(id_personne, id_conf) VALUES (900100, 900100);   -- Alice est membre du PC

\echo '=== CI-1 : Alice (membre PC) évalue la session -> OK'
INSERT INTO evalue VALUES (900100, 900100, 1);

\echo '=== CI-1 : Bob (PAS membre PC) évalue la session -> doit échouer'
SAVEPOINT s; INSERT INTO evalue VALUES (900101, 900100, 1); ROLLBACK TO s;

\echo '=== CI-1 : retirer Alice du PC alors qu''elle évalue -> doit échouer'
SAVEPOINT s; DELETE FROM membre_pc WHERE id_personne = 900100 AND id_conf = 900100; ROLLBACK TO s;

\echo '=== CI-1 : Bob passe du PC de A au PC de la conférence 900102 (UPDATE) -> OK, id_conf = 900102 attendu'
INSERT INTO membre_pc VALUES (900101, 900100);
UPDATE membre_pc SET id_conf = 900102 WHERE id_personne = 900101 AND id_conf = 900100;
SELECT id_personne, id_conf FROM membre_pc WHERE id_personne = 900101;

\echo '=== CI-2 : workshop A1 rattaché à la conférence A -> OK'
INSERT INTO workshop VALUES (900101, 900100);

\echo '=== CI-2a : rattacher un workshop à un workshop -> doit échouer'
SAVEPOINT s; INSERT INTO workshop VALUES (900102, 900101); ROLLBACK TO s;

\echo '=== CI-2b : la conférence A (qui a des workshops) devient workshop -> doit échouer'
SAVEPOINT s; INSERT INTO workshop VALUES (900100, 900102); ROLLBACK TO s;

\echo '=== CI-2c : workshop 3 mois après la conférence -> doit échouer'
SAVEPOINT s; INSERT INTO workshop VALUES (900102, 900100); ROLLBACK TO s;

\echo '=== CI-2c : déplacer la conférence A d''un mois (son workshop resterait loin) -> doit échouer'
SAVEPOINT s;
UPDATE conference SET date_debut = '2027-07-10', date_fin = '2027-07-12' WHERE id_conf = 900100;
ROLLBACK TO s;

\echo '=== CI-2c : déplacer A ET son workshop dans le même UPDATE -> OK'
SAVEPOINT s;
UPDATE conference SET date_debut = date_debut + 30, date_fin = date_fin + 30 WHERE id_conf IN (900100, 900101);
ROLLBACK TO s;

INSERT INTO categorie_soumission(id_categorie, libelle) VALUES (900100, 'TEST_Regular paper');

\echo '=== CI-3 : spécification avec échéances avant la conférence -> OK'
INSERT INTO specification(id_conf, id_categorie, nb_pages_max, date_limite_soumission,
                          date_notification, date_limite_version_finale)
VALUES (900100, 900100, 12, '2027-02-01', '2027-04-01', '2027-05-01');

\echo '=== CI-3 : version finale APRÈS le début de la conférence -> doit échouer'
SAVEPOINT s;
UPDATE specification SET date_limite_version_finale = '2027-06-15'
WHERE id_conf = 900100 AND id_categorie = 900100;
ROLLBACK TO s;

\echo '=== CI-3 : avancer le début de la conférence avant la version finale -> doit échouer'
SAVEPOINT s; UPDATE conference SET date_debut = '2027-04-20' WHERE id_conf = 900100; ROLLBACK TO s;

INSERT INTO theme(id_theme, libelle, id_theme_parent) VALUES
  (900100, 'TEST_Spatial databases',  NULL),
  (900101, 'TEST_GIS',                900100),
  (900102, 'TEST_R-tree indexing',    900101),
  (900103, 'TEST_Temporal databases', NULL);

\echo '=== CI-4 : Spatial databases devient sous-thème de R-tree (cycle) -> doit échouer'
SAVEPOINT s; UPDATE theme SET id_theme_parent = 900102 WHERE id_theme = 900100; ROLLBACK TO s;

\echo '=== Fonction fn_themes_descendants(''TEST_Spatial'') -> 3 thèmes attendus'
SELECT * FROM fn_themes_descendants('TEST_Spatial') ORDER BY id_theme;

\echo '=== Suppression de la conférence A -> son workshop A1 est supprimé aussi (0 attendu)'
DELETE FROM conference WHERE id_conf = 900100;
SELECT COUNT(*) AS workshops_restants FROM conference WHERE id_conf = 900101;

ROLLBACK;
