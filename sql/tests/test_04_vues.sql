-- =====================================================================
--  Tests des vues de 04_vues.sql
--  Mini jeu de données dans une transaction annulée (ROLLBACK) :
--  la base n'est pas modifiée.
-- =====================================================================
SET search_path TO conferences, public;
BEGIN;

INSERT INTO pays(id_pays, nom_pays) VALUES (100, 'France'), (101, 'Italie');
INSERT INTO ville(id_ville, nom_ville, id_pays) VALUES (100, 'Lyon', 100), (101, 'Paris', 100), (102, 'Rome', 101);
INSERT INTO organisme(id_organisme, nom, adresse, email_contact)
       VALUES (100, 'École Centrale de Lyon', 'Ecully', 'contact@ec-lyon.fr');
INSERT INTO serie(id_serie, sigle, nom_serie) VALUES (100, 'SDH', 'Spatial Data Handling');
INSERT INTO editeur(id_editeur, nom_editeur) VALUES (100, 'Springer');

INSERT INTO conference(id_conf, intitule, date_debut, date_fin, texte_introductif, id_ville, id_organisme, id_serie, id_editeur) VALUES
  (100, 'SDH 2027',              '2027-06-10', '2027-06-12', 'intro', 100, 100, 100, 100),
  (101, 'Workshop GIS @ SDH',    '2027-06-09', '2027-06-09', 'intro', 100, 100, NULL, NULL),
  (102, 'Temporal DB Days',      '2027-09-01', '2027-09-03', 'intro', 101, 100, NULL, 100),
  (103, 'Roma Data Conference',  '2027-10-01', '2027-10-02', 'intro', 102, 100, NULL, NULL);
INSERT INTO workshop VALUES (101, 100);

INSERT INTO theme(id_theme, libelle, id_theme_parent) VALUES
  (100, 'Spatial databases', NULL), (101, 'GIS', 100), (102, 'R-tree indexing', 101),
  (103, 'Temporal databases', NULL);

INSERT INTO session(id_conf, num_session, intitule_session) VALUES
  (100, 1, 'Indexation spatiale'), (101, 1, 'GIS en pratique'), (102, 1, 'Temps et versions');
INSERT INTO session_theme VALUES (100, 1, 102), (101, 1, 101), (102, 1, 103);

INSERT INTO personne(id_personne, nom, prenom, email) VALUES
  (100, 'Ardabilian', 'Mohsen', 'mohsen@ec-lyon.fr'),
  (101, 'Martin',     'Alice',  'alice@ec-lyon.fr'),
  (102, 'Durand',     'Bob',    'bob@ec-lyon.fr');
INSERT INTO utilisateur(id_personne, login, mot_de_passe, role) VALUES
  (101, 'alice', 'hash', 'utilisateur'),
  (102, 'bob',   'hash', 'utilisateur');
INSERT INTO utilisateur_theme VALUES (101, 100);   -- Alice : intéressée par "Spatial databases"
INSERT INTO type_responsabilite(id_type, libelle) VALUES (100, 'General chair');
INSERT INTO responsable_de VALUES (100, 100, 100), (101, 102, 100);   -- Mohsen chair SDH, Alice chair Temporal
INSERT INTO membre_pc VALUES (100, 102);                               -- Mohsen membre PC Temporal

\echo '=== V1 v_conference_complete (le workshop doit avoir est_workshop = t)'
SELECT id_conf, intitule, nom_ville, nom_pays, serie_sigle, nom_editeur, est_workshop, id_conf_mere
FROM v_conference_complete ORDER BY id_conf;

\echo '=== V2 v_personnes_responsables (Mohsen : 2 lignes, Alice : 1 ligne)'
SELECT nom, prenom, intitule, role FROM v_personnes_responsables ORDER BY nom, intitule;

\echo '=== V3 v_conference_themes'
SELECT intitule, theme FROM v_conference_themes ORDER BY id_conf;

\echo '=== V4 v_workshops'
SELECT workshop, conference_mere FROM v_workshops;

\echo '=== V5 v_conferences_par_pays (France : 3, Italie : 1)'
SELECT * FROM v_conferences_par_pays ORDER BY nom_pays;

\echo '=== V6 v_utilisateur_conferences (Alice : SDH 2027 via R-tree, Workshop via GIS)'
SELECT login, intitule, theme_profil, theme_conference FROM v_utilisateur_conferences ORDER BY intitule;

\echo '=== V7 v_utilisateurs_responsables (Alice seulement ; Bob n''est responsable de rien)'
SELECT login, nom, nb_conferences, roles FROM v_utilisateurs_responsables;

ROLLBACK;