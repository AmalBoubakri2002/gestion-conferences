-- =====================================================================
--  MOD 11.1 - Projet 4 : Gestion des conférences
--  Fichier 04_vues.sql : vues
--  Prérequis : 01, 02 et 03 exécutés.
--
--  Une vue est une requête enregistrée sous un nom : on l'interroge
--  comme une table. Elles servent ici à :
--    - masquer les jointures répétitives (v_conference_complete) ;
--    - simplifier les 9 requêtes du sujet et l'interface ;
--    - présenter les données à l'utilisateur sans exposer le schéma.
-- =====================================================================

SET search_path TO conferences, public;

-- ---------------------------------------------------------------------
-- V1. v_conference_complete
--     Toutes les informations d'une conférence sur une seule ligne :
--     lieu, organisateur, série, éditeur, et s'il s'agit d'un workshop.
--     Utilisée par les requêtes 1, 2, 5, 7 et par l'interface.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_conference_complete AS
SELECT
    c.id_conf,
    c.intitule,
    c.date_debut,
    c.date_fin,
    c.texte_introductif,
    v.id_ville,
    v.nom_ville,
    p.id_pays,
    p.nom_pays,
    o.id_organisme,
    o.nom            AS organisme,
    o.email_contact  AS organisme_email,
    s.id_serie,
    s.sigle          AS serie_sigle,
    s.nom_serie,
    e.id_editeur,
    e.nom_editeur,
    (w.id_conf IS NOT NULL) AS est_workshop,   -- TRUE si la conférence est un workshop
    w.id_conf_mere
FROM conference c
JOIN      ville     v ON v.id_ville     = c.id_ville
JOIN      pays      p ON p.id_pays      = v.id_pays
JOIN      organisme o ON o.id_organisme = c.id_organisme
LEFT JOIN serie     s ON s.id_serie     = c.id_serie      -- 0-1 : LEFT JOIN
LEFT JOIN editeur   e ON e.id_editeur   = c.id_editeur    -- 0-1 : LEFT JOIN
LEFT JOIN workshop  w ON w.id_conf      = c.id_conf;      -- héritage partiel

-- ---------------------------------------------------------------------
-- V2. v_personnes_responsables
--     Union des deux façons d'être "responsable" d'une conférence :
--     avoir un type de responsabilité OU être membre du comité de programme.
--     Utilisée par les requêtes 8 et 9.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_personnes_responsables AS
SELECT
    pe.id_personne, pe.nom, pe.prenom, pe.email,
    c.id_conf, c.intitule, c.date_debut,
    tr.libelle AS role
FROM responsable_de r
JOIN personne            pe ON pe.id_personne = r.id_personne
JOIN conference          c  ON c.id_conf      = r.id_conf
JOIN type_responsabilite tr ON tr.id_type     = r.id_type
UNION                                   -- UNION (et non UNION ALL) : supprime les doublons
SELECT
    pe.id_personne, pe.nom, pe.prenom, pe.email,
    c.id_conf, c.intitule, c.date_debut,
    'Program Committee member' AS role
FROM membre_pc m
JOIN personne   pe ON pe.id_personne = m.id_personne
JOIN conference c  ON c.id_conf      = m.id_conf;

-- ---------------------------------------------------------------------
-- V3. v_conference_themes
--     Thèmes abordés par chaque conférence (via ses sessions).
--     Une conférence porte sur un thème si au moins une de ses sessions
--     porte sur ce thème. Utilisée par les requêtes 3 et 4.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_conference_themes AS
SELECT DISTINCT
    c.id_conf,
    c.intitule,
    c.date_debut,
    t.id_theme,
    t.libelle AS theme
FROM conference    c
JOIN session_theme st ON st.id_conf  = c.id_conf
JOIN theme         t  ON t.id_theme  = st.id_theme;

-- ---------------------------------------------------------------------
-- V4. v_workshops
--     Chaque workshop avec sa conférence mère. Utilisée par la requête 6.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_workshops AS
SELECT
    w.id_conf         AS id_workshop,
    cw.intitule       AS workshop,
    cw.date_debut     AS workshop_debut,
    cw.date_fin       AS workshop_fin,
    w.id_conf_mere,
    cm.intitule       AS conference_mere,
    cm.date_debut     AS conference_debut,
    cm.date_fin       AS conference_fin
FROM workshop   w
JOIN conference cw ON cw.id_conf = w.id_conf
JOIN conference cm ON cm.id_conf = w.id_conf_mere;

-- ---------------------------------------------------------------------
-- V5. v_conferences_par_pays
--     Pour chaque pays, la liste des conférences qui y ont été organisées.
--     Répond directement à la requête 2.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_conferences_par_pays AS
SELECT
    p.nom_pays,
    COUNT(c.id_conf) AS nb_conferences,
    STRING_AGG(c.intitule, ' ; ' ORDER BY c.date_debut) AS conferences
FROM pays p
JOIN ville      v ON v.id_pays  = p.id_pays
JOIN conference c ON c.id_ville = v.id_ville
GROUP BY p.nom_pays;

-- ---------------------------------------------------------------------
-- V6. v_utilisateur_conferences
--     Conférences qui intéressent chaque utilisateur (requête 4).
--     On tient compte de la hiérarchie : un utilisateur intéressé par
--     "Spatial databases" est aussi intéressé par ses sous-thèmes
--     ("GIS", "R-tree indexing"...).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_utilisateur_conferences AS
WITH RECURSIVE interets(id_personne, id_theme, theme_profil) AS (
    -- thèmes déclarés dans le profil
    SELECT ut.id_personne, ut.id_theme, t.libelle
    FROM utilisateur_theme ut
    JOIN theme t ON t.id_theme = ut.id_theme
    UNION
    -- + tous leurs sous-thèmes, récursivement
    SELECT i.id_personne, t.id_theme, i.theme_profil
    FROM interets i
    JOIN theme t ON t.id_theme_parent = i.id_theme
)
SELECT DISTINCT
    u.id_personne,
    u.login,
    pe.nom,
    pe.prenom,
    ct.id_conf,
    ct.intitule,
    ct.date_debut,
    i.theme_profil,           -- le thème du profil qui a déclenché l'intérêt
    ct.theme AS theme_conference
FROM interets i
JOIN utilisateur         u  ON u.id_personne  = i.id_personne
JOIN personne            pe ON pe.id_personne = u.id_personne
JOIN v_conference_themes ct ON ct.id_theme    = i.id_theme;

-- ---------------------------------------------------------------------
-- V7. v_utilisateurs_responsables
--     Utilisateurs de la base qui ont aussi été responsables d'au moins
--     une conférence (requête 8). Grâce à l'héritage
--     UTILISATEUR -> PERSONNE, c'est une simple jointure sur id_personne.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_utilisateurs_responsables AS
SELECT
    u.id_personne,
    u.login,
    pr.nom,
    pr.prenom,
    pr.email,
    COUNT(DISTINCT pr.id_conf) AS nb_conferences,
    STRING_AGG(DISTINCT pr.role, ', ') AS roles
FROM utilisateur u
JOIN v_personnes_responsables pr ON pr.id_personne = u.id_personne
GROUP BY u.id_personne, u.login, pr.nom, pr.prenom, pr.email;

-- ---------------------------------------------------------------------
-- V8. v_specifications
--     Appels à communication : pour chaque conférence et chaque catégorie
--     de soumission, les consignes et les échéances. Utile pour l'interface.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_specifications AS
SELECT
    c.id_conf,
    c.intitule,
    cs.libelle AS categorie,
    sp.nb_pages_max,
    sp.police,
    sp.taille_police,
    sp.logiciel,
    sp.date_limite_soumission,
    sp.date_notification,
    sp.date_limite_version_finale,
    (sp.date_limite_soumission >= CURRENT_DATE) AS soumission_ouverte
FROM specification        sp
JOIN conference           c  ON c.id_conf       = sp.id_conf
JOIN categorie_soumission cs ON cs.id_categorie = sp.id_categorie;