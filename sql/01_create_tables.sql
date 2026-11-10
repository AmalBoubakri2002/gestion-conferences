-- =====================================================================
--  MOD 11.1 - Projet 4 : Gestion des conférences
--  Fichier 01_create_tables.sql : création des tables (DDL PostgreSQL)
--  Ordre de création : tables "référentiels" -> tables principales
--                      -> sous-types (héritage) -> tables de jointure
-- =====================================================================

-- Repartir d'un schéma propre (utile pendant le développement)
DROP SCHEMA IF EXISTS conferences CASCADE;
CREATE SCHEMA conferences;
SET search_path TO conferences;

-- ---------------------------------------------------------------------
-- 1. Référentiels géographiques
-- ---------------------------------------------------------------------
CREATE TABLE pays (
    id_pays      SERIAL       PRIMARY KEY,
    nom_pays     VARCHAR(100) NOT NULL,
    CONSTRAINT uq_pays_nom UNIQUE (nom_pays)                 -- id' : nom_pays
);

CREATE TABLE ville (
    id_ville     SERIAL       PRIMARY KEY,
    nom_ville    VARCHAR(100) NOT NULL,
    id_pays      INTEGER      NOT NULL,                      -- contient : VILLE 1-1
    CONSTRAINT fk_ville_pays FOREIGN KEY (id_pays)
        REFERENCES pays (id_pays) ON DELETE RESTRICT,        -- on ne supprime pas un pays qui a des villes
    CONSTRAINT uq_ville_nom_pays UNIQUE (nom_ville, id_pays) -- pas deux "Lyon" en France
);

-- ---------------------------------------------------------------------
-- 2. Référentiels liés à la conférence
-- ---------------------------------------------------------------------
CREATE TABLE organisme (
    id_organisme  SERIAL       PRIMARY KEY,
    nom           VARCHAR(200) NOT NULL,
    adresse       VARCHAR(300) NOT NULL,
    email_contact VARCHAR(150) NOT NULL,
    CONSTRAINT ck_organisme_email CHECK (email_contact ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

CREATE TABLE serie (
    id_serie   SERIAL       PRIMARY KEY,
    sigle      VARCHAR(20)  NOT NULL,
    nom_serie  VARCHAR(200) NOT NULL,
    CONSTRAINT uq_serie_sigle UNIQUE (sigle)                 -- id' : sigle (ex : SDH)
);

CREATE TABLE editeur (
    id_editeur   SERIAL       PRIMARY KEY,
    nom_editeur  VARCHAR(150) NOT NULL,
    CONSTRAINT uq_editeur_nom UNIQUE (nom_editeur)
);

CREATE TABLE type_responsabilite (
    id_type  SERIAL       PRIMARY KEY,
    libelle  VARCHAR(100) NOT NULL,
    CONSTRAINT uq_type_resp_libelle UNIQUE (libelle)         -- "General chair", ...
);

CREATE TABLE categorie_soumission (
    id_categorie  SERIAL       PRIMARY KEY,
    libelle       VARCHAR(100) NOT NULL,
    CONSTRAINT uq_categorie_libelle UNIQUE (libelle)         -- "Regular paper", ...
);

-- Thèmes de recherche, hiérarchisés (association réflexive sous_theme_de)
CREATE TABLE theme (
    id_theme         SERIAL       PRIMARY KEY,
    libelle          VARCHAR(150) NOT NULL,
    id_theme_parent  INTEGER      NULL,                      -- 0-1 : un thème racine n'a pas de parent
    CONSTRAINT uq_theme_libelle UNIQUE (libelle),
    CONSTRAINT fk_theme_parent FOREIGN KEY (id_theme_parent)
        REFERENCES theme (id_theme) ON DELETE SET NULL,      -- si le parent disparaît, le thème devient racine
    CONSTRAINT ck_theme_pas_son_parent CHECK (id_theme_parent IS NULL OR id_theme_parent <> id_theme)
);

-- ---------------------------------------------------------------------
-- 3. Conférence
-- ---------------------------------------------------------------------
CREATE TABLE conference (
    id_conf            SERIAL       PRIMARY KEY,
    intitule           VARCHAR(300) NOT NULL,
    date_debut         DATE         NOT NULL,
    date_fin           DATE         NOT NULL,
    texte_introductif  TEXT         NOT NULL,
    id_ville           INTEGER      NOT NULL,                -- accueille  : CONF 1-1
    id_organisme       INTEGER      NOT NULL,                -- organise   : CONF 1-1
    id_serie           INTEGER      NULL,                    -- regroupe   : CONF 0-1
    id_editeur         INTEGER      NULL,                    -- publie_actes : CONF 0-1
    CONSTRAINT ck_conf_dates CHECK (date_debut <= date_fin),
    CONSTRAINT fk_conf_ville FOREIGN KEY (id_ville)
        REFERENCES ville (id_ville) ON DELETE RESTRICT,
    CONSTRAINT fk_conf_organisme FOREIGN KEY (id_organisme)
        REFERENCES organisme (id_organisme) ON DELETE RESTRICT,
    CONSTRAINT fk_conf_serie FOREIGN KEY (id_serie)
        REFERENCES serie (id_serie) ON DELETE SET NULL,      -- la conférence existe sans sa série
    CONSTRAINT fk_conf_editeur FOREIGN KEY (id_editeur)
        REFERENCES editeur (id_editeur) ON DELETE SET NULL
);

-- Sous-type WORKSHOP (héritage : une table par sous-type)
CREATE TABLE workshop (
    id_conf       INTEGER PRIMARY KEY,                       -- même clé que la conférence
    id_conf_mere  INTEGER NOT NULL,                          -- est_rattache_a : WORKSHOP 1-1
    CONSTRAINT fk_workshop_conf FOREIGN KEY (id_conf)
        REFERENCES conference (id_conf) ON DELETE CASCADE,
    CONSTRAINT fk_workshop_mere FOREIGN KEY (id_conf_mere)
        REFERENCES conference (id_conf) ON DELETE CASCADE,   -- supprimer la conf. supprime le lien
    CONSTRAINT ck_workshop_pas_sa_mere CHECK (id_conf <> id_conf_mere)
);

-- ---------------------------------------------------------------------
-- 4. Personnes et utilisateurs
-- ---------------------------------------------------------------------
CREATE TABLE personne (
    id_personne  SERIAL       PRIMARY KEY,
    nom          VARCHAR(100) NOT NULL,
    prenom       VARCHAR(100) NOT NULL,
    adresse_pro  VARCHAR(300) NULL,                          -- [0-1] : un simple utilisateur peut ne pas l'avoir
    email        VARCHAR(150) NOT NULL,
    CONSTRAINT uq_personne_email UNIQUE (email),             -- id' : email
    CONSTRAINT ck_personne_email CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

-- Sous-type UTILISATEUR
CREATE TABLE utilisateur (
    id_personne   INTEGER      PRIMARY KEY,
    login         VARCHAR(50)  NOT NULL,
    mot_de_passe  VARCHAR(255) NOT NULL,                     -- stocké hashé (bcrypt), jamais en clair
    role          VARCHAR(20)  NOT NULL DEFAULT 'utilisateur',
    CONSTRAINT fk_utilisateur_personne FOREIGN KEY (id_personne)
        REFERENCES personne (id_personne) ON DELETE CASCADE,
    CONSTRAINT uq_utilisateur_login UNIQUE (login),
    CONSTRAINT ck_utilisateur_role CHECK (role IN ('admin', 'utilisateur'))
);

-- ---------------------------------------------------------------------
-- 5. Session (entité faible de CONFERENCE)
-- ---------------------------------------------------------------------
CREATE TABLE session (
    id_conf           INTEGER      NOT NULL,
    num_session       SMALLINT     NOT NULL,
    intitule_session  VARCHAR(300) NOT NULL,
    CONSTRAINT pk_session PRIMARY KEY (id_conf, num_session),
    CONSTRAINT fk_session_conf FOREIGN KEY (id_conf)
        REFERENCES conference (id_conf) ON DELETE CASCADE,   -- entité faible : disparaît avec sa conférence
    CONSTRAINT ck_session_num CHECK (num_session > 0)
);

-- ---------------------------------------------------------------------
-- 6. Tables de jointure (associations N-N)
-- ---------------------------------------------------------------------

-- responsable_de : association ternaire PERSONNE - CONFERENCE - TYPE
CREATE TABLE responsable_de (
    id_personne  INTEGER NOT NULL,
    id_conf      INTEGER NOT NULL,
    id_type      INTEGER NOT NULL,
    CONSTRAINT pk_responsable_de PRIMARY KEY (id_personne, id_conf, id_type),
    CONSTRAINT fk_resp_personne FOREIGN KEY (id_personne)
        REFERENCES personne (id_personne) ON DELETE RESTRICT, -- on garde l'historique des responsables
    CONSTRAINT fk_resp_conf FOREIGN KEY (id_conf)
        REFERENCES conference (id_conf) ON DELETE CASCADE,
    CONSTRAINT fk_resp_type FOREIGN KEY (id_type)
        REFERENCES type_responsabilite (id_type) ON DELETE RESTRICT
);

-- membre_comite_prog : PERSONNE - CONFERENCE
CREATE TABLE membre_pc (
    id_personne  INTEGER NOT NULL,
    id_conf      INTEGER NOT NULL,
    CONSTRAINT pk_membre_pc PRIMARY KEY (id_personne, id_conf),
    CONSTRAINT fk_pc_personne FOREIGN KEY (id_personne)
        REFERENCES personne (id_personne) ON DELETE RESTRICT,
    CONSTRAINT fk_pc_conf FOREIGN KEY (id_conf)
        REFERENCES conference (id_conf) ON DELETE CASCADE
);

-- evalue : PERSONNE - SESSION (FK composée vers session)
CREATE TABLE evalue (
    id_personne  INTEGER  NOT NULL,
    id_conf      INTEGER  NOT NULL,
    num_session  SMALLINT NOT NULL,
    CONSTRAINT pk_evalue PRIMARY KEY (id_personne, id_conf, num_session),
    CONSTRAINT fk_evalue_personne FOREIGN KEY (id_personne)
        REFERENCES personne (id_personne) ON DELETE RESTRICT,
    CONSTRAINT fk_evalue_session FOREIGN KEY (id_conf, num_session)
        REFERENCES session (id_conf, num_session) ON DELETE CASCADE
);

-- porte_sur : SESSION - THEME
CREATE TABLE session_theme (
    id_conf      INTEGER  NOT NULL,
    num_session  SMALLINT NOT NULL,
    id_theme     INTEGER  NOT NULL,
    CONSTRAINT pk_session_theme PRIMARY KEY (id_conf, num_session, id_theme),
    CONSTRAINT fk_st_session FOREIGN KEY (id_conf, num_session)
        REFERENCES session (id_conf, num_session) ON DELETE CASCADE,
    CONSTRAINT fk_st_theme FOREIGN KEY (id_theme)
        REFERENCES theme (id_theme) ON DELETE RESTRICT
);

-- interesse : UTILISATEUR - THEME (profil de l'utilisateur)
CREATE TABLE utilisateur_theme (
    id_personne  INTEGER NOT NULL,
    id_theme     INTEGER NOT NULL,
    CONSTRAINT pk_utilisateur_theme PRIMARY KEY (id_personne, id_theme),
    CONSTRAINT fk_ut_utilisateur FOREIGN KEY (id_personne)
        REFERENCES utilisateur (id_personne) ON DELETE CASCADE,
    CONSTRAINT fk_ut_theme FOREIGN KEY (id_theme)
        REFERENCES theme (id_theme) ON DELETE CASCADE
);

-- specifie : CONFERENCE - CATEGORIE_SOUMISSION (association porteuse d'attributs)
CREATE TABLE specification (
    id_conf                     INTEGER      NOT NULL,
    id_categorie                INTEGER      NOT NULL,
    nb_pages_max                SMALLINT     NULL,           -- NULL pour tutorial, panel, workshop
    police                      VARCHAR(50)  NULL,
    taille_police               SMALLINT     NULL,
    logiciel                    VARCHAR(50)  NULL,           -- ex : LaTeX, Word
    date_limite_soumission      DATE         NOT NULL,
    date_notification           DATE         NOT NULL,
    date_limite_version_finale  DATE         NOT NULL,
    CONSTRAINT pk_specification PRIMARY KEY (id_conf, id_categorie),
    CONSTRAINT fk_spec_conf FOREIGN KEY (id_conf)
        REFERENCES conference (id_conf) ON DELETE CASCADE,
    CONSTRAINT fk_spec_categorie FOREIGN KEY (id_categorie)
        REFERENCES categorie_soumission (id_categorie) ON DELETE RESTRICT,
    CONSTRAINT ck_spec_pages  CHECK (nb_pages_max IS NULL OR nb_pages_max > 0),
    CONSTRAINT ck_spec_taille CHECK (taille_police IS NULL OR taille_police BETWEEN 6 AND 20),
    CONSTRAINT ck_spec_dates  CHECK (date_limite_soumission < date_notification
                                     AND date_notification < date_limite_version_finale)
);