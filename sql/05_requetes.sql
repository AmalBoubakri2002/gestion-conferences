-- =====================================================================
--  MOD 11.1 - Projet 4 : Gestion des conférences
--  Fichier 05_requetes.sql : les 9 requêtes du sujet
--  Prérequis : base créée (init_db.sh) et alimentée (alimentation.ipynb).
--
--  Les requêtes sont PARAMÉTRÉES avec des variables psql (\set).
--  Pour changer un paramètre : modifier la valeur ci-dessous, ou lancer
--     psql -d gestion_conferences -v login=bob -f sql/05_requetes.sql
--  Dans l'interface (Python), ces variables deviendront des paramètres
--  de requête (%s), ce qui protège contre les injections SQL.
-- =====================================================================

SET search_path TO conferences, public;
\pset null '-'

-- ---------- Paramètres (valeurs par défaut) ----------
\if :{?mot_cle}      \else \set mot_cle 'spatial'           \endif
\if :{?login}        \else \set login 'alice'               \endif
\if :{?sigle}        \else \set sigle 'SDH'                 \endif
\if :{?id_conf}      \else \set id_conf 1                   \endif
\if :{?editeur}      \else \set editeur 'Springer'          \endif
\if :{?nom}          \else \set nom 'Dupont'                \endif
\if :{?prenom}       \else \set prenom 'Jean'               \endif


-- =====================================================================
-- REQUÊTE 1 : Afficher la liste des conférences qui ont lieu dans
--             l'année courante.
-- ---------------------------------------------------------------------
-- - Année courante calculée par le SGBD (CURRENT_DATE) : la requête
--   reste valable quelle que soit l'année d'exécution.
-- - Intervalle [1er janvier ; 1er janvier suivant[ plutôt que
--   EXTRACT(YEAR ...) = ... : l'index idx_conference_date_debut est utilisé.
-- - On indique si la conférence est un workshop.
-- =====================================================================
\echo '\n===== REQUÊTE 1 : conférences de l''année courante ====='
SELECT id_conf,
       intitule,
       date_debut,
       date_fin,
       nom_ville || ' (' || nom_pays || ')' AS lieu,
       CASE WHEN est_workshop THEN 'Workshop' ELSE 'Conférence' END AS type
FROM v_conference_complete
WHERE date_debut >= date_trunc('year', CURRENT_DATE)
  AND date_debut <  date_trunc('year', CURRENT_DATE) + INTERVAL '1 year'
ORDER BY date_debut, intitule;


-- =====================================================================
-- REQUÊTE 2 : Afficher la liste des pays, avec pour chaque pays la
--             liste des conférences (intitulé) qui y ont été organisées.
-- ---------------------------------------------------------------------
-- - Jointure pays -> ville -> conférence, regroupement par pays.
-- - STRING_AGG concatène les intitulés en une liste par pays.
-- - LEFT JOIN : les pays sans conférence apparaissent aussi (liste vide).
-- - On ne garde que les conférences principales (workshops exclus) pour
--   la lisibilité.
-- =====================================================================
\echo '\n===== REQUÊTE 2 : conférences par pays ====='
SELECT p.nom_pays,
       COUNT(c.id_conf) AS nb_conferences,
       COALESCE(STRING_AGG(c.intitule, ' ; ' ORDER BY c.date_debut), '(aucune)') AS conferences
FROM pays p
LEFT JOIN ville      v ON v.id_pays  = p.id_pays
LEFT JOIN conference c ON c.id_ville = v.id_ville
                      AND NOT EXISTS (SELECT 1 FROM workshop w WHERE w.id_conf = c.id_conf)
GROUP BY p.nom_pays
ORDER BY nb_conferences DESC, p.nom_pays;


-- =====================================================================
-- REQUÊTE 3 : Afficher les conférences qui portent sur un domaine de
--             recherche portant sur les bases de données spatiales
--             (le mot-clé enregistré n'est pas forcément "bases de
--             données spatiales").
-- ---------------------------------------------------------------------
-- - fn_themes_descendants('spatial') (02_triggers.sql) renvoie les thèmes
--   dont le libellé contient le mot-clé ET tous leurs sous-thèmes
--   (parcours récursif de la hiérarchie) : GIS, R-tree, Trajectory data...
-- - On garde les conférences dont au moins une session porte sur l'un
--   de ces thèmes, et on affiche les thèmes concernés.
-- =====================================================================
\echo '\n===== REQUÊTE 3 : conférences sur le domaine' :'mot_cle' '====='
SELECT ct.id_conf,
       ct.intitule,
       ct.date_debut,
       STRING_AGG(DISTINCT ct.theme, ', ') AS themes_concernes
FROM v_conference_themes ct
WHERE ct.id_theme IN (SELECT id_theme FROM fn_themes_descendants(:'mot_cle'))
GROUP BY ct.id_conf, ct.intitule, ct.date_debut
ORDER BY ct.date_debut DESC;


-- =====================================================================
-- REQUÊTE 4 : Afficher la liste des conférences qui intéressent un
--             utilisateur particulier.
-- ---------------------------------------------------------------------
-- - Le profil de l'utilisateur = ses thèmes (utilisateur_theme).
-- - La vue v_utilisateur_conferences étend le profil aux sous-thèmes,
--   puis cherche les conférences dont une session porte sur ces thèmes.
-- - On indique si la conférence est passée ou à venir.
-- =====================================================================
\echo '\n===== REQUÊTE 4 : conférences qui intéressent l''utilisateur' :'login' '====='
SELECT uc.id_conf,
       uc.intitule,
       uc.date_debut,
       CASE WHEN uc.date_debut >= CURRENT_DATE THEN 'à venir' ELSE 'passée' END AS statut,
       STRING_AGG(DISTINCT uc.theme_conference, ', ') AS themes_correspondants
FROM v_utilisateur_conferences uc
WHERE uc.login = :'login'
GROUP BY uc.id_conf, uc.intitule, uc.date_debut
ORDER BY uc.date_debut DESC;


-- =====================================================================
-- REQUÊTE 5 : Afficher la liste des conférences du groupe de
--             conférences SDH.
-- ---------------------------------------------------------------------
-- - Filtre sur le sigle de la série (identifiant secondaire, indexé).
-- =====================================================================
\echo '\n===== REQUÊTE 5 : conférences de la série' :'sigle' '====='
SELECT id_conf,
       intitule,
       date_debut,
       nom_ville || ' (' || nom_pays || ')' AS lieu,
       organisme,
       nom_editeur
FROM v_conference_complete
WHERE serie_sigle = :'sigle'
ORDER BY date_debut;


-- =====================================================================
-- REQUÊTE 6 : Afficher la liste des workshops organisés conjointement
--             avec une conférence donnée.
-- ---------------------------------------------------------------------
-- - Vue v_workshops : chaque workshop avec sa conférence mère.
-- - Paramètre : l'identifiant de la conférence (dans l'interface, il est
--   choisi dans une liste déroulante).
-- - On calcule la position du workshop par rapport à la conférence.
-- =====================================================================
\echo '\n===== REQUÊTE 6 : workshops de la conférence n°' :id_conf '====='
SELECT id_workshop,
       workshop,
       workshop_debut,
       workshop_fin,
       conference_mere,
       CASE WHEN workshop_fin < conference_debut THEN 'avant la conférence'
            WHEN workshop_debut > conference_fin THEN 'après la conférence'
            ELSE 'pendant la conférence' END AS position
FROM v_workshops
WHERE id_conf_mere = :id_conf
ORDER BY workshop_debut;


-- =====================================================================
-- REQUÊTE 7 : Afficher la liste des conférences qui ont publié dans les
--             actes d'un éditeur donné.
-- =====================================================================
\echo '\n===== REQUÊTE 7 : conférences publiées par' :'editeur' '====='
SELECT id_conf,
       intitule,
       date_debut,
       serie_sigle
FROM v_conference_complete
WHERE nom_editeur = :'editeur'
ORDER BY date_debut DESC;


-- =====================================================================
-- REQUÊTE 8 : Afficher la liste des utilisateurs de la base de données
--             qui ont aussi été responsables d'une conférence (comme
--             responsable ou membre du comité de programme).
-- ---------------------------------------------------------------------
-- - Grâce à l'héritage UTILISATEUR -> PERSONNE, un utilisateur et un
--   responsable sont la même personne (même id_personne) : simple jointure,
--   sans comparer de chaînes (emails, noms).
-- - Équivalent "à la main", sans la vue :
--     SELECT ... FROM utilisateur u JOIN personne p USING (id_personne)
--     WHERE EXISTS (SELECT 1 FROM responsable_de r WHERE r.id_personne = u.id_personne)
--        OR EXISTS (SELECT 1 FROM membre_pc m      WHERE m.id_personne = u.id_personne);
-- =====================================================================
\echo '\n===== REQUÊTE 8 : utilisateurs qui ont aussi été responsables ====='
SELECT login,
       prenom || ' ' || nom AS utilisateur,
       email,
       nb_conferences,
       roles
FROM v_utilisateurs_responsables
ORDER BY nb_conferences DESC, nom;


-- =====================================================================
-- REQUÊTE 9 : Afficher la liste des conférences pour lesquelles le
--             professeur "X" a été responsable (comme responsable ou
--             membre du comité de programme).
-- ---------------------------------------------------------------------
-- - v_personnes_responsables réunit (UNION) responsabilités et comités.
-- - Recherche insensible à la casse avec lower() : l'index sur
--   expression idx_personne_nom_lower peut être utilisé.
-- - Une conférence où X a plusieurs rôles n'apparaît qu'une fois, avec
--   la liste de ses rôles.
-- =====================================================================
\echo '\n===== REQUÊTE 9 : conférences dont' :'prenom' :'nom' 'a été responsable ====='
SELECT pr.id_conf,
       pr.intitule,
       pr.date_debut,
       STRING_AGG(pr.role, ', ' ORDER BY pr.role) AS roles
FROM v_personnes_responsables pr
JOIN personne pe ON pe.id_personne = pr.id_personne
WHERE lower(pe.nom)    = lower(:'nom')
  AND lower(pe.prenom) = lower(:'prenom')
GROUP BY pr.id_conf, pr.intitule, pr.date_debut
ORDER BY pr.date_debut DESC;