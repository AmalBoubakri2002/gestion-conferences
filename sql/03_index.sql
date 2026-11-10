-- =====================================================================
--  MOD 11.1 - Projet 4 : Gestion des conférences
--  Fichier 03_index.sql : index d'optimisation
--  Prérequis : 01_create_tables.sql et 02_triggers.sql exécutés.
--
--  Rappel : PostgreSQL crée AUTOMATIQUEMENT un index pour chaque
--  PRIMARY KEY et chaque UNIQUE, mais PAS pour les clés étrangères.
--  On indexe donc ici :
--    (1) les clés étrangères (jointures + vérification des ON DELETE) ;
--    (2) les colonnes filtrées ou triées par les 9 requêtes du sujet ;
--    (3) les recherches par mot-clé (extension pg_trgm).
-- =====================================================================

SET search_path TO conferences, public;

-- ---------------------------------------------------------------------
-- (1) Index sur les clés étrangères
--     Une PK composée (a, b) n'est utilisable que pour une recherche
--     sur "a" ou "a + b" : on indexe donc les colonnes suivantes.
-- ---------------------------------------------------------------------

-- Géographie : requête 2 (conférences par pays)
CREATE INDEX idx_ville_pays            ON ville (id_pays);

-- Conférence -> ville / organisme / série / éditeur
CREATE INDEX idx_conference_ville      ON conference (id_ville);
CREATE INDEX idx_conference_organisme  ON conference (id_organisme);
CREATE INDEX idx_conference_serie      ON conference (id_serie);     -- requête 5 (série SDH)
CREATE INDEX idx_conference_editeur    ON conference (id_editeur);   -- requête 7 (éditeur donné)

-- Workshops d'une conférence donnée : requête 6
CREATE INDEX idx_workshop_mere         ON workshop (id_conf_mere);

-- responsable_de : PK (id_personne, id_conf, id_type)
CREATE INDEX idx_resp_conf             ON responsable_de (id_conf);
CREATE INDEX idx_resp_type             ON responsable_de (id_type);

-- membre_pc : PK (id_personne, id_conf)
CREATE INDEX idx_membre_pc_conf        ON membre_pc (id_conf);

-- evalue : PK (id_personne, id_conf, num_session)
CREATE INDEX idx_evalue_session        ON evalue (id_conf, num_session);

-- session_theme : PK (id_conf, num_session, id_theme) -> requêtes 3 et 4
CREATE INDEX idx_session_theme_theme   ON session_theme (id_theme);

-- utilisateur_theme : PK (id_personne, id_theme) -> requête 4
CREATE INDEX idx_util_theme_theme      ON utilisateur_theme (id_theme);

-- specification : PK (id_conf, id_categorie)
CREATE INDEX idx_specification_cat     ON specification (id_categorie);

-- Hiérarchie des thèmes : parcours récursif (requête 3, CI-4)
CREATE INDEX idx_theme_parent          ON theme (id_theme_parent);

-- ---------------------------------------------------------------------
-- (2) Index sur les colonnes de recherche des requêtes
-- ---------------------------------------------------------------------

-- Requête 1 : conférences de l'année courante.
-- La requête sera écrite sous forme d'intervalle :
--   WHERE date_debut >= date_trunc('year', CURRENT_DATE)
--     AND date_debut <  date_trunc('year', CURRENT_DATE) + INTERVAL '1 year'
-- pour que cet index B-tree soit utilisable (un EXTRACT(YEAR ...) ne l'utiliserait pas).
CREATE INDEX idx_conference_date_debut ON conference (date_debut);

-- Requête 9 : conférences dont le professeur "X" a été responsable.
-- Recherche par nom insensible à la casse : index sur expression.
CREATE INDEX idx_personne_nom_lower    ON personne (lower(nom), lower(prenom));

-- Remarque : personne.email, serie.sigle, pays.nom_pays, editeur.nom_editeur
-- sont déjà indexés grâce à leurs contraintes UNIQUE (01_create_tables.sql).

-- ---------------------------------------------------------------------
-- (3) Recherche par mot-clé (requête 3) : extension pg_trgm
--     Un B-tree ne sert pas pour ILIKE '%spatial%' (joker au début).
--     Un index GIN trigrammes, lui, accélère ce type de recherche.
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA public;

CREATE INDEX idx_theme_libelle_trgm
    ON theme USING GIN (libelle public.gin_trgm_ops);

CREATE INDEX idx_conference_intitule_trgm
    ON conference USING GIN (intitule public.gin_trgm_ops);

-- Mettre à jour les statistiques utilisées par l'optimiseur
ANALYZE;