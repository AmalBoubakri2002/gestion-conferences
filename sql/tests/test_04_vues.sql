-- =====================================================================
--  Tests des vues de 04_vues.sql
--  Mini jeu de données dans une transaction annulée (ROLLBACK) :
--  la base n'est pas modifiée.
--  Identifiants >= 900100 et libellés TEST_ : aucun conflit avec les
--  données du notebook. Chaque SELECT ne montre que ces données de test.
-- =====================================================================
SET search_path TO conferences, public;
BEGIN;

INSERT INTO pays(id_pays, nom_pays) VALUES (900100, 'TEST_France'), (900101, 'TEST_Italie');
INSERT INTO ville(id_ville, nom_ville, id_pays) VALUES
  (900100, 'TEST_Lyon', 900100), (900101, 'TEST_Paris', 900100), (900102, 'TEST_Rome', 900101);
INSERT INTO organisme(id_organisme, nom, adresse, email_contact)
       VALUES (900100, 'TEST_École Centrale de Lyon', 'Ecully', 'contact@test.fr');
INSERT INTO serie(id_serie, sigle, nom_serie) VALUES (900100, 'TEST_SDH', 'Spatial Data Handling');
INSERT INTO editeur(id_editeur, nom_editeur) VALUES (900100, 'TEST_Springer');

INSERT INTO conference(id_conf, intitule, date_debut, date_fin, texte_introductif, id_ville, id_organisme, id_serie, id_editeur) VALUES
  (900100, 'SDH 2027',              '2027-06-10', '2027-06-12', 'intro', 900100, 900100, 900100, 900100),
  (900101, 'Workshop GIS @ SDH',    '2027-06-09', '2027-06-09', 'intro', 900100, 900100, NULL,   NULL),
  (900102, 'Temporal DB Days',      '2027-09-01', '2027-09-03', 'intro', 900101, 900100, NULL,   900100),
  (900103, 'Roma Data Conference',  '2027-10-01', '2027-10-02', 'intro', 900102, 900100, NULL,   NULL);
INSERT INTO workshop VALUES (900101, 900100);

INSERT INTO theme(id_theme, libelle, id_theme_parent) VALUES
  (900100, 'TEST_Spatial databases', NULL), (900101, 'TEST_GIS', 900100),
  (900102, 'TEST_R-tree indexing', 900101), (900103, 'TEST_Temporal databases', NULL);

INSERT INTO session(id_conf, num_session, intitule_session) VALUES
  (900100, 1, 'Indexation spatiale'), (900101, 1, 'GIS en pratique'), (900102, 1, 'Temps et versions');
INSERT INTO session_theme VALUES (900100, 1, 900102), (900101, 1, 900101), (900102, 1, 900103);

INSERT INTO personne(id_personne, nom, prenom, email) VALUES
  (900100, 'Ardabilian', 'Mohsen', 'mohsen@test.fr'),
  (900101, 'Martin',     'Alice',  'alice@test.fr'),
  (900102, 'Durand',     'Bob',    'bob@test.fr');
INSERT INTO utilisateur(id_personne, login, mot_de_passe, role) VALUES
  (900101, 'test_alice', 'hash', 'utilisateur'),
  (900102, 'test_bob',   'hash', 'utilisateur');
INSERT INTO utilisateur_theme VALUES (900101, 900100);   -- Alice : intéressée par "Spatial databases"
INSERT INTO type_responsabilite(id_type, libelle) VALUES (900100, 'TEST_General chair');
INSERT INTO responsable_de VALUES (900100, 900100, 900100), (900101, 900102, 900100);   -- Mohsen chair SDH, Alice chair Temporal
INSERT INTO membre_pc VALUES (900100, 900102);                                           -- Mohsen membre PC Temporal

\echo '=== V1 v_conference_complete (le workshop doit avoir est_workshop = t)'
SELECT id_conf, intitule, nom_ville, nom_pays, serie_sigle, nom_editeur, est_workshop, id_conf_mere
FROM v_conference_complete WHERE id_conf >= 900100 ORDER BY id_conf;

\echo '=== V2 v_personnes_responsables (Mohsen : 2 lignes, Alice : 1 ligne)'
SELECT nom, prenom, intitule, role FROM v_personnes_responsables
WHERE id_personne >= 900100 ORDER BY nom, intitule;

\echo '=== V3 v_conference_themes'
SELECT intitule, theme FROM v_conference_themes WHERE id_conf >= 900100 ORDER BY id_conf;

\echo '=== V4 v_workshops'
SELECT workshop, conference_mere FROM v_workshops WHERE id_workshop >= 900100;

\echo '=== V5 v_conferences_par_pays (TEST_France : 3, TEST_Italie : 1)'
SELECT * FROM v_conferences_par_pays WHERE nom_pays LIKE 'TEST%' ORDER BY nom_pays;

\echo '=== V6 v_utilisateur_conferences (Alice : SDH 2027 via R-tree, Workshop via GIS)'
SELECT login, intitule, theme_profil, theme_conference FROM v_utilisateur_conferences
WHERE login = 'test_alice' ORDER BY intitule;

\echo '=== V7 v_utilisateurs_responsables (Alice seulement ; Bob n''est responsable de rien)'
SELECT login, nom, nb_conferences, roles FROM v_utilisateurs_responsables
WHERE id_personne >= 900100;

ROLLBACK;
