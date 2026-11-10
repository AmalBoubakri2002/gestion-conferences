--
-- PostgreSQL database dump
--

\restrict TjpiTHYxsoBows22xMMtN2cSak6Yz5FQoDRLhUmqbQpG0bTiwyLCxh7H2rl6Ya4

-- Dumped from database version 17.11 (Homebrew)
-- Dumped by pg_dump version 17.11 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: conferences; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA conferences;


--
-- Name: fn_check_evaluateur_membre_pc(); Type: FUNCTION; Schema: conferences; Owner: -
--

CREATE FUNCTION conferences.fn_check_evaluateur_membre_pc() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM membre_pc m
        WHERE m.id_personne = NEW.id_personne
          AND m.id_conf     = NEW.id_conf
    ) THEN
        RAISE EXCEPTION
            'CI-1 : la personne % ne peut pas évaluer la session % de la conférence % : elle n''est pas membre du comité de programme.',
            NEW.id_personne, NEW.num_session, NEW.id_conf;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: fn_check_retrait_membre_pc(); Type: FUNCTION; Schema: conferences; Owner: -
--

CREATE FUNCTION conferences.fn_check_retrait_membre_pc() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Si la conférence elle-même est en cours de suppression (CASCADE),
    -- les évaluations disparaissent aussi : on laisse passer.
    IF NOT EXISTS (SELECT 1 FROM conference WHERE id_conf = OLD.id_conf) THEN
        RETURN OLD;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM evalue e
        WHERE e.id_personne = OLD.id_personne
          AND e.id_conf     = OLD.id_conf
    ) THEN
        RAISE EXCEPTION
            'CI-1 : impossible de retirer la personne % du comité de programme de la conférence % : elle évalue encore des sessions.',
            OLD.id_personne, OLD.id_conf;
    END IF;
    RETURN OLD;
END;
$$;


--
-- Name: fn_check_specification_dates(); Type: FUNCTION; Schema: conferences; Owner: -
--

CREATE FUNCTION conferences.fn_check_specification_dates() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_debut DATE;
BEGIN
    SELECT date_debut INTO v_debut FROM conference WHERE id_conf = NEW.id_conf;

    IF NEW.date_limite_version_finale >= v_debut THEN
        RAISE EXCEPTION
            'CI-3 : la date limite de version finale (%) doit précéder le début de la conférence % (%).',
            NEW.date_limite_version_finale, NEW.id_conf, v_debut;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: fn_check_theme_cycle(); Type: FUNCTION; Schema: conferences; Owner: -
--

CREATE FUNCTION conferences.fn_check_theme_cycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.id_theme_parent IS NULL THEN
        RETURN NEW;
    END IF;

    -- On remonte la chaîne des parents à partir du nouveau parent :
    -- si on retombe sur le thème lui-même, il y a un cycle.
    IF EXISTS (
        WITH RECURSIVE ancetres(id_theme) AS (
            SELECT NEW.id_theme_parent
            UNION
            SELECT t.id_theme_parent
            FROM theme t
            JOIN ancetres a ON t.id_theme = a.id_theme
            WHERE t.id_theme_parent IS NOT NULL
        )
        SELECT 1 FROM ancetres WHERE id_theme = NEW.id_theme
    ) THEN
        RAISE EXCEPTION
            'CI-4 : rattacher le thème % au parent % créerait un cycle dans la hiérarchie des thèmes.',
            NEW.id_theme, NEW.id_theme_parent;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: fn_check_workshop(); Type: FUNCTION; Schema: conferences; Owner: -
--

CREATE FUNCTION conferences.fn_check_workshop() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_ws    conference%ROWTYPE;   -- le workshop
    v_mere  conference%ROWTYPE;   -- la conférence mère
BEGIN
    -- a) la mère ne doit pas être un workshop
    IF EXISTS (SELECT 1 FROM workshop WHERE id_conf = NEW.id_conf_mere) THEN
        RAISE EXCEPTION
            'CI-2a : la conférence % est un workshop, elle ne peut pas être conférence mère.',
            NEW.id_conf_mere;
    END IF;

    -- b) le futur workshop ne doit pas déjà être mère d'autres workshops
    IF EXISTS (SELECT 1 FROM workshop WHERE id_conf_mere = NEW.id_conf) THEN
        RAISE EXCEPTION
            'CI-2b : la conférence % a déjà des workshops rattachés, elle ne peut pas devenir un workshop.',
            NEW.id_conf;
    END IF;

    -- c) proximité des dates (fenêtre de 7 jours autour de la conférence mère)
    SELECT * INTO v_ws   FROM conference WHERE id_conf = NEW.id_conf;
    SELECT * INTO v_mere FROM conference WHERE id_conf = NEW.id_conf_mere;

    IF v_ws.date_debut < v_mere.date_debut - 7
       OR v_ws.date_fin > v_mere.date_fin + 7 THEN
        RAISE EXCEPTION
            'CI-2c : le workshop % (du % au %) doit avoir lieu au plus 7 jours avant/après la conférence % (du % au %).',
            NEW.id_conf, v_ws.date_debut, v_ws.date_fin,
            NEW.id_conf_mere, v_mere.date_debut, v_mere.date_fin;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: fn_themes_descendants(text); Type: FUNCTION; Schema: conferences; Owner: -
--

CREATE FUNCTION conferences.fn_themes_descendants(p_mot_cle text) RETURNS TABLE(id_theme integer, libelle character varying)
    LANGUAGE sql STABLE
    AS $$
    WITH RECURSIVE descendants AS (
        -- point de départ : les thèmes dont le libellé contient le mot-clé
        SELECT t.id_theme, t.libelle
        FROM theme t
        WHERE t.libelle ILIKE '%' || p_mot_cle || '%'
        UNION
        -- puis, récursivement, leurs sous-thèmes
        SELECT t.id_theme, t.libelle
        FROM theme t
        JOIN descendants d ON t.id_theme_parent = d.id_theme
    )
    SELECT id_theme, libelle FROM descendants;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: categorie_soumission; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.categorie_soumission (
    id_categorie integer NOT NULL,
    libelle character varying(100) NOT NULL
);


--
-- Name: categorie_soumission_id_categorie_seq; Type: SEQUENCE; Schema: conferences; Owner: -
--

CREATE SEQUENCE conferences.categorie_soumission_id_categorie_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: categorie_soumission_id_categorie_seq; Type: SEQUENCE OWNED BY; Schema: conferences; Owner: -
--

ALTER SEQUENCE conferences.categorie_soumission_id_categorie_seq OWNED BY conferences.categorie_soumission.id_categorie;


--
-- Name: conference; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.conference (
    id_conf integer NOT NULL,
    intitule character varying(300) NOT NULL,
    date_debut date NOT NULL,
    date_fin date NOT NULL,
    texte_introductif text NOT NULL,
    id_ville integer NOT NULL,
    id_organisme integer NOT NULL,
    id_serie integer,
    id_editeur integer,
    CONSTRAINT ck_conf_dates CHECK ((date_debut <= date_fin))
);


--
-- Name: conference_id_conf_seq; Type: SEQUENCE; Schema: conferences; Owner: -
--

CREATE SEQUENCE conferences.conference_id_conf_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: conference_id_conf_seq; Type: SEQUENCE OWNED BY; Schema: conferences; Owner: -
--

ALTER SEQUENCE conferences.conference_id_conf_seq OWNED BY conferences.conference.id_conf;


--
-- Name: editeur; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.editeur (
    id_editeur integer NOT NULL,
    nom_editeur character varying(150) NOT NULL
);


--
-- Name: editeur_id_editeur_seq; Type: SEQUENCE; Schema: conferences; Owner: -
--

CREATE SEQUENCE conferences.editeur_id_editeur_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: editeur_id_editeur_seq; Type: SEQUENCE OWNED BY; Schema: conferences; Owner: -
--

ALTER SEQUENCE conferences.editeur_id_editeur_seq OWNED BY conferences.editeur.id_editeur;


--
-- Name: evalue; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.evalue (
    id_personne integer NOT NULL,
    id_conf integer NOT NULL,
    num_session smallint NOT NULL
);


--
-- Name: membre_pc; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.membre_pc (
    id_personne integer NOT NULL,
    id_conf integer NOT NULL
);


--
-- Name: organisme; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.organisme (
    id_organisme integer NOT NULL,
    nom character varying(200) NOT NULL,
    adresse character varying(300) NOT NULL,
    email_contact character varying(150) NOT NULL,
    CONSTRAINT ck_organisme_email CHECK (((email_contact)::text ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text))
);


--
-- Name: organisme_id_organisme_seq; Type: SEQUENCE; Schema: conferences; Owner: -
--

CREATE SEQUENCE conferences.organisme_id_organisme_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organisme_id_organisme_seq; Type: SEQUENCE OWNED BY; Schema: conferences; Owner: -
--

ALTER SEQUENCE conferences.organisme_id_organisme_seq OWNED BY conferences.organisme.id_organisme;


--
-- Name: pays; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.pays (
    id_pays integer NOT NULL,
    nom_pays character varying(100) NOT NULL
);


--
-- Name: pays_id_pays_seq; Type: SEQUENCE; Schema: conferences; Owner: -
--

CREATE SEQUENCE conferences.pays_id_pays_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pays_id_pays_seq; Type: SEQUENCE OWNED BY; Schema: conferences; Owner: -
--

ALTER SEQUENCE conferences.pays_id_pays_seq OWNED BY conferences.pays.id_pays;


--
-- Name: personne; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.personne (
    id_personne integer NOT NULL,
    nom character varying(100) NOT NULL,
    prenom character varying(100) NOT NULL,
    adresse_pro character varying(300),
    email character varying(150) NOT NULL,
    CONSTRAINT ck_personne_email CHECK (((email)::text ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text))
);


--
-- Name: personne_id_personne_seq; Type: SEQUENCE; Schema: conferences; Owner: -
--

CREATE SEQUENCE conferences.personne_id_personne_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: personne_id_personne_seq; Type: SEQUENCE OWNED BY; Schema: conferences; Owner: -
--

ALTER SEQUENCE conferences.personne_id_personne_seq OWNED BY conferences.personne.id_personne;


--
-- Name: responsable_de; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.responsable_de (
    id_personne integer NOT NULL,
    id_conf integer NOT NULL,
    id_type integer NOT NULL
);


--
-- Name: serie; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.serie (
    id_serie integer NOT NULL,
    sigle character varying(20) NOT NULL,
    nom_serie character varying(200) NOT NULL
);


--
-- Name: serie_id_serie_seq; Type: SEQUENCE; Schema: conferences; Owner: -
--

CREATE SEQUENCE conferences.serie_id_serie_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: serie_id_serie_seq; Type: SEQUENCE OWNED BY; Schema: conferences; Owner: -
--

ALTER SEQUENCE conferences.serie_id_serie_seq OWNED BY conferences.serie.id_serie;


--
-- Name: session; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.session (
    id_conf integer NOT NULL,
    num_session smallint NOT NULL,
    intitule_session character varying(300) NOT NULL,
    CONSTRAINT ck_session_num CHECK ((num_session > 0))
);


--
-- Name: session_theme; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.session_theme (
    id_conf integer NOT NULL,
    num_session smallint NOT NULL,
    id_theme integer NOT NULL
);


--
-- Name: specification; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.specification (
    id_conf integer NOT NULL,
    id_categorie integer NOT NULL,
    nb_pages_max smallint,
    police character varying(50),
    taille_police smallint,
    logiciel character varying(50),
    date_limite_soumission date NOT NULL,
    date_notification date NOT NULL,
    date_limite_version_finale date NOT NULL,
    CONSTRAINT ck_spec_dates CHECK (((date_limite_soumission < date_notification) AND (date_notification < date_limite_version_finale))),
    CONSTRAINT ck_spec_pages CHECK (((nb_pages_max IS NULL) OR (nb_pages_max > 0))),
    CONSTRAINT ck_spec_taille CHECK (((taille_police IS NULL) OR ((taille_police >= 6) AND (taille_police <= 20))))
);


--
-- Name: theme; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.theme (
    id_theme integer NOT NULL,
    libelle character varying(150) NOT NULL,
    id_theme_parent integer,
    CONSTRAINT ck_theme_pas_son_parent CHECK (((id_theme_parent IS NULL) OR (id_theme_parent <> id_theme)))
);


--
-- Name: theme_id_theme_seq; Type: SEQUENCE; Schema: conferences; Owner: -
--

CREATE SEQUENCE conferences.theme_id_theme_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: theme_id_theme_seq; Type: SEQUENCE OWNED BY; Schema: conferences; Owner: -
--

ALTER SEQUENCE conferences.theme_id_theme_seq OWNED BY conferences.theme.id_theme;


--
-- Name: type_responsabilite; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.type_responsabilite (
    id_type integer NOT NULL,
    libelle character varying(100) NOT NULL
);


--
-- Name: type_responsabilite_id_type_seq; Type: SEQUENCE; Schema: conferences; Owner: -
--

CREATE SEQUENCE conferences.type_responsabilite_id_type_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: type_responsabilite_id_type_seq; Type: SEQUENCE OWNED BY; Schema: conferences; Owner: -
--

ALTER SEQUENCE conferences.type_responsabilite_id_type_seq OWNED BY conferences.type_responsabilite.id_type;


--
-- Name: utilisateur; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.utilisateur (
    id_personne integer NOT NULL,
    login character varying(50) NOT NULL,
    mot_de_passe character varying(255) NOT NULL,
    role character varying(20) DEFAULT 'utilisateur'::character varying NOT NULL,
    CONSTRAINT ck_utilisateur_role CHECK (((role)::text = ANY ((ARRAY['admin'::character varying, 'utilisateur'::character varying])::text[])))
);


--
-- Name: utilisateur_theme; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.utilisateur_theme (
    id_personne integer NOT NULL,
    id_theme integer NOT NULL
);


--
-- Name: ville; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.ville (
    id_ville integer NOT NULL,
    nom_ville character varying(100) NOT NULL,
    id_pays integer NOT NULL
);


--
-- Name: workshop; Type: TABLE; Schema: conferences; Owner: -
--

CREATE TABLE conferences.workshop (
    id_conf integer NOT NULL,
    id_conf_mere integer NOT NULL,
    CONSTRAINT ck_workshop_pas_sa_mere CHECK ((id_conf <> id_conf_mere))
);


--
-- Name: v_conference_complete; Type: VIEW; Schema: conferences; Owner: -
--

CREATE VIEW conferences.v_conference_complete AS
 SELECT c.id_conf,
    c.intitule,
    c.date_debut,
    c.date_fin,
    c.texte_introductif,
    v.id_ville,
    v.nom_ville,
    p.id_pays,
    p.nom_pays,
    o.id_organisme,
    o.nom AS organisme,
    o.email_contact AS organisme_email,
    s.id_serie,
    s.sigle AS serie_sigle,
    s.nom_serie,
    e.id_editeur,
    e.nom_editeur,
    (w.id_conf IS NOT NULL) AS est_workshop,
    w.id_conf_mere
   FROM ((((((conferences.conference c
     JOIN conferences.ville v ON ((v.id_ville = c.id_ville)))
     JOIN conferences.pays p ON ((p.id_pays = v.id_pays)))
     JOIN conferences.organisme o ON ((o.id_organisme = c.id_organisme)))
     LEFT JOIN conferences.serie s ON ((s.id_serie = c.id_serie)))
     LEFT JOIN conferences.editeur e ON ((e.id_editeur = c.id_editeur)))
     LEFT JOIN conferences.workshop w ON ((w.id_conf = c.id_conf)));


--
-- Name: v_conference_themes; Type: VIEW; Schema: conferences; Owner: -
--

CREATE VIEW conferences.v_conference_themes AS
 SELECT DISTINCT c.id_conf,
    c.intitule,
    c.date_debut,
    t.id_theme,
    t.libelle AS theme
   FROM ((conferences.conference c
     JOIN conferences.session_theme st ON ((st.id_conf = c.id_conf)))
     JOIN conferences.theme t ON ((t.id_theme = st.id_theme)));


--
-- Name: v_conferences_par_pays; Type: VIEW; Schema: conferences; Owner: -
--

CREATE VIEW conferences.v_conferences_par_pays AS
 SELECT p.nom_pays,
    count(c.id_conf) AS nb_conferences,
    string_agg((c.intitule)::text, ' ; '::text ORDER BY c.date_debut) AS conferences
   FROM ((conferences.pays p
     JOIN conferences.ville v ON ((v.id_pays = p.id_pays)))
     JOIN conferences.conference c ON ((c.id_ville = v.id_ville)))
  GROUP BY p.nom_pays;


--
-- Name: v_personnes_responsables; Type: VIEW; Schema: conferences; Owner: -
--

CREATE VIEW conferences.v_personnes_responsables AS
 SELECT pe.id_personne,
    pe.nom,
    pe.prenom,
    pe.email,
    c.id_conf,
    c.intitule,
    c.date_debut,
    tr.libelle AS role
   FROM (((conferences.responsable_de r
     JOIN conferences.personne pe ON ((pe.id_personne = r.id_personne)))
     JOIN conferences.conference c ON ((c.id_conf = r.id_conf)))
     JOIN conferences.type_responsabilite tr ON ((tr.id_type = r.id_type)))
UNION
 SELECT pe.id_personne,
    pe.nom,
    pe.prenom,
    pe.email,
    c.id_conf,
    c.intitule,
    c.date_debut,
    'Program Committee member'::character varying AS role
   FROM ((conferences.membre_pc m
     JOIN conferences.personne pe ON ((pe.id_personne = m.id_personne)))
     JOIN conferences.conference c ON ((c.id_conf = m.id_conf)));


--
-- Name: v_specifications; Type: VIEW; Schema: conferences; Owner: -
--

CREATE VIEW conferences.v_specifications AS
 SELECT c.id_conf,
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
   FROM ((conferences.specification sp
     JOIN conferences.conference c ON ((c.id_conf = sp.id_conf)))
     JOIN conferences.categorie_soumission cs ON ((cs.id_categorie = sp.id_categorie)));


--
-- Name: v_utilisateur_conferences; Type: VIEW; Schema: conferences; Owner: -
--

CREATE VIEW conferences.v_utilisateur_conferences AS
 WITH RECURSIVE interets(id_personne, id_theme, theme_profil) AS (
         SELECT ut.id_personne,
            ut.id_theme,
            t.libelle
           FROM (conferences.utilisateur_theme ut
             JOIN conferences.theme t ON ((t.id_theme = ut.id_theme)))
        UNION
         SELECT i_1.id_personne,
            t.id_theme,
            i_1.theme_profil
           FROM (interets i_1
             JOIN conferences.theme t ON ((t.id_theme_parent = i_1.id_theme)))
        )
 SELECT DISTINCT u.id_personne,
    u.login,
    pe.nom,
    pe.prenom,
    ct.id_conf,
    ct.intitule,
    ct.date_debut,
    i.theme_profil,
    ct.theme AS theme_conference
   FROM (((interets i
     JOIN conferences.utilisateur u ON ((u.id_personne = i.id_personne)))
     JOIN conferences.personne pe ON ((pe.id_personne = u.id_personne)))
     JOIN conferences.v_conference_themes ct ON ((ct.id_theme = i.id_theme)));


--
-- Name: v_utilisateurs_responsables; Type: VIEW; Schema: conferences; Owner: -
--

CREATE VIEW conferences.v_utilisateurs_responsables AS
 SELECT u.id_personne,
    u.login,
    pr.nom,
    pr.prenom,
    pr.email,
    count(DISTINCT pr.id_conf) AS nb_conferences,
    string_agg(DISTINCT (pr.role)::text, ', '::text) AS roles
   FROM (conferences.utilisateur u
     JOIN conferences.v_personnes_responsables pr ON ((pr.id_personne = u.id_personne)))
  GROUP BY u.id_personne, u.login, pr.nom, pr.prenom, pr.email;


--
-- Name: v_workshops; Type: VIEW; Schema: conferences; Owner: -
--

CREATE VIEW conferences.v_workshops AS
 SELECT w.id_conf AS id_workshop,
    cw.intitule AS workshop,
    cw.date_debut AS workshop_debut,
    cw.date_fin AS workshop_fin,
    w.id_conf_mere,
    cm.intitule AS conference_mere,
    cm.date_debut AS conference_debut,
    cm.date_fin AS conference_fin
   FROM ((conferences.workshop w
     JOIN conferences.conference cw ON ((cw.id_conf = w.id_conf)))
     JOIN conferences.conference cm ON ((cm.id_conf = w.id_conf_mere)));


--
-- Name: ville_id_ville_seq; Type: SEQUENCE; Schema: conferences; Owner: -
--

CREATE SEQUENCE conferences.ville_id_ville_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ville_id_ville_seq; Type: SEQUENCE OWNED BY; Schema: conferences; Owner: -
--

ALTER SEQUENCE conferences.ville_id_ville_seq OWNED BY conferences.ville.id_ville;


--
-- Name: categorie_soumission id_categorie; Type: DEFAULT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.categorie_soumission ALTER COLUMN id_categorie SET DEFAULT nextval('conferences.categorie_soumission_id_categorie_seq'::regclass);


--
-- Name: conference id_conf; Type: DEFAULT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.conference ALTER COLUMN id_conf SET DEFAULT nextval('conferences.conference_id_conf_seq'::regclass);


--
-- Name: editeur id_editeur; Type: DEFAULT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.editeur ALTER COLUMN id_editeur SET DEFAULT nextval('conferences.editeur_id_editeur_seq'::regclass);


--
-- Name: organisme id_organisme; Type: DEFAULT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.organisme ALTER COLUMN id_organisme SET DEFAULT nextval('conferences.organisme_id_organisme_seq'::regclass);


--
-- Name: pays id_pays; Type: DEFAULT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.pays ALTER COLUMN id_pays SET DEFAULT nextval('conferences.pays_id_pays_seq'::regclass);


--
-- Name: personne id_personne; Type: DEFAULT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.personne ALTER COLUMN id_personne SET DEFAULT nextval('conferences.personne_id_personne_seq'::regclass);


--
-- Name: serie id_serie; Type: DEFAULT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.serie ALTER COLUMN id_serie SET DEFAULT nextval('conferences.serie_id_serie_seq'::regclass);


--
-- Name: theme id_theme; Type: DEFAULT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.theme ALTER COLUMN id_theme SET DEFAULT nextval('conferences.theme_id_theme_seq'::regclass);


--
-- Name: type_responsabilite id_type; Type: DEFAULT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.type_responsabilite ALTER COLUMN id_type SET DEFAULT nextval('conferences.type_responsabilite_id_type_seq'::regclass);


--
-- Name: ville id_ville; Type: DEFAULT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.ville ALTER COLUMN id_ville SET DEFAULT nextval('conferences.ville_id_ville_seq'::regclass);


--
-- Data for Name: categorie_soumission; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.categorie_soumission (id_categorie, libelle) FROM stdin;
1	Regular paper
2	Short paper
3	Panel
4	Tutorial
5	Industrial development
6	System description
7	Poster
8	Workshop proposal
9	Demo
\.


--
-- Data for Name: conference; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.conference (id_conf, intitule, date_debut, date_fin, texte_introductif, id_ville, id_organisme, id_serie, id_editeur) FROM stdin;
1	SDH 2020 – Spatial Data Handling	2020-08-27	2020-08-29	The 2020 edition of the International Symposium on Spatial Data Handling brings together researchers in GIScience and spatial databases.	3	5	1	2
2	SDH 2021 – Spatial Data Handling	2021-04-24	2021-04-26	The 2021 edition of the International Symposium on Spatial Data Handling brings together researchers in GIScience and spatial databases.	1	2	1	2
3	SDH 2022 – Spatial Data Handling	2022-08-03	2022-08-05	The 2022 edition of the International Symposium on Spatial Data Handling brings together researchers in GIScience and spatial databases.	12	11	1	1
4	SDH 2023 – Spatial Data Handling	2023-09-10	2023-09-12	The 2023 edition of the International Symposium on Spatial Data Handling brings together researchers in GIScience and spatial databases.	12	11	1	2
5	SDH 2024 – Spatial Data Handling	2024-08-02	2024-08-04	The 2024 edition of the International Symposium on Spatial Data Handling brings together researchers in GIScience and spatial databases.	9	9	1	2
6	SDH 2025 – Spatial Data Handling	2025-05-30	2025-06-01	The 2025 edition of the International Symposium on Spatial Data Handling brings together researchers in GIScience and spatial databases.	40	27	1	1
7	SDH 2026 – Spatial Data Handling	2026-09-18	2026-09-20	The 2026 edition of the International Symposium on Spatial Data Handling brings together researchers in GIScience and spatial databases.	1	1	1	1
8	SDH 2027 – Spatial Data Handling	2027-07-19	2027-07-21	The 2027 edition of the International Symposium on Spatial Data Handling brings together researchers in GIScience and spatial databases.	7	8	1	1
9	CAISE 2026	2026-02-10	2026-02-11	Décrire réveiller résister figure nom que. Blanc cesser jardin dehors silence droit sortir. Devoir accent quelque accomplir main lutter. Perdu porter enfoncer exprimer choix pénétrer. Dimanche mari mois or voler.	26	20	2	2
10	EDBT 2026	2026-11-05	2026-11-07	Nemico no concedere noi madre voi. Fiume proporre ragazza soltanto politica religioso istituto. Bianco mente roba scegliere.	8	6	7	3
11	DEXA 2026	2026-06-29	2026-06-30	Razón ayuda película distintos. Particular siendo tiene países otros esta campo.	25	19	6	4
12	Forum on Data and Knowledge Engineering 2026	2026-02-28	2026-03-04	Effetto vario articolo risposta comune mano accorgersi. Economico ammazzare osservare mettere dente compagnia ampio. Più vi azzurro dove grosso. Idea controllo affare promettere tempo neanche. Tavolo fondo vario dove palazzo contenere toccare.	7	8	\N	\N
13	European Days on Knowledge Management 2026	2026-11-24	2026-11-25	Pueden control estudios jefe buena. Precio instituto junio aspectos.	38	26	\N	2
14	Forum on GIScience 2026	2026-10-07	2026-10-09	Piel contrario cierta alrededor rosa etc. Aun pregunta resultados problemas vista expresión nadie. Felipe barcelona m menor habrá.	40	27	\N	8
15	European Days on Temporal Reasoning 2026	2026-04-09	2026-04-12	Boden schaffen traurig Berg wieder. Gerade etwas müde ein sieht wie einmal. Ferien Feuer Freude fast um.	30	21	\N	5
16	European Days on Data and Knowledge Engineering 2026	2026-07-05	2026-07-07	Cultural algo te club. Cuyo doctor encuentra fue resultados posición siguiente. Dolor investigación líder profesional problema países administración. Próximo relaciones visita.	16	9	\N	7
17	Forum on Database Systems 2026	2026-07-12	2026-07-13	Fond port complet village pouvoir importer. Acte cri naturel. Expression six considérer direction divers valoir. Faible leur creuser précis fauteuil siècle.	4	6	\N	5
18	European Days on Data Science 2026	2026-11-01	2026-11-02	Möglich zu schlafen Tier. Suchen Minutenmir verstehen Ende Stunde. Küche Affe in dazu. Ließ sechs stark gefährlich Musik Mädchen hoch schlimm.	2	3	\N	4
19	Symposium on Data Science 2026	2026-09-21	2026-09-24	Jambe parfois hôtel espérer exposer. Million robe étendre fumer être poète oeil. Moyen pencher complet renoncer examiner plein journée.	2	3	\N	6
20	Forum on Database Systems 2026 – Amsterdam	2026-09-20	2026-09-24	Parte levare uomo specie pesare titolo. Perdere nuovo soffrire attività coloro decidere.	18	12	\N	4
21	ICDE 2026	2026-07-01	2026-07-02	Nichts hinter warten spät Winter. Los kennen draußen verstecken darauf Fenster Flasche sieben. Erzählen hoch brauchen will.	6	7	4	5
22	Symposium on Knowledge Management 2026	2026-03-13	2026-03-15	Almeno greco riguardare. Bocca passare avvicinare tono. Estate dimostrare eccetera pena caso signora. Amore frase tavolo. Libertà sperare trarre ne cavallo ufficio muovere.	10	10	\N	1
23	International Conference on Data Engineering 2026	2026-10-31	2026-11-02	Blanco ayuda manuel recursos buenos propio esas. Importante día falta demás tal las recursos. Palabras joven se material. Cierto vino tenían rey europea hacen social. Anterior cuerpo ocho autor técnica nadie otros.	32	21	\N	8
24	International Conference on Temporal Data 2027	2027-09-03	2027-09-05	Space range expect sea speak include table consumer. Book lay laugh red man. Affect anyone movement control bill especially. Road do character management game find. Your less social form such weight argue.	31	9	\N	2
25	DEXA 2020	2020-04-07	2020-04-09	Linea contadino simile segno sereno capace ripetere. Giudizio vestito dimostrare volto contro.	8	3	6	7
26	International Conference on Database Systems 2023	2023-10-15	2023-10-18	Interrompre point énergie entraîner parfaitement. Quelqu'Un mentir causer. Pas coucher souvenir société d'abord calme partager. Affirmer rester neuf forcer dernier vêtement. Répéter inviter nouveau fatiguer beau ciel beauté ouvrage.	28	10	\N	2
27	ER 2023	2023-05-09	2023-05-11	Pauvre préférer respecter cela dehors vision. Révolution haut convenir poser existence chacun.	4	6	5	7
28	DEXA 2027	2027-11-21	2027-11-24	Mine meilleur juste mon mêler entre. Dos sauver tenter mien aussitôt choix écrire. Me ignorer remonter lisser puisque. Page facile page.	32	23	6	\N
29	International Conference on Data Science 2021	2021-05-20	2021-05-22	Tragen einmal Schiff Sonntag die führen ich. Da Luft beim um das von.	13	19	\N	3
30	DEXA 2024	2024-04-02	2024-04-03	Court all politics home majority perhaps opportunity. Hand paper audience.	37	20	6	\N
31	TIME 2027	2027-03-25	2027-03-28	Life police guess sea. State some around pay more same. Back democratic mind big discuss. Country moment eat personal condition see.	9	9	8	2
32	VLDB 2020	2020-08-29	2020-08-31	Freddo leggere porre stanza commercio concludere guardare. Poeta morale osservare tra sud necessario.	37	8	3	1
33	Forum on Data Science 2024	2024-11-11	2024-11-12	Sonne jeder sehr nimmt Musik essen. Wetter fliegen Wort kaufen hoch sehr zum. Also dazu warum acht zur essen gerade Spiel. Wenn Licht möglich möglich Boden.	21	16	\N	7
34	EDBT 2027	2027-03-08	2027-03-11	Cercare futuro ognuno descrivere. Base grosso tedesco raccogliere quale. Comporre sentire prezzo occorrere sviluppo orecchio esempio. Giovanotto riunire tentare figura stagione intenzione togliere.	29	22	7	7
35	Forum on Database Systems 2027	2027-06-17	2027-06-20	Tour parti part article mais ensemble mois envelopper. Chien plein vraiment vide rang. Ligne d'autres eaux fonder cerveau baisser mort.	1	2	\N	7
36	EDBT 2020	2020-10-24	2020-10-27	Dire fort habiter pouvoir reconnaître jeune. Juge pensée côte où pur. Depuis disparaître gris politique muet. Plante goutte étrange ensuite. Permettre regretter comme étranger sac révéler papier haute.	41	20	7	1
37	International Conference on Temporal Data 2023	2023-06-06	2023-06-10	Choose rock beat science drug per. Than star add really. Figure likely forward science.	32	15	\N	\N
38	TIME 2023	2023-04-12	2023-04-14	Model else low role center recognize adult. Town money eight art customer recent even let. At produce production.	2	3	8	2
39	European Days on Database Systems 2027	2027-03-22	2027-03-24	Gar Wald hier. Letzte schwarz weil lassen nennen blau.	10	10	\N	8
40	ICDE 2023	2023-09-11	2023-09-15	Night Republican always two figure majority season. Get goal personal. You without every artist election. Three spring ahead never exactly charge.	2	3	4	7
41	DEXA 2025	2025-10-07	2025-10-09	Quello militare preciso spesso. In né inizio età pagina. Nascere corsa cercare musica scegliere sorriso estate.	40	27	6	\N
42	Forum on Data Science 2027	2027-04-07	2027-04-10	Explicó hicieron decir corte asimismo algún. Época escuela tras fútbol decir si tuvo. Rosa podía entrada informe oficial finalmente.	25	18	\N	\N
43	European Days on Temporal Reasoning 2023	2023-11-09	2023-11-12	Capital ago worry pay. Note discuss discussion reach grow read live maybe. Light power contain hold listen clearly difficult impact.	15	14	\N	7
44	European Days on Spatial Information 2026	2026-04-08	2026-04-11	D'Autres planche courage cours comprendre usage. Soit juste entrée immense désert franchir. Offrir saison problème.	29	4	\N	3
45	European Days on Big Data Analytics 2026	2026-04-10	2026-04-11	Ordinare mio spingere romano milione largo sera. Stabilire dimenticare motivo. No mettere perciò. Considerare intero stare. Lettera infatti parte arrestare metà.	9	9	\N	6
46	VLDB 2026	2026-07-02	2026-07-05	Bed may conference one thus national hotel. Late condition opportunity Republican dark lawyer. Food possible represent clearly run. Box last guy model.	19	8	3	\N
47	VLDB 2021	2021-08-31	2021-09-01	Uguale giornata giovane ripetere tanto notevole politico ciascuno. Concedere provincia indicare estendere. Eh concludere su valere abito riguardare addirittura. Soluzione natura accanto stanco determinare opinione lotta. Invece pace accendere stanco dubbio per.	19	15	3	1
48	TIME 2020	2020-07-05	2020-07-06	Challenge president already take. Study fear turn any indicate condition public.	3	5	8	3
49	Symposium on Knowledge Management 2022	2022-04-20	2022-04-21	Plazo nueva ninguna dejar reforma sí dicho. Presenta mejores acerca ocasiones tiene aquellos. Acciones hora tenemos crisis. P hacer metros pueda rafael. Éxito conocer expresión cambios actual hija carlos.	32	20	\N	5
50	European Days on Data Engineering 2027	2027-05-31	2027-06-01	Trabajar cuyo necesidad metros organización pasó. Lado cabeza historia les bueno europea efectos parece. Términos idea claro derechos oficial un punto da. Falta sociales sé a. Aquella éxito alta si tienen mercado.	29	22	\N	\N
51	Symposium on Data Engineering 2024	2024-08-25	2024-08-27	Straße plötzlich las offen was Maus Glas. Wichtig bauen los Mutter scheinen Minutenmir. Erst schlafen Stunde. Beim deshalb unser gleich her man.	31	7	\N	6
52	International Conference on Big Data Analytics 2024	2024-06-20	2024-06-21	Hope organization ten seem relate fire all including. Theory he stop few modern company hear. Sing tree kitchen. Sometimes toward child. Type run model simply century the.	1	1	\N	\N
53	Symposium on Database Systems 2027	2027-06-16	2027-06-18	Éxito etc viaje duda en. Puedo podemos tan. Dicen antes vino entrada más acerca buenos.	40	8	\N	1
54	ICDE 2024	2024-09-02	2024-09-03	Court everybody five kid brother. Church boy when nice. Deal go five center. Off commercial find throughout music.	21	3	4	3
55	DEXA 2023	2023-03-29	2023-04-02	Intérieur pluie bras. Bas fois près. Parfois position hiver examiner erreur couche rayon risquer.	40	27	6	\N
56	VLDB 2027	2027-06-21	2027-06-23	Certes rôle théâtre intelligence image politique presser. Intérêt trou charger supporter devoir face connaissance. Résistance source idée amour inviter être. Sentiment dresser étrange moyen livrer frapper prévoir.	15	5	3	\N
57	European Days on Spatial Information 2026 – Lyon	2026-11-02	2026-11-04	Pencher respirer marchand fou garçon pain mener. Fils étaler roman nombreux répondre habitude représenter. Pourquoi compagnie plaire quart prétendre seconde calmer. Inconnu mieux sac composer vague autant brûler rompre.	1	1	\N	5
58	Symposium on Database Systems 2026	2026-07-30	2026-07-31	Piano assicurare crisi certamente oggi ricerca scrivere. Polizia latino energia partire. Contento preoccupare facile numero tardi espressione tuo. Pure tavolo volere ognuno parlare meritare.	36	20	\N	8
59	CAISE 2024	2024-08-17	2024-08-18	Hard nature apply reflect. Body executive all it opportunity personal. Image itself deep community cause new.	8	10	2	3
60	Symposium on Knowledge Management 2026 – Vancouver	2026-09-10	2026-09-12	Gab von darauf alle. Denn war rennen. Bin Pferd ihr klein. Wie oben Klasse ist tragen hier Familie ist.	27	23	\N	\N
61	Symposium on Database Systems 2021	2021-09-28	2021-10-02	Séparer demander libre fumée même faire vingt. Joindre fait nature venir avis prouver mal. Inquiétude avec succès beau interroger. Politique matière nation ordre. Mari acheter ignorer tantôt mouvement éprouver.	9	9	\N	4
62	Forum on Data Science 2025	2025-03-12	2025-03-14	Draußen Schnee neu gehen stark. Bei Küche drehen bald zwei. Anfangen lassen darin Berg Stadt Flasche nächste früher.	30	21	\N	2
63	CAISE 2027	2027-03-08	2027-03-10	Nichts weiter sich richtig. Tante frei schreiben lassen Stunde vielleicht.	16	2	2	\N
64	Forum on Temporal Data 2023	2023-02-25	2023-03-01	Nein traurig und sitzen. Spaß fertig kam packen erzählen selbst.	39	11	\N	\N
65	International Conference on Information Systems 2022	2022-03-28	2022-04-01	Sofort dafür draußen holen gefährlich. Fenster Schiff Himmel fressen mal jung gab.	2	4	\N	4
66	TIME 2025	2025-01-29	2025-01-31	Valle presentare animale tedesco persona uomo. Parete pietra donna domani scendere discorso. Godere rispondere rendere raccogliere operazione contento finalmente prima. Europeo accorgersi accogliere attento.	22	17	8	8
67	ER 2025	2025-10-10	2025-10-14	Bocca istante croce eccellenza contare alcuno base. Poesia sicurezza ultimo personaggio proprio cane sonno carta.	26	20	5	5
68	European Days on Big Data Analytics 2027	2027-02-05	2027-02-06	Padres último niño obstante. Material pueblo actual fiscal cierta sé estas. Alguna ni razón explicó.	32	14	\N	2
69	EDBT 2025	2025-04-06	2025-04-07	Kam Leben wichtig noch. Plötzlich Buch mehr jeder. Platz weiß schwimmen Brot beißen möglich Flasche kaufen.	34	13	7	7
70	European Days on Information Systems 2021	2021-03-20	2021-03-24	Tra popolo dolce. Superare occasione metro triste mancare interessare. Muro abitare unire segno.	15	14	\N	8
71	International Conference on Data Engineering 2026 – Seattle	2026-08-21	2026-08-22	Morire volontà figlio esperienza arrivare zia piantare. Morire valere avanzare leggero rimettere pianura. Nero venire polizia esame.	31	12	\N	2
72	International Conference on Database Systems 2026	2026-03-11	2026-03-13	Prezzo maggio stasera interno conservare ampio allora vuoto. Male assoluto musica essere morale.	36	19	\N	7
73	ER 2020	2020-06-16	2020-06-20	Fine finalmente qualche. Campagna scoprire porto legge preciso spiegare.	15	5	5	6
74	International Conference on Knowledge Management 2025	2025-03-20	2025-03-22	Under already center president likely. Animal red candidate common anyone film soldier lay. Structure ask stage box. Sometimes determine source international specific word question food. National focus who degree animal community as.	40	18	\N	5
75	Symposium on Information Systems 2020	2020-04-22	2020-04-24	Drehen heiß dort fiel Name davon. Nun springen als laufen acht dürfen bleiben rechnen. Im Tante Spiel Schluss erschrecken.	12	11	\N	7
76	Forum on GIScience 2021	2021-04-03	2021-04-04	Ihm Winter noch Arzt eigentlich leicht wo. Tun gefährlich immer mit Eis zurück Zimmer nämlich. Letzte Kopf offen erst bald dabei deshalb. Lehrerin dir werden Ball Hase erzählen Flasche. Tag Sohn auf sicher werfen durch stark lassen.	6	7	\N	5
77	International Conference on Spatial Information 2025	2025-11-07	2025-11-11	Produire nord entretenir coucher plusieurs. Défaut but déclarer demander gagner couleur.	3	5	\N	7
78	European Days on Database Systems 2027 – Barcelone	2027-11-27	2027-11-30	One approach job democratic participant concern health. Rest place wish dark camera realize arrive.	13	12	\N	5
79	Forum on Data and Knowledge Engineering 2020	2020-05-12	2020-05-15	Learn commercial gas though page smile point. Town official need discover in miss television describe.	9	10	\N	2
80	Forum on Temporal Reasoning 2020	2020-10-01	2020-10-04	Adesso inoltre spesso dinanzi intenzione. Straniero ora chiudere o accadere. Anima linea ripetere. Iniziare grave scrivere.	22	17	\N	1
81	European Days on GIScience 2026	2026-01-30	2026-02-02	Dépasser mince action public tu cesse écrire. Afin De plaire classe important. Quinze ainsi il relation songer françois résister. Parcourir préparer abandonner pareil fin posséder.	25	19	\N	7
82	European Days on Data Engineering 2020	2020-07-05	2020-07-07	Ir todavía sistemas gracias producto. Quizá éste hermano hijos.	24	15	\N	4
83	Symposium on Database Systems 2026 – Pékin	2026-11-18	2026-11-21	Heute Kopf auch hat. Schuh Monate spielen dem Glas Meer Rad.	34	24	\N	2
84	Symposium on Data Engineering 2023	2023-07-18	2023-07-20	Semana pp estamos relaciones han. Internacional capacidad tenemos ellos seguro viene. Revolución julio fuerza plaza realizar imágenes juicio.	16	21	\N	3
85	BDA 2022	2022-02-28	2022-03-02	Bag today eye what. Clearly born challenge character. Minute physical fall wide must. Listen information scene again.	36	25	9	6
86	Forum on Spatial Information 2025	2025-04-08	2025-04-11	The discussion water. In garden position for order recent.	38	26	\N	5
87	European Days on GIScience 2027	2027-09-09	2027-09-10	Podía millones diciembre personas carlos atención blanca. Todas verdad instituto. Llama momentos verdad teoría fútbol realizar iglesia casi. Ante niveles partidos primeros único.	6	3	\N	1
88	ICDE 2027	2027-11-09	2027-11-11	Program within challenge. Music class feeling turn identify material certainly. Until choose wife national medical positive far. Wide senior yes project son. Full both look always question bring.	1	2	4	6
89	BDA 2021	2021-10-06	2021-10-08	Sein homme besoin as passer nécessaire d'autres traîner. Côte bande serrer plusieurs valeur. Fonder justice obtenir longtemps aspect place former. Famille faux droite être vin songer.	19	15	9	6
90	Forum on Data and Knowledge Engineering 2025	2025-06-14	2025-06-17	Que gauche hésiter coin proposer sur. Changement noir bas couvrir inventer sol. Aujourd'Hui veille rapporter beau fruit tenter.	29	22	\N	2
91	Symposium on Data Engineering 2026	2026-06-15	2026-06-17	Letto notte tavolo contro settimana elemento mancare. Si esporre noi levare alto. Cittadino esempio pesare.	22	20	\N	\N
92	Forum on Data Science 2024 – Paris	2024-08-08	2024-08-10	Improvviso mandare presto difficoltà campo. Mangiare verde ospedale frutto là. Specie pensiero luce privato campo mese.	2	3	\N	2
93	Symposium on GIScience 2026	2026-10-08	2026-10-10	Sea puede respecto sectores están. Qué creo ayuda club.	6	7	\N	3
94	Forum on Data Engineering 2022	2022-03-01	2022-03-03	Malheur trait lourd réflexion confondre. Nuit combien entourer engager. Doigt pouvoir extraordinaire marcher étroit.	34	17	\N	\N
95	ICDE 2022	2022-11-22	2022-11-25	Million health machine future. Bill choice determine could.	34	24	4	4
96	European Days on Time Series Management 2027	2027-06-15	2027-06-18	U momentos precisamente chile dado profesional ante. Carne sigue cosa dios. Dicen domingo serán aquella seguro me. Horas asunto otras importante. Situación máximo medios serán.	13	26	\N	5
97	Symposium on Knowledge Management 2026 – Sydney	2026-10-05	2026-10-09	Remercier rassurer apporter. Ancien petit note intention.	40	27	\N	\N
98	International Conference on Database Systems 2020	2020-09-23	2020-09-25	Gefährlich alle brauchen daran. Erschrecken Weg einfach Haare Blume unter wird wo.	8	23	\N	5
99	ER 2027	2027-10-10	2027-10-12	Verstecken spät nun lernen. Brief Nacht als etwas. Wünschen dumm so aber sehen. Wer verkaufen lachen schnell einfach.	40	27	5	1
100	TIME 2026	2026-02-17	2026-02-20	Visible gouvernement lourd froid recommencer enfermer. But chair reconnaître près mille appartenir environ. Fin immense qualité porte.	2	3	8	2
101	BDA 2025	2025-04-05	2025-04-07	Il vivere inoltre sonno stringere scendere treno. Concedere zitto mandare bosco interno poiché. Campo grave probabilmente viaggio.	31	23	9	1
102	European Days on Temporal Reasoning 2021	2021-01-30	2021-02-01	Window full organization wrong but study. Everything require old event smile popular hundred.	39	18	\N	5
103	BDA 2023	2023-06-24	2023-06-25	Voglia merito chilometro latte capace male. Pensiero cavallo bestia arma attenzione. Vero girare preferire. Esperienza pazzo ridere polizia. Ringraziare salire coprire ponte mamma dito fissare.	2	3	9	\N
104	Forum on Temporal Reasoning 2020 – Milan	2020-10-10	2020-10-14	Propios sobre estudio. Campo hemos zona movimiento. Misma amigos cultural. Investigación hombre vivir efecto. Apoyo investigación palabra resultado.	10	10	\N	7
105	CAISE 2022	2022-03-05	2022-03-09	Soltanto memoria governo mano verità partito fortuna. Fantasia altro anzi sicuro forma. Alto strada finire bello foglia fratello forse pomeriggio. Desiderio età avvocato prevedere specie.	3	13	2	6
106	ER 2024	2024-01-29	2024-01-31	Agiter entretenir imposer société. Lueur glace ah intéresser aile engager montrer. Mot rire bois pluie esprit lier. Combat également vêtir couper partir vieux.	7	24	5	6
107	European Days on Big Data Analytics 2022	2022-02-12	2022-02-14	Durant argent voyager frais début. Printemps naissance non donner. Rêve inviter créer retenir pénétrer elle rêver. Phrase enfant garde dessus lui planche. Conduire agir prendre social mur croire venir.	30	27	\N	3
108	ER 2021	2021-09-12	2021-09-13	Scrittore solito svegliare trarre qualunque aspetto controllo. Chissà ciascuno presenza esempio interessare famiglia servire. Pericolo smettere dolce effetto.	1	2	5	7
109	Forum on Data and Knowledge Engineering 2027	2027-05-30	2027-05-31	Door draw change agree someone financial magazine yard. Positive already city carry election sound. Compare system white magazine after teacher base.	4	12	\N	6
110	Forum on Data and Knowledge Engineering 2026 – Lausanne	2026-08-13	2026-08-16	Busca seis c lucha. Servicio fútbol pese cambio. Corazón corte duda título martín reforma incluso.	24	16	\N	7
111	DEXA 2021	2021-08-29	2021-09-02	Causer rideau épais neuf flot quoi demain goût. Briser croix dormir front. Aspect marché précieux calme même inviter désert douleur.	12	11	6	5
112	BDA 2024	2024-09-05	2024-09-09	Resource start again whom paper success production. Real small dream. His police red total rate movement door. Home travel hotel within eight bed.	13	12	9	6
113	International Conference on Geographic Data Science 2026	2026-06-10	2026-06-11	Teacher civil keep first speech. Smile ever bag single man say. Response theory star station recognize media.	13	12	\N	8
114	International Conference on Temporal Reasoning 2020	2020-03-25	2020-03-26	Sein merken gesund Schnee Sommer Pferd einfach kann. Abend er gehen müssen. Dir liegen zeigen Tür. Vater schlafen Stein Geschenk.	13	12	\N	8
115	ICDE 2025	2025-07-30	2025-08-02	Comprare oramai fermare duro avvicinare. Condizione spirito tuttavia stare da ufficiale. Piantare pena svegliare vestire conto professore comodo.	22	17	4	5
116	Forum on Data and Knowledge Engineering 2023	2023-03-20	2023-03-21	Ottenere ci uscire compagno notte adesso. Interessante tendere lato potenza campagna provvedere consiglio. Eh mano casa sonno ottenere. Qualunque conservare concludere salire alzare. Destino largo dio oh piantare.	24	18	\N	4
117	VLDB 2024	2024-09-28	2024-09-30	Cesse entraîner pourquoi porte preuve présenter qualité. Autre mille arrivée tout intérieur.	19	15	3	2
118	Forum on Information Systems 2025	2025-07-17	2025-07-18	Schwarz Teller aber lernen Herz Zimmer sagen davon. Auch dürfen drei Leben gleich kurz bleiben. Jetzt frei genau zu leicht Zeitung fährt. Wetter führen vorbei nun Sommer fressen. Jung dort setzen Leben wo Minutenmir.	41	6	\N	2
119	EDBT 2023	2023-04-02	2023-04-04	Chiudere dedicare ampio distinguere proporre. Cambiare strumento mantenere invece volare non.	24	18	7	3
120	European Days on Data Science 2021	2021-02-23	2021-02-25	Smettere spazio capire bastare. Concludere comodo mentre donna strada. Costringere zio abito rimettere concludere tendere dimenticare massa. Stella almeno preoccupare prendere.	34	24	\N	2
121	EDBT 2022	2022-07-02	2022-07-03	Titolo bravo fede alzare leggero proposta luogo pensiero. Ordine accanto veramente poesia umano. Ufficiale zona svegliare sapere carta sostenere. Favore arrivare attività un giovanotto.	36	5	7	3
122	VLDB 2022	2022-08-30	2022-09-03	Dietro risolvere grigio aiutare. Colpire riunire ecco resto piuttosto. Esame scena ragazza tentare.	22	17	3	6
123	Forum on Knowledge Management 2023	2023-07-17	2023-07-21	Partes octubre congreso aire considera nuevos. Cantidad tanto relaciones fuerza ciudad blanco tres. Aquella actividad tarde radio toda comunidad pueda.	9	9	\N	5
124	Forum on Knowledge Management 2021	2021-10-05	2021-10-07	Difícil otros creación casos líder. Consumo recursos equipo hasta otro.	3	5	\N	1
125	International Conference on Data Science 2020	2020-03-02	2020-03-03	Long gagner inquiétude prochain. Examiner nez regarder afin de quatre. Condamner confier fonction banc sortir effort noir. Rassurer hôtel rire état terrible robe cri. Quinze occuper sommeil briller.	37	9	\N	5
126	International Conference on Data Engineering 2024	2024-09-24	2024-09-26	Comisión con siete. Autoridades dolor peor clase efecto secretario teoría.	16	13	\N	7
127	Forum on Data and Knowledge Engineering 2027 – Tokyo	2027-09-15	2027-09-17	Blau dazu einmal Tisch Schnee. Versuchen erzählen Polizei Rad jung. Versuchen Meer bis Spaß deshalb in damit Weihnachten. Wünschen Küche versuchen Nase Erde mögen.	32	23	\N	\N
128	ER 2022	2022-07-29	2022-08-02	Accogliere perciò provvedere vincere soffrire raggiungere. Questo zitto anche grosso messa qualità trarre superare.	19	15	5	3
129	Symposium on Data and Knowledge Engineering 2021	2021-02-15	2021-02-17	Modo industriale faccia assoluto. Storia camera pazzo pianta labbro interesse. Eh contadino fissare dentro.	15	14	\N	6
130	European Days on Data Science 2023	2023-04-12	2023-04-15	Two table resource life third rich. Where strategy pull same somebody son. Perform executive see project. Community choose man soldier. Field decide another adult thing ground city.	21	16	\N	\N
131	International Conference on Location Intelligence 2023	2023-11-15	2023-11-17	Orden estos importante cuales. Problemas buena igual años marco mujeres política.	31	20	\N	7
132	Symposium on Knowledge Management 2022 – Édimbourg	2022-06-05	2022-06-07	Santa jorge alto cara. Animales práctica actividades puso. Distintos también sino origen. Ii luego aquel arte control. Toda c mirada ellos.	16	13	\N	5
133	International Conference on Big Data Analytics 2021	2021-08-06	2021-08-10	Shoulder according strong list expert commercial. Head senior guess professor charge. Instead direction soon including important learn system. Want kind show response military attorney.	40	9	\N	2
134	European Days on Knowledge Management 2026 – São Paulo	2026-07-31	2026-08-02	Zug dort bei Sohn richtig Pferd. Bauer Oma Schwester richtig Loch Garten Hund. Von sechs gerade Gott tun Weg noch. Schreiben kaufen erschrecken Mensch.	36	25	\N	1
135	BDA 2020	2020-03-31	2020-04-02	Mucha práctica producción cuatro manos todo. Ex escuela hacerlo económica encuentra nuestra. Seguir políticos alrededor medio ha europea superior. Octubre podía relaciones prensa consecuencia.	33	5	9	6
136	European Days on Data and Knowledge Engineering 2022	2022-08-10	2022-08-14	Letzte daran sofort wird kein müde aber gleich. Tag zusammen Mutter waschen oft. Unter Fenster Geburtstag rund Tisch müde dem.	25	19	\N	5
137	International Conference on Big Data Analytics 2027	2027-01-29	2027-01-31	Braccio metà contare ritrovare lato. Provincia sereno avvenire assistere. Luce istante generale misura. Noi ritrovare spesa oltre permettere vuoto prezzo ufficiale. Senso chiave caratteristico provare carta pronto.	25	19	\N	5
138	International Conference on Data Engineering 2023	2023-02-16	2023-02-20	Ninguna este luego estudios distintas. Elecciones fondo hacia miguel. Recursos unos familia.	16	5	\N	8
139	International Conference on Data and Knowledge Engineering 2025	2025-08-23	2025-08-25	Laufen Stein denken natürlich Auto. Warten Essen tragen laut daran. Bein Auge langsam Geld Kind gleich.	31	17	\N	4
140	Forum on Knowledge Management 2025	2025-09-22	2025-09-26	Cattolico cercare permettere riempire portare chiudere quarto bagno. Popolo imparare descrivere grazia musica uscire storico ragazza. Spalla proposta nuovo sangue. Non capire noi contare passato.	22	15	\N	5
141	European Days on Big Data Analytics 2027 – Valence	2027-04-29	2027-05-01	Duda dejó jefe es pudo apenas imposible. Llegado padre ejército mucha sector.	14	10	\N	6
142	TIME 2024	2024-06-16	2024-06-17	Hablar era pregunta o anterior especial. Algún modo presidente menos ver mejor mis. Toda propios viene puede. Frente viaje director según otras aparece. Zona llamado hacia ello llevar.	10	13	8	5
143	Forum on Knowledge Management 2021 – Berlin	2021-07-17	2021-07-20	Militar estamos martín todavía tuvo allá él. Quién mí tendrá. Palabra plan año serán viejo.	6	7	\N	\N
144	Symposium on Big Data Analytics 2024	2024-03-31	2024-04-01	Image base player data whose health world. Mr interest treatment later a. Which per president cold art two event.	7	8	\N	1
145	ICDE 2021	2021-08-20	2021-08-22	Unten es unser fährt doch man. Gefährlich hinter daran dem. Überall Wagen erzählen lernen Stück war wissen. Zu Schule früh rot Gesicht.	11	1	4	8
146	Symposium on Knowledge Management 2027	2027-05-03	2027-05-05	Foreign trial card two participant above act community. Time reflect several Mrs skin power back. Throughout staff knowledge. Good spend still group.	36	25	\N	1
147	International Conference on Location Intelligence 2022	2022-08-22	2022-08-24	Leg view know develop. Serve quite remember.	12	13	\N	2
148	Symposium on Database Systems 2025	2025-06-15	2025-06-18	Personal space determine woman whose already manage region. Decide cultural start how thank notice management necessary.	30	5	\N	6
149	Symposium on Big Data Analytics 2022	2022-09-12	2022-09-14	Tienen energía humanos mientras corte ciencia razones. Sistema viene proyectos realizar época. Análisis juicio la actual plaza. Salida real exterior. Nosotros análisis niño tengo peso juicio.	38	26	\N	7
150	Symposium on Location Intelligence 2026	2026-10-11	2026-10-13	Truth mother first hot free. Space wrong difficult ready when true culture.	31	6	\N	7
151	CAISE 2023	2023-09-06	2023-09-08	Offen braun langsam Tante. Straße will unser Finger lachen wollen Uhr traurig. Stelle wirklich sprechen ob Sonne offen Nacht.	16	9	2	2
152	Forum on Database Systems 2027 – Tokyo	2027-06-27	2027-06-29	Fermer succès pourquoi. Attention révéler as on.	32	23	\N	4
153	European Days on Big Data Analytics 2022 – Toronto	2022-09-22	2022-09-24	Prato noi epoca giovanotto. Passare impedire sottile rompere.	26	20	\N	4
154	Symposium on Data Engineering 2023 – Hambourg	2023-11-22	2023-11-23	Campo produce aspecto objeto buena pone nuestras. Mundial energía caso por viaje naturaleza prueba.	8	3	\N	3
155	European Days on Data Engineering 2022	2022-07-07	2022-07-11	Modo europa éxito imagen sociedad conciencia así. Experiencia congreso encima últimos experiencia. Características entonces llegar programa solo se plan.	32	23	\N	8
156	Forum on Data Science 2022	2022-10-10	2022-10-13	Medical strong teach instead crime. Policy cut attention country little.	2	22	\N	4
157	International Conference on Data Science 2021 – Nantes	2021-02-13	2021-02-16	Sole notizia film escludere ferro bosco. Mare tendere personaggio. Libertà costruire là ripetere secondo. Correre confronto volere fuggire attorno amare. Chiamare intorno perdere tanto.	5	18	\N	3
158	TIME 2022	2022-08-24	2022-08-26	Endlich fünf fahren. Schüler Glück Minutenmir dürfen am.	16	13	8	\N
159	Symposium on Temporal Reasoning 2022	2022-07-18	2022-07-19	Tür dein reiten. Gleich erzählen klein heiß.	16	13	\N	1
160	Forum on Information Systems 2024	2024-09-14	2024-09-18	Zimmer über Wald Wagen beim denn werfen. Eis heraus helfen neu Zimmer. Wer Sommer nass verstecken Garten.	7	8	\N	2
161	Workshop on Indexing of temporal data @ CAISE 2026	2026-02-09	2026-02-09	Satellite workshop of CAISE 2026 dedicated to Indexing of temporal data.	26	20	\N	2
162	Workshop on NoSQL databases @ ER 2021	2021-09-11	2021-09-11	Satellite workshop of ER 2021 dedicated to NoSQL databases.	1	2	\N	7
163	Workshop on Temporal query languages @ TIME 2022	2022-08-27	2022-08-28	Satellite workshop of TIME 2022 dedicated to Temporal query languages.	16	13	\N	\N
164	Workshop on Cartographic generalization @ SDH 2024	2024-08-05	2024-08-06	Satellite workshop of SDH 2024 – Spatial Data Handling dedicated to Cartographic generalization.	9	9	\N	2
165	Workshop on Deep learning @ Forum on Data Science 2025	2025-03-11	2025-03-11	Satellite workshop of Forum on Data Science 2025 dedicated to Deep learning.	30	21	\N	2
166	Workshop on Deep learning @ Symposium on Database Systems 2027	2027-06-19	2027-06-20	Satellite workshop of Symposium on Database Systems 2027 dedicated to Deep learning.	40	8	\N	1
167	Workshop on Deep learning @ European Days on Data Science 2026	2026-11-03	2026-11-04	Satellite workshop of European Days on Data Science 2026 dedicated to Deep learning.	2	3	\N	4
168	Workshop on Requirements engineering @ International Conference on Database Systems 2023	2023-10-19	2023-10-19	Satellite workshop of International Conference on Database Systems 2023 dedicated to Requirements engineering.	28	10	\N	2
169	Workshop on Requirements engineering @ Forum on Information Systems 2024	2024-09-19	2024-09-19	Satellite workshop of Forum on Information Systems 2024 dedicated to Requirements engineering.	7	8	\N	2
170	Workshop on Access control @ ICDE 2025	2025-07-29	2025-07-29	Satellite workshop of ICDE 2025 dedicated to Access control.	22	17	\N	5
171	Workshop on Access control @ European Days on Knowledge Management 2026	2026-11-23	2026-11-23	Satellite workshop of European Days on Knowledge Management 2026 dedicated to Access control.	38	26	\N	2
172	Workshop on Distributed computing @ CAISE 2027	2027-03-11	2027-03-12	Satellite workshop of CAISE 2027 dedicated to Distributed computing.	16	2	\N	\N
173	Workshop on Distributed computing @ Forum on Data and Knowledge Engineering 2026	2026-03-05	2026-03-05	Satellite workshop of Forum on Data and Knowledge Engineering 2026 dedicated to Distributed computing.	7	8	\N	\N
174	Workshop on Remote sensing data @ BDA 2023	2023-06-23	2023-06-23	Satellite workshop of BDA 2023 dedicated to Remote sensing data.	2	3	\N	\N
175	Workshop on Geographic information retrieval @ International Conference on Geographic Data Science 2026	2026-06-12	2026-06-12	Satellite workshop of International Conference on Geographic Data Science 2026 dedicated to Geographic information retrieval.	13	12	\N	8
176	Workshop on Data lakes @ Symposium on Knowledge Management 2026	2026-09-09	2026-09-09	Satellite workshop of Symposium on Knowledge Management 2026 – Vancouver dedicated to Data lakes.	27	23	\N	\N
177	Workshop on Requirements engineering @ International Conference on Data and Knowledge Engineering 2025	2025-08-26	2025-08-26	Satellite workshop of International Conference on Data and Knowledge Engineering 2025 dedicated to Requirements engineering.	31	17	\N	4
178	Workshop on Data anonymization @ VLDB 2027	2027-06-20	2027-06-20	Satellite workshop of VLDB 2027 dedicated to Data anonymization.	15	5	\N	\N
179	Workshop on Temporal data models @ European Days on Temporal Reasoning 2026	2026-04-08	2026-04-08	Satellite workshop of European Days on Temporal Reasoning 2026 dedicated to Temporal data models.	30	21	\N	5
180	Workshop on Entity-relationship model @ EDBT 2020	2020-10-23	2020-10-23	Satellite workshop of EDBT 2020 dedicated to Entity-relationship model.	41	20	\N	1
181	Workshop on Requirements engineering @ Symposium on Data and Knowledge Engineering 2021	2021-02-18	2021-02-18	Satellite workshop of Symposium on Data and Knowledge Engineering 2021 dedicated to Requirements engineering.	15	14	\N	6
182	Workshop on Stream processing @ Symposium on Information Systems 2020	2020-04-25	2020-04-25	Satellite workshop of Symposium on Information Systems 2020 dedicated to Stream processing.	12	11	\N	7
183	Workshop on Stream processing @ ICDE 2021	2021-08-23	2021-08-24	Satellite workshop of ICDE 2021 dedicated to Stream processing.	11	1	\N	8
184	Workshop on Data anonymization @ European Days on Data Engineering 2020	2020-07-04	2020-07-04	Satellite workshop of European Days on Data Engineering 2020 dedicated to Data anonymization.	24	15	\N	4
185	Workshop on Reinforcement learning @ Symposium on Database Systems 2026	2026-11-17	2026-11-17	Satellite workshop of Symposium on Database Systems 2026 – Pékin dedicated to Reinforcement learning.	34	24	\N	2
186	Workshop on Requirements engineering @ Symposium on Database Systems 2021	2021-10-03	2021-10-04	Satellite workshop of Symposium on Database Systems 2021 dedicated to Requirements engineering.	9	9	\N	4
187	Workshop on Requirements engineering @ European Days on Database Systems 2027	2027-11-26	2027-11-26	Satellite workshop of European Days on Database Systems 2027 – Barcelone dedicated to Requirements engineering.	13	12	\N	5
188	Workshop on Temporal database design @ International Conference on Temporal Data 2023	2023-06-11	2023-06-12	Satellite workshop of International Conference on Temporal Data 2023 dedicated to Temporal database design.	32	15	\N	\N
189	Workshop on Spatio-temporal data @ European Days on Spatial Information 2026	2026-11-01	2026-11-01	Satellite workshop of European Days on Spatial Information 2026 – Lyon dedicated to Spatio-temporal data.	1	1	\N	5
190	Workshop on Access control @ ER 2024	2024-01-28	2024-01-28	Satellite workshop of ER 2024 dedicated to Access control.	7	24	\N	6
191	Workshop on R-tree @ International Conference on Spatial Information 2025	2025-11-12	2025-11-12	Satellite workshop of International Conference on Spatial Information 2025 dedicated to R-tree.	3	5	\N	7
192	Workshop on NoSQL databases @ International Conference on Data Engineering 2026	2026-08-23	2026-08-24	Satellite workshop of International Conference on Data Engineering 2026 – Seattle dedicated to NoSQL databases.	31	12	\N	2
193	Workshop on Data anonymization @ European Days on Data and Knowledge Engineering 2026	2026-07-04	2026-07-04	Satellite workshop of European Days on Data and Knowledge Engineering 2026 dedicated to Data anonymization.	16	9	\N	7
194	Workshop on Access control @ International Conference on Database Systems 2026	2026-03-10	2026-03-10	Satellite workshop of International Conference on Database Systems 2026 dedicated to Access control.	36	19	\N	7
195	Workshop on Data anonymization @ VLDB 2022	2022-08-29	2022-08-29	Satellite workshop of VLDB 2022 dedicated to Data anonymization.	22	17	\N	6
196	Workshop on Trajectory data @ Forum on GIScience 2021	2021-04-02	2021-04-02	Satellite workshop of Forum on GIScience 2021 dedicated to Trajectory data.	6	7	\N	5
197	Workshop on Graph databases @ Symposium on Knowledge Management 2027	2027-05-06	2027-05-07	Satellite workshop of Symposium on Knowledge Management 2027 dedicated to Graph databases.	36	25	\N	1
198	Workshop on Temporal query languages @ ICDE 2022	2022-11-21	2022-11-21	Satellite workshop of ICDE 2022 dedicated to Temporal query languages.	34	24	\N	4
199	Workshop on Moving objects @ VLDB 2024	2024-09-27	2024-09-27	Satellite workshop of VLDB 2024 dedicated to Moving objects.	19	15	\N	2
200	Workshop on Data lakes @ International Conference on Data Engineering 2026	2026-10-30	2026-10-30	Satellite workshop of International Conference on Data Engineering 2026 dedicated to Data lakes.	32	21	\N	8
201	Workshop on Moving objects @ European Days on GIScience 2026	2026-02-03	2026-02-03	Satellite workshop of European Days on GIScience 2026 dedicated to Moving objects.	25	19	\N	7
202	Workshop on Geographic information retrieval @ European Days on GIScience 2027	2027-09-08	2027-09-08	Satellite workshop of European Days on GIScience 2027 dedicated to Geographic information retrieval.	6	3	\N	1
203	Workshop on GIS @ SDH 2020	2020-08-30	2020-08-30	Satellite workshop of SDH 2020 – Spatial Data Handling dedicated to GIS.	3	5	\N	2
204	Workshop on Remote sensing data @ SDH 2020	2020-08-26	2020-08-26	Satellite workshop of SDH 2020 – Spatial Data Handling dedicated to Remote sensing data.	3	5	\N	2
205	Workshop on Cartographic generalization @ SDH 2021	2021-04-23	2021-04-23	Satellite workshop of SDH 2021 – Spatial Data Handling dedicated to Cartographic generalization.	1	2	\N	2
\.


--
-- Data for Name: editeur; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.editeur (id_editeur, nom_editeur) FROM stdin;
1	Springer
2	IEEE
3	ACM
4	Elsevier
5	CEUR-WS
6	IOS Press
7	LIPIcs
8	OpenProceedings
\.


--
-- Data for Name: evalue; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.evalue (id_personne, id_conf, num_session) FROM stdin;
1	1	1
1	5	1
1	7	1
1	8	4
1	81	1
1	81	5
1	98	1
1	98	2
1	170	2
2	3	4
2	15	4
2	15	5
2	41	1
2	41	4
2	45	5
2	88	2
2	139	2
2	139	3
2	139	4
2	149	3
3	104	2
4	44	2
5	65	2
5	65	3
5	65	5
5	81	2
5	81	5
5	114	1
5	154	5
5	175	1
5	180	2
5	187	1
6	6	2
6	18	2
6	18	3
6	25	2
6	69	2
6	113	3
6	113	5
7	114	2
7	122	1
7	122	3
7	152	3
7	160	3
8	7	1
8	26	1
8	111	2
8	111	4
8	177	2
9	43	3
9	43	4
9	89	3
10	9	2
10	94	2
10	94	3
10	135	5
11	32	2
11	46	1
11	46	4
11	94	4
11	134	2
11	146	1
11	146	3
11	146	4
11	161	2
12	65	3
12	65	5
12	93	2
13	58	1
13	58	2
13	58	3
13	156	1
13	156	2
13	156	4
13	173	1
14	6	1
14	9	3
14	20	1
14	58	2
14	192	1
14	192	2
15	42	1
15	88	2
15	88	4
15	136	3
15	136	4
15	154	1
15	154	2
16	102	1
16	102	2
16	135	2
16	135	4
16	156	1
17	47	2
17	47	3
17	47	4
17	55	3
17	62	1
17	136	2
17	136	3
17	196	2
18	139	1
19	19	1
19	19	2
19	38	1
19	38	3
19	68	3
19	73	1
20	29	1
20	37	1
20	37	2
20	82	2
20	82	4
20	154	2
20	154	4
21	55	1
21	55	2
21	55	4
21	184	1
22	96	2
22	181	1
23	37	2
23	37	3
23	37	4
23	42	1
23	61	2
23	115	2
24	1	2
24	7	2
24	28	1
24	60	2
24	60	3
24	60	4
24	60	5
24	113	2
24	113	5
24	130	1
24	152	2
24	161	1
25	20	2
25	20	4
25	35	3
25	83	2
25	157	2
25	162	1
25	182	1
26	64	3
26	140	5
26	146	2
26	153	2
26	153	3
26	153	4
26	153	5
26	171	1
27	45	1
27	64	2
27	64	3
27	81	2
27	81	4
27	81	5
28	140	3
28	148	2
28	148	3
29	66	1
29	66	3
29	82	2
29	117	2
29	156	5
30	7	3
30	7	4
30	26	1
30	39	2
30	39	3
30	45	2
30	144	2
30	150	2
30	150	3
30	150	4
30	171	1
30	171	2
31	16	1
31	52	1
31	52	2
31	52	3
31	52	5
31	150	1
31	150	4
32	70	2
32	99	1
32	130	1
32	155	1
32	155	4
33	30	1
33	125	2
33	126	3
33	175	1
34	101	1
35	68	2
35	94	1
35	94	2
35	193	1
36	49	1
36	57	3
36	80	2
36	82	3
36	86	3
36	182	2
37	74	1
37	92	2
37	92	4
37	153	1
37	177	1
38	100	4
39	8	5
39	35	1
39	110	1
39	110	2
40	137	1
40	137	2
40	137	3
42	64	1
42	64	2
42	79	3
42	79	5
42	123	1
42	137	2
42	137	4
42	178	1
43	4	1
43	4	2
43	12	2
43	65	1
43	97	2
43	136	1
43	168	1
43	190	1
44	79	2
45	98	4
45	110	2
45	116	3
45	120	2
45	130	2
45	181	1
45	194	1
46	27	1
46	27	2
46	49	2
46	75	2
46	75	3
46	109	2
46	109	3
46	122	3
46	149	1
47	17	3
47	17	4
47	19	2
47	19	4
47	20	2
47	20	4
47	43	4
47	118	2
47	129	1
47	129	4
47	148	1
47	148	5
48	58	3
48	76	3
48	169	1
49	47	1
49	47	3
49	187	1
50	53	1
50	132	1
50	132	4
51	53	2
51	173	1
51	173	2
52	128	2
52	128	3
52	129	2
52	150	4
52	150	5
52	153	2
52	153	4
52	154	1
52	166	2
52	193	1
52	195	2
53	76	1
53	76	4
53	111	1
53	111	4
54	93	1
54	93	3
54	101	2
54	189	1
55	20	5
55	82	1
55	95	3
55	141	1
55	178	2
56	35	1
56	84	1
56	111	1
56	111	3
56	111	4
56	127	2
56	130	3
56	134	1
57	33	2
57	33	4
57	65	1
57	65	2
57	65	3
57	65	4
57	114	2
57	118	3
57	122	1
57	162	1
58	10	1
58	10	3
58	17	4
58	23	2
58	23	5
58	127	1
58	159	2
58	159	3
58	161	2
58	174	1
59	36	1
59	117	1
59	123	1
59	123	2
59	125	1
59	126	1
59	126	2
59	146	1
59	146	2
59	146	3
59	155	2
59	155	3
59	195	1
60	22	3
60	48	1
60	56	1
60	56	3
60	124	2
60	170	2
60	190	2
61	18	1
61	18	4
61	33	3
61	68	1
61	68	2
61	76	1
61	76	4
61	85	1
61	85	2
61	116	2
61	176	2
62	19	1
62	19	5
62	41	3
62	192	1
63	86	2
63	107	1
64	7	1
64	49	1
64	181	1
65	17	2
65	17	5
65	31	4
65	69	1
65	74	1
65	92	1
65	102	2
65	102	4
65	141	5
65	158	1
66	44	2
66	44	3
66	47	2
66	48	2
66	93	2
66	101	2
66	103	2
66	109	1
66	109	4
66	111	2
66	111	4
66	140	3
66	160	5
67	2	1
67	2	3
67	34	1
67	34	2
67	41	4
67	71	1
68	80	3
68	165	1
68	189	1
69	73	1
69	128	3
69	136	2
70	46	1
70	46	2
70	46	3
70	46	4
70	60	1
70	60	4
70	106	2
70	183	1
70	197	1
71	96	2
71	96	3
71	125	1
71	125	2
72	55	3
72	177	1
73	11	1
73	11	2
73	11	3
73	69	2
73	83	1
73	148	1
73	148	4
73	158	3
73	164	1
74	24	3
74	46	2
74	102	1
74	102	3
74	102	5
74	125	3
74	154	3
74	154	5
74	186	1
75	85	2
75	151	1
75	158	2
75	167	1
76	34	1
76	34	4
76	34	5
76	49	3
76	122	1
76	122	2
76	129	1
76	129	2
76	148	2
77	27	2
77	28	2
77	59	2
77	124	1
77	124	3
78	121	1
78	121	3
78	121	4
79	15	1
79	15	3
79	15	4
79	15	5
79	37	3
79	37	5
79	89	1
79	89	5
79	190	1
80	70	1
81	2	5
81	44	1
81	50	1
81	50	2
81	62	1
81	76	2
81	98	3
81	105	2
81	135	1
82	126	3
82	130	3
83	35	2
83	35	4
84	1	2
84	55	1
84	55	2
84	55	3
84	55	4
84	55	5
84	68	1
84	68	2
84	71	1
84	91	2
84	152	4
84	152	5
84	153	4
84	153	5
84	185	1
85	57	4
85	67	1
85	78	1
85	137	2
85	172	1
86	61	2
86	61	5
87	51	1
87	70	3
87	92	3
87	92	4
87	132	3
88	94	4
89	49	3
89	76	2
89	76	3
89	167	1
89	183	1
90	15	4
90	22	2
90	93	3
90	100	2
90	135	3
90	135	5
90	176	2
91	24	2
91	79	1
91	79	5
91	182	1
92	41	1
92	41	2
92	68	1
92	68	2
92	68	3
92	80	1
92	98	1
92	98	2
92	98	4
92	98	5
92	111	1
92	147	2
92	147	3
92	191	2
93	23	2
93	23	3
93	23	4
93	35	1
93	35	3
93	35	5
93	93	2
93	100	3
93	100	5
93	121	1
93	202	2
94	21	2
94	87	2
94	169	1
94	180	1
95	5	1
95	157	1
96	45	4
96	45	5
96	74	2
96	76	1
96	112	1
97	3	1
97	47	3
97	108	1
97	132	1
97	132	4
97	151	1
97	151	3
98	19	5
98	25	1
98	25	2
98	114	2
98	116	1
98	116	3
99	24	1
99	24	2
99	40	1
99	40	2
99	90	1
99	121	3
100	86	3
100	115	1
100	115	2
100	119	2
100	119	3
100	119	4
100	119	5
100	202	2
101	2	5
101	67	3
101	75	2
101	75	3
101	75	4
101	80	1
101	80	2
101	86	2
101	94	1
101	94	4
101	138	1
101	138	2
102	45	5
102	85	1
102	128	2
102	128	4
102	144	1
102	180	1
103	8	1
103	140	1
103	156	4
104	21	1
104	49	3
104	132	2
104	132	4
104	176	1
104	182	2
104	190	1
105	30	2
105	47	2
105	47	3
105	63	2
106	33	4
106	36	2
106	55	4
106	66	2
106	66	3
106	69	1
106	91	2
106	91	3
106	91	4
106	178	2
107	90	3
107	96	3
107	145	2
107	145	3
107	154	2
107	154	4
107	158	4
108	34	2
108	47	1
108	145	3
108	197	1
108	197	2
108	201	1
109	1	1
109	194	1
110	17	5
110	89	2
110	89	4
110	89	5
110	105	1
110	118	1
110	118	3
110	118	4
110	133	2
110	133	3
110	137	1
110	137	3
110	137	4
110	152	1
111	32	1
111	78	2
111	162	1
112	54	2
112	71	2
113	133	3
113	159	4
113	172	1
114	92	3
114	195	2
115	33	1
115	143	1
115	170	2
116	6	2
116	37	4
116	111	2
116	111	3
117	58	1
117	81	3
117	123	1
117	167	2
117	196	2
118	105	1
119	11	5
119	48	1
119	80	3
119	89	2
119	89	4
119	161	1
119	202	1
120	58	2
120	188	1
121	10	2
121	10	3
121	67	3
122	2	1
122	72	2
122	72	3
122	77	2
123	52	1
123	52	2
123	101	2
123	151	2
124	41	3
124	118	2
124	118	5
125	3	4
126	11	1
126	11	2
126	107	1
126	107	2
126	142	3
126	155	1
126	155	2
126	155	5
126	179	2
127	8	2
127	8	3
127	66	2
127	83	1
127	83	3
127	99	1
128	52	1
128	52	4
128	113	1
128	113	2
128	113	4
129	13	2
129	52	4
129	52	5
129	77	1
129	99	2
129	99	3
129	99	4
129	116	1
129	183	1
129	202	2
130	59	3
130	102	4
130	102	5
130	112	2
131	29	2
131	95	1
131	95	2
131	138	3
131	148	4
133	18	3
133	18	4
133	76	3
134	98	1
134	103	1
134	109	1
134	161	1
134	161	2
134	192	1
134	202	2
135	30	3
135	65	3
135	65	4
135	65	5
135	199	1
135	199	2
136	57	1
136	57	2
136	61	1
136	61	4
136	151	2
136	198	1
136	198	2
136	199	1
137	130	3
137	159	2
137	159	4
137	159	5
137	178	1
137	205	1
138	30	2
138	30	3
138	147	1
138	160	2
139	12	1
139	101	1
139	101	2
140	25	1
140	54	1
140	62	2
140	77	2
140	122	2
140	163	1
140	171	2
141	38	1
141	127	1
141	148	1
142	45	2
142	55	1
142	55	5
142	88	3
142	88	4
142	144	2
142	144	3
143	17	2
143	17	3
143	111	3
143	140	2
143	147	3
143	147	4
144	6	3
144	39	1
144	39	2
144	118	2
144	152	2
144	152	3
145	55	1
145	93	1
145	124	2
145	124	3
145	131	1
145	131	3
145	167	1
145	167	2
145	202	1
146	102	1
146	102	2
146	103	1
146	117	3
146	138	2
146	158	3
146	166	1
146	178	1
147	18	3
147	18	5
147	22	3
147	78	1
147	78	2
147	121	2
147	123	2
148	29	1
148	29	2
148	34	2
148	34	5
148	43	4
148	72	1
148	72	2
148	72	3
148	72	5
148	115	2
149	41	2
149	76	4
149	112	3
150	9	1
150	67	3
150	100	4
150	100	5
150	145	1
150	170	1
150	170	2
150	184	1
151	45	1
151	59	2
151	59	3
151	150	3
152	40	1
152	40	2
152	45	1
152	92	1
152	157	1
152	157	2
153	14	2
153	66	1
153	93	1
153	120	1
153	120	3
153	138	2
153	163	1
154	38	1
154	38	2
154	38	3
154	70	1
155	16	1
155	16	2
155	53	2
155	108	2
155	109	4
155	114	1
155	132	1
155	132	2
155	132	4
155	141	3
155	149	2
155	149	3
155	166	1
155	166	2
155	191	1
156	6	3
156	18	2
156	72	2
156	72	3
156	72	4
156	72	5
156	78	2
156	126	2
157	6	5
157	19	2
157	19	3
157	19	4
157	60	3
157	60	4
157	82	2
157	107	2
157	149	3
157	179	2
158	50	2
158	77	2
158	156	3
158	194	1
159	7	2
159	98	3
159	149	1
159	149	2
159	158	1
159	158	2
159	158	4
160	19	1
160	19	5
160	23	2
160	23	5
160	42	2
160	43	1
160	43	2
160	76	3
160	143	1
160	160	5
161	63	2
161	63	3
161	74	1
161	75	1
161	129	3
161	180	2
162	20	5
162	21	3
162	83	3
162	83	4
162	155	4
163	104	2
163	141	1
163	141	2
163	164	2
164	6	2
164	19	2
164	128	1
164	163	1
165	2	3
165	41	1
165	41	3
165	56	2
165	56	3
165	88	1
165	88	2
165	96	1
165	135	4
166	124	2
166	124	3
166	189	1
167	3	2
167	3	4
167	160	3
167	160	5
168	18	1
168	18	4
168	106	1
168	106	2
169	33	3
169	95	2
169	120	1
169	120	2
169	191	2
169	205	2
170	23	4
170	23	5
170	103	1
170	140	5
170	179	1
171	62	2
171	90	4
171	96	1
171	114	2
171	180	1
172	84	2
172	128	4
172	147	1
172	147	2
173	20	3
173	20	4
173	30	1
173	30	2
173	144	1
174	15	1
174	15	2
174	15	4
174	135	2
174	135	4
175	33	1
175	53	2
175	94	3
175	117	3
175	126	1
175	159	3
175	175	1
175	185	1
176	2	4
176	32	3
176	171	1
176	171	2
177	11	4
177	69	1
178	9	1
178	9	2
178	9	3
178	26	2
178	26	3
178	26	5
178	27	1
178	36	2
178	101	1
178	132	3
178	201	1
179	43	2
179	43	5
179	67	2
179	113	1
179	113	4
179	187	1
180	40	1
180	184	1
180	189	1
181	16	1
181	16	2
181	46	2
181	133	1
181	138	1
181	138	3
181	159	1
182	22	1
182	22	3
182	29	2
182	43	1
182	52	3
182	72	4
182	114	1
182	161	2
183	57	3
183	139	4
183	148	3
184	83	2
184	112	2
184	152	4
184	152	5
184	168	1
185	21	3
185	201	1
186	115	1
186	115	2
186	152	3
186	152	4
186	185	1
187	45	2
187	45	3
188	127	1
188	188	1
189	143	2
191	4	2
191	63	3
191	88	1
191	88	3
191	92	4
191	99	3
191	102	3
191	104	1
191	121	4
192	60	1
192	60	2
192	60	4
192	144	3
193	19	5
193	43	1
193	43	4
193	118	1
193	127	1
193	127	2
193	158	3
193	158	4
194	56	5
194	100	2
194	130	2
194	130	3
194	135	4
194	183	1
195	96	2
195	105	2
196	82	1
196	82	3
196	86	1
196	86	3
196	111	2
196	133	2
196	179	1
197	3	2
197	3	3
197	10	1
197	10	2
197	13	1
197	78	2
197	156	3
198	11	5
198	24	1
198	50	1
198	50	2
198	60	5
198	110	2
198	136	4
198	174	1
199	31	1
199	31	2
199	118	2
199	118	5
199	140	1
199	140	4
199	140	5
199	190	1
200	10	2
200	38	1
200	38	2
200	38	3
200	43	1
200	99	2
200	99	3
200	143	2
201	63	1
201	156	1
201	156	2
201	156	5
201	159	1
201	165	1
202	1	2
202	51	2
203	66	2
203	81	4
203	90	1
203	128	2
203	173	2
204	11	2
204	11	3
204	13	1
204	79	1
204	79	2
204	79	4
204	141	1
204	141	2
204	141	3
204	141	4
205	8	3
205	60	1
205	65	4
205	191	1
206	89	1
206	89	3
206	89	4
206	100	1
206	107	2
206	119	1
206	119	4
207	155	4
208	5	2
208	33	2
208	49	1
208	49	2
208	53	1
208	70	3
208	102	3
208	186	1
209	31	3
209	49	2
209	107	1
209	153	1
209	153	3
209	153	5
210	24	1
211	48	2
212	73	2
212	88	3
212	120	1
212	139	2
212	139	4
213	25	2
213	52	2
213	52	4
213	52	5
213	92	2
213	126	2
213	126	3
213	134	2
213	196	1
214	17	1
214	19	1
214	79	1
214	79	2
214	79	5
214	142	2
215	4	1
215	4	2
216	11	1
216	11	3
216	34	2
216	44	1
216	44	2
216	74	2
216	177	2
216	198	1
217	36	1
217	45	1
217	59	1
217	112	2
218	57	1
218	57	4
218	81	2
218	81	4
218	83	2
218	83	4
218	94	3
218	94	4
218	133	1
219	14	1
219	14	2
219	14	3
219	39	1
219	39	2
219	56	1
219	56	2
219	56	5
219	109	3
219	109	4
219	144	2
219	165	1
220	37	3
220	37	4
220	37	5
220	99	4
220	113	1
221	13	2
221	33	1
221	33	4
221	97	1
221	97	2
221	117	2
221	124	1
221	159	2
222	132	1
223	8	1
223	51	2
223	100	1
224	82	1
224	82	3
224	82	4
224	151	3
224	192	1
225	7	3
225	70	2
225	86	2
225	86	3
225	103	2
225	108	2
225	159	4
225	159	5
226	31	1
226	31	2
226	31	3
226	138	2
227	67	1
227	67	2
227	119	2
227	119	5
227	151	1
227	151	3
227	166	2
228	30	2
228	30	3
228	41	3
228	41	4
228	85	2
228	160	4
228	204	1
229	46	4
229	61	3
229	82	1
229	180	2
230	96	2
230	126	1
230	126	2
230	126	3
230	134	1
230	199	2
231	43	3
231	43	5
231	63	1
231	63	2
231	124	1
231	124	3
232	28	1
232	81	1
232	81	3
232	81	5
232	113	4
232	113	5
233	9	3
233	32	3
233	34	1
233	34	4
233	59	3
233	66	1
233	92	4
233	147	1
233	147	2
233	147	4
233	199	1
234	19	3
234	90	1
234	140	1
234	143	1
235	84	1
235	141	4
236	203	1
237	5	2
237	32	3
237	61	5
237	106	1
237	197	2
238	62	1
238	121	4
238	125	1
238	150	2
238	150	4
238	150	5
238	193	1
239	22	1
239	22	2
239	58	1
239	58	3
239	149	2
239	160	1
239	160	2
240	14	1
240	14	3
240	44	1
240	98	3
240	98	5
240	196	1
241	160	2
241	160	5
242	20	2
242	20	3
242	20	5
242	54	1
242	61	2
242	88	4
242	97	2
242	112	2
242	112	3
242	138	1
242	152	5
243	26	3
243	26	4
243	26	5
243	51	3
243	51	4
243	177	2
243	204	1
244	66	3
244	89	3
244	89	5
244	93	2
244	179	2
245	69	2
245	87	2
245	125	1
245	125	3
245	177	1
245	179	1
246	22	1
246	22	3
246	24	2
246	24	3
246	34	3
246	34	4
246	56	4
246	56	5
246	63	2
246	91	2
246	91	4
246	103	1
246	103	2
246	131	1
246	131	3
247	99	3
247	142	1
247	142	2
247	156	2
248	42	2
248	46	4
248	117	1
249	31	1
249	31	2
249	31	3
249	156	5
250	17	4
250	77	1
250	77	2
250	87	2
250	151	2
251	35	2
251	35	4
251	61	3
251	61	5
251	66	1
251	66	2
251	131	1
251	131	2
251	171	1
251	171	2
252	2	1
252	2	2
252	2	4
252	137	2
252	137	3
252	137	4
252	176	2
252	203	1
253	79	4
253	79	5
253	99	1
253	99	4
253	107	1
253	107	2
254	4	2
254	30	1
254	56	1
254	56	5
254	100	3
254	121	1
254	121	2
254	199	1
256	23	1
256	23	4
256	48	2
256	61	4
256	87	1
256	105	1
256	119	1
256	119	4
256	119	5
256	138	1
256	138	3
256	145	1
256	145	2
256	176	1
256	176	2
257	33	1
257	33	4
257	88	2
257	88	3
257	88	4
257	129	2
257	174	1
258	69	2
258	129	4
259	25	1
259	25	2
259	128	4
259	152	1
259	155	1
260	39	3
260	91	2
260	91	3
260	112	3
260	128	1
260	128	2
260	128	3
260	146	1
260	146	3
260	148	3
260	148	4
260	152	4
260	152	5
261	5	1
261	37	4
261	92	3
261	164	1
262	3	1
262	3	3
262	18	1
262	18	3
262	18	4
262	18	5
262	109	2
262	109	4
263	10	3
263	83	1
263	83	2
263	83	3
263	99	4
263	166	1
263	166	2
263	204	1
264	6	1
264	6	3
264	6	4
264	6	5
264	117	1
264	117	2
264	162	1
265	26	2
265	26	4
265	63	1
265	63	3
265	64	3
265	89	3
265	119	1
265	119	2
265	143	2
266	190	2
267	14	2
267	169	1
267	200	1
267	205	1
267	205	2
268	155	3
268	155	5
269	11	2
269	11	3
269	11	4
269	20	1
269	20	2
269	20	5
269	70	1
269	70	3
270	32	1
270	34	1
270	34	3
270	64	1
270	142	1
270	142	2
270	142	3
271	7	3
271	7	4
271	8	3
271	17	5
271	100	4
271	113	2
271	113	3
271	146	2
271	146	4
271	152	1
271	152	2
271	152	3
271	176	1
272	17	1
272	17	4
272	147	2
272	147	4
273	17	1
273	27	2
273	73	1
273	118	3
274	37	5
274	38	3
274	45	3
274	45	4
274	45	5
274	139	1
274	139	4
274	165	1
275	10	2
275	10	3
275	28	2
275	54	1
275	54	2
275	86	1
275	119	3
275	119	4
275	191	2
276	5	2
276	21	2
276	26	1
276	26	4
276	32	2
276	32	3
276	56	2
276	72	3
276	90	2
276	90	5
276	93	1
276	198	2
277	2	2
277	2	4
277	95	1
277	95	2
277	95	3
277	110	1
278	35	5
278	79	1
278	79	2
278	108	1
278	198	1
278	198	2
279	31	2
279	31	3
279	31	4
279	51	4
280	75	1
281	134	1
281	136	2
281	136	3
281	147	1
281	147	3
281	170	1
282	24	2
282	56	4
282	131	1
282	133	1
282	133	2
282	133	3
283	57	1
283	57	2
283	129	1
283	129	3
283	129	4
284	1	2
284	5	1
284	15	3
284	18	1
284	18	5
284	97	1
284	120	2
285	42	1
285	71	2
285	167	1
285	167	2
286	51	1
286	51	3
286	92	3
286	98	1
286	98	2
286	158	1
286	172	1
287	6	4
287	79	3
287	85	2
288	2	1
288	2	3
288	48	1
288	58	2
288	58	3
289	44	2
289	44	3
289	60	3
289	60	5
289	73	2
289	179	1
289	180	1
289	180	2
290	8	2
290	8	5
290	43	3
290	43	5
290	61	1
290	61	2
290	130	1
290	148	1
290	148	4
290	148	5
291	178	1
292	15	2
292	72	5
292	74	1
293	12	1
293	129	3
293	146	2
293	146	3
293	149	1
293	149	3
293	199	2
294	36	2
294	90	5
294	160	1
294	160	4
294	184	1
295	6	2
295	6	5
295	8	4
295	13	1
295	17	3
295	51	3
295	75	2
295	75	3
295	75	4
295	108	2
295	192	2
295	195	1
295	195	2
296	26	1
296	26	3
296	37	1
296	74	2
296	90	2
296	90	3
296	90	4
296	104	1
296	104	3
297	22	2
297	22	4
297	41	2
297	70	1
297	70	2
297	91	1
297	164	2
298	20	3
298	75	1
298	75	2
298	104	3
298	124	1
298	133	3
298	142	3
298	186	1
299	53	2
299	89	5
300	60	2
300	72	1
300	87	1
300	106	2
300	196	1
300	203	1
301	87	2
301	154	2
301	154	3
301	154	5
302	66	3
302	78	1
302	83	3
302	101	1
302	118	4
302	200	1
303	47	1
303	91	1
303	91	3
303	139	3
304	118	5
304	166	1
305	37	1
305	140	4
305	159	4
305	190	2
306	53	1
306	97	1
306	104	1
306	104	3
306	186	1
307	20	3
307	20	4
307	72	4
307	150	1
307	150	5
308	21	2
308	23	1
308	23	2
308	46	3
308	191	2
309	23	1
309	23	3
309	23	5
309	175	1
310	95	2
310	135	1
310	135	3
310	140	2
311	7	3
311	47	1
311	47	2
311	47	4
311	57	1
311	57	2
311	63	1
311	80	2
311	90	2
311	90	3
311	102	2
311	102	3
311	157	1
311	157	2
312	17	1
312	22	2
312	22	4
312	65	4
312	91	1
312	91	3
312	118	5
312	131	2
312	131	3
312	139	1
312	139	2
312	139	3
312	173	1
313	113	1
313	113	5
313	164	1
313	198	1
313	198	2
314	90	4
314	112	1
314	113	4
314	156	5
314	201	1
315	82	2
315	155	4
316	11	1
316	11	5
316	15	1
316	15	2
316	120	1
316	120	3
316	141	4
317	190	2
318	12	2
318	21	1
318	35	3
318	84	1
318	84	2
318	134	2
318	151	1
319	42	1
319	42	2
319	59	1
319	75	1
319	116	2
319	136	1
319	136	2
319	136	4
319	141	1
319	141	4
319	141	5
319	153	1
319	155	3
319	196	1
320	3	4
320	9	3
320	60	5
320	83	4
320	143	1
320	143	2
\.


--
-- Data for Name: membre_pc; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.membre_pc (id_personne, id_conf) FROM stdin;
1	1
1	2
1	3
1	4
1	5
1	6
1	7
1	8
1	81
1	90
1	98
1	170
1	184
1	191
2	3
2	13
2	15
2	41
2	45
2	65
2	88
2	93
2	104
2	139
2	143
2	149
2	190
2	194
3	100
3	104
3	109
3	148
3	188
3	203
4	44
4	74
4	169
5	37
5	62
5	65
5	81
5	114
5	148
5	154
5	175
5	177
5	180
5	187
6	6
6	18
6	25
6	69
6	100
6	113
6	190
6	204
7	66
7	101
7	114
7	122
7	130
7	152
7	160
7	185
7	203
8	7
8	26
8	111
8	120
8	177
8	180
8	183
9	4
9	28
9	43
9	89
9	126
9	189
9	200
10	9
10	94
10	129
10	133
10	135
10	173
11	32
11	46
11	94
11	134
11	146
11	160
11	161
11	174
11	191
12	3
12	10
12	65
12	77
12	93
12	156
12	193
13	40
13	58
13	66
13	67
13	121
13	156
13	173
13	183
14	6
14	9
14	20
14	40
14	58
14	71
14	151
14	192
15	29
15	42
15	88
15	136
15	154
15	198
16	12
16	44
16	50
16	102
16	135
16	156
16	159
16	162
17	35
17	47
17	55
17	59
17	62
17	71
17	77
17	94
17	103
17	136
17	159
17	181
17	186
17	196
17	200
18	85
18	101
18	139
18	153
18	197
19	16
19	19
19	27
19	36
19	38
19	68
19	73
19	126
19	135
19	194
20	29
20	37
20	82
20	107
20	109
20	154
20	185
21	16
21	32
21	55
21	70
21	87
21	175
21	184
21	191
22	96
22	131
22	169
22	176
22	181
23	37
23	42
23	48
23	61
23	96
23	115
23	202
24	1
24	7
24	13
24	28
24	32
24	41
24	60
24	84
24	113
24	130
24	152
24	161
25	15
25	20
25	35
25	37
25	74
25	83
25	85
25	94
25	157
25	161
25	162
25	182
26	20
26	64
26	78
26	140
26	146
26	153
26	171
27	45
27	53
27	64
27	81
27	141
28	16
28	140
28	144
28	148
29	35
29	66
29	82
29	117
29	156
30	7
30	14
30	21
30	26
30	39
30	45
30	75
30	106
30	132
30	144
30	150
30	171
31	16
31	32
31	52
31	82
31	150
31	156
31	181
32	4
32	17
32	70
32	99
32	120
32	130
32	155
32	159
33	2
33	30
33	36
33	54
33	76
33	83
33	105
33	125
33	126
33	175
34	4
34	23
34	70
34	101
34	117
34	161
34	182
35	3
35	39
35	40
35	68
35	90
35	94
35	101
35	108
35	193
36	22
36	49
36	57
36	80
36	82
36	86
36	182
36	197
36	201
37	18
37	53
37	74
37	92
37	124
37	153
37	169
37	177
38	23
38	30
38	31
38	78
38	100
38	143
39	8
39	35
39	38
39	110
39	198
40	137
40	199
41	119
41	168
42	45
42	64
42	79
42	92
42	123
42	127
42	137
42	157
42	178
42	188
43	4
43	12
43	65
43	97
43	136
43	158
43	168
43	190
43	194
44	62
44	79
44	164
44	183
45	77
45	98
45	110
45	116
45	120
45	130
45	181
45	182
45	189
45	194
46	27
46	49
46	70
46	75
46	109
46	122
46	149
46	150
46	191
47	11
47	17
47	19
47	20
47	21
47	43
47	118
47	129
47	148
48	58
48	76
48	78
48	103
48	104
48	134
48	169
49	14
49	47
49	97
49	187
49	202
50	53
50	71
50	121
50	132
50	138
51	53
51	95
51	173
51	191
52	28
52	63
52	94
52	100
52	128
52	129
52	150
52	153
52	154
52	166
52	167
52	170
52	193
52	195
53	10
53	69
53	76
53	108
53	111
53	144
53	196
54	57
54	77
54	93
54	101
54	114
54	134
54	185
54	189
55	20
55	49
55	66
55	82
55	95
55	123
55	141
55	178
56	5
56	29
56	35
56	84
56	92
56	111
56	127
56	130
56	134
56	181
56	185
57	2
57	33
57	65
57	103
57	114
57	118
57	122
57	150
57	162
57	167
57	189
58	10
58	17
58	23
58	90
58	127
58	159
58	161
58	174
59	9
59	36
59	48
59	51
59	115
59	117
59	123
59	125
59	126
59	146
59	155
59	195
60	22
60	48
60	56
60	123
60	124
60	170
60	190
60	191
60	203
60	204
61	18
61	33
61	68
61	76
61	85
61	116
61	131
61	176
62	19
62	35
62	41
62	42
62	61
62	168
62	192
63	32
63	73
63	86
63	107
63	123
63	164
63	165
63	179
64	7
64	33
64	49
64	140
64	181
64	198
64	201
65	1
65	17
65	31
65	69
65	74
65	78
65	92
65	102
65	141
65	142
65	158
65	176
66	44
66	47
66	48
66	75
66	93
66	101
66	103
66	105
66	109
66	111
66	140
66	151
66	160
66	195
67	2
67	34
67	41
67	71
67	77
67	108
67	157
68	36
68	80
68	82
68	83
68	104
68	165
68	189
69	73
69	86
69	128
69	136
69	143
69	157
70	46
70	60
70	63
70	106
70	169
70	181
70	183
70	197
71	51
71	96
71	115
71	120
71	125
72	48
72	55
72	177
73	11
73	69
73	83
73	106
73	148
73	158
73	164
73	196
74	24
74	42
74	46
74	102
74	125
74	152
74	154
74	176
74	186
75	14
75	85
75	151
75	158
75	167
76	34
76	49
76	76
76	86
76	110
76	122
76	129
76	148
77	16
77	27
77	28
77	59
77	106
77	124
77	151
78	9
78	16
78	121
78	124
78	164
78	182
79	7
79	15
79	32
79	37
79	89
79	162
79	177
79	190
79	201
80	70
80	173
80	175
81	2
81	27
81	41
81	44
81	50
81	62
81	69
81	76
81	98
81	105
81	116
81	135
81	178
81	181
81	187
82	126
82	130
82	131
82	148
82	184
83	5
83	35
83	73
83	168
83	205
84	1
84	15
84	55
84	68
84	71
84	91
84	152
84	153
84	185
84	187
84	195
85	57
85	67
85	78
85	93
85	103
85	137
85	172
85	189
86	45
86	61
86	84
86	106
86	110
86	186
86	189
86	204
87	51
87	70
87	92
87	119
87	132
87	143
87	177
88	5
88	14
88	94
88	133
88	176
88	186
89	49
89	76
89	100
89	113
89	123
89	167
89	183
90	15
90	22
90	36
90	80
90	93
90	95
90	100
90	103
90	109
90	135
90	140
90	145
90	176
90	184
90	205
91	24
91	79
91	97
91	138
91	182
91	196
92	41
92	68
92	80
92	98
92	111
92	147
92	191
92	197
93	23
93	35
93	93
93	100
93	121
93	166
93	181
93	202
94	21
94	30
94	44
94	50
94	87
94	160
94	169
94	177
94	178
94	180
94	188
94	189
94	190
94	195
95	5
95	27
95	59
95	121
95	137
95	157
96	41
96	45
96	74
96	76
96	112
96	149
96	202
96	204
97	3
97	12
97	16
97	47
97	108
97	121
97	132
97	151
97	192
98	19
98	25
98	83
98	114
98	116
99	24
99	40
99	90
99	104
99	121
99	133
99	143
99	196
100	86
100	115
100	119
100	133
100	180
100	183
100	202
101	2
101	29
101	67
101	75
101	80
101	86
101	94
101	138
101	182
101	192
101	205
102	45
102	80
102	85
102	127
102	128
102	144
102	163
102	173
102	180
102	203
103	8
103	140
103	156
103	180
103	201
104	8
104	21
104	49
104	115
104	132
104	138
104	169
104	176
104	182
104	186
104	190
105	30
105	47
105	49
105	54
105	63
105	197
106	33
106	36
106	55
106	66
106	69
106	91
106	143
106	178
107	90
107	96
107	110
107	145
107	154
107	158
108	34
108	47
108	145
108	167
108	197
108	201
109	1
109	4
109	16
109	87
109	169
109	194
110	9
110	17
110	20
110	89
110	105
110	106
110	118
110	133
110	137
110	152
110	158
110	184
111	9
111	24
111	32
111	73
111	78
111	131
111	162
111	195
111	200
112	6
112	54
112	71
112	169
113	19
113	105
113	133
113	159
113	172
113	178
113	203
114	92
114	183
114	195
115	29
115	33
115	36
115	94
115	103
115	143
115	145
115	170
115	171
116	6
116	37
116	111
116	168
116	193
117	44
117	58
117	81
117	123
117	167
117	196
117	201
118	25
118	31
118	53
118	105
118	113
118	193
118	201
119	7
119	11
119	48
119	80
119	89
119	146
119	156
119	161
119	200
119	202
120	58
120	188
120	205
121	10
121	12
121	40
121	67
121	153
121	158
121	163
121	166
121	167
122	2
122	72
122	77
122	175
123	27
123	52
123	59
123	97
123	101
123	151
123	161
123	188
124	19
124	25
124	41
124	96
124	118
124	140
125	3
125	197
126	11
126	107
126	142
126	155
126	165
126	179
127	8
127	66
127	83
127	99
127	163
128	52
128	69
128	107
128	113
128	130
128	157
128	174
128	187
128	199
128	202
129	8
129	13
129	52
129	56
129	77
129	99
129	116
129	117
129	170
129	183
129	202
130	59
130	102
130	112
130	116
130	172
130	191
131	29
131	95
131	138
131	148
132	175
133	18
133	76
134	83
134	98
134	103
134	109
134	161
134	192
134	200
134	202
135	30
135	55
135	65
135	80
135	161
135	167
135	190
135	199
135	200
136	27
136	41
136	57
136	61
136	110
136	151
136	164
136	192
136	198
136	199
137	44
137	59
137	130
137	159
137	178
137	205
138	30
138	53
138	120
138	147
138	160
139	8
139	12
139	101
139	182
139	202
140	25
140	54
140	62
140	77
140	87
140	117
140	122
140	145
140	163
140	171
140	175
140	186
140	205
141	34
141	38
141	127
141	148
141	150
142	19
142	45
142	53
142	55
142	88
142	144
143	17
143	80
143	105
143	111
143	140
143	147
143	199
144	6
144	39
144	101
144	112
144	118
144	152
144	182
145	55
145	81
145	93
145	96
145	124
145	131
145	143
145	167
145	168
145	201
145	202
146	36
146	102
146	103
146	116
146	117
146	138
146	158
146	166
146	178
147	18
147	22
147	78
147	121
147	123
147	157
147	169
148	29
148	34
148	43
148	71
148	72
148	115
148	148
149	41
149	76
149	112
149	126
149	164
150	9
150	28
150	44
150	48
150	67
150	100
150	145
150	170
150	184
150	193
151	45
151	59
151	85
151	130
151	146
151	150
151	162
151	172
151	195
152	10
152	40
152	45
152	92
152	105
152	106
152	157
152	194
152	200
153	14
153	66
153	82
153	93
153	120
153	125
153	138
153	139
153	144
153	163
153	165
153	197
154	36
154	38
154	64
154	70
154	170
154	199
155	16
155	53
155	108
155	109
155	114
155	132
155	141
155	149
155	166
155	191
156	6
156	18
156	44
156	72
156	78
156	84
156	98
156	126
156	186
156	203
157	6
157	19
157	60
157	82
157	107
157	149
157	179
158	50
158	77
158	106
158	117
158	156
158	194
158	200
159	7
159	9
159	98
159	149
159	158
160	18
160	19
160	23
160	42
160	43
160	76
160	100
160	143
160	160
160	171
160	183
161	63
161	74
161	75
161	129
161	180
161	201
161	204
162	1
162	20
162	21
162	46
162	51
162	52
162	71
162	83
162	155
162	173
162	175
162	177
162	179
163	13
163	48
163	82
163	104
163	130
163	137
163	141
163	157
163	162
163	164
164	6
164	10
164	19
164	28
164	70
164	81
164	128
164	163
164	194
165	2
165	24
165	41
165	56
165	88
165	96
165	135
165	163
165	177
165	179
165	193
166	7
166	117
166	124
166	189
166	204
167	3
167	87
167	160
167	175
168	1
168	18
168	106
168	197
168	205
169	13
169	33
169	92
169	95
169	108
169	120
169	170
169	191
169	193
169	205
170	23
170	50
170	103
170	140
170	168
170	179
171	17
171	62
171	84
171	90
171	96
171	114
171	163
171	180
172	9
172	84
172	128
172	147
172	172
172	199
173	20
173	21
173	30
173	38
173	66
173	105
173	123
173	144
173	150
174	15
174	36
174	40
174	69
174	84
174	135
174	185
174	196
175	5
175	32
175	33
175	53
175	68
175	94
175	117
175	126
175	159
175	175
175	185
175	190
176	2
176	32
176	49
176	70
176	122
176	171
177	11
177	69
177	71
177	104
177	159
177	164
177	188
178	9
178	26
178	27
178	36
178	101
178	131
178	132
178	199
178	201
179	39
179	43
179	67
179	113
179	187
179	194
180	2
180	40
180	120
180	145
180	184
180	189
181	16
181	22
181	46
181	74
181	125
181	132
181	133
181	138
181	147
181	152
181	159
182	22
182	29
182	43
182	47
182	52
182	72
182	78
182	114
182	117
182	148
182	157
182	161
183	57
183	139
183	148
183	161
184	83
184	112
184	114
184	152
184	165
184	168
184	179
185	2
185	21
185	52
185	61
185	120
185	123
185	201
186	12
186	63
186	115
186	152
186	185
187	4
187	45
187	48
187	85
187	123
187	125
187	154
187	180
188	46
188	127
188	163
188	188
189	3
189	49
189	69
189	109
189	117
189	143
189	200
191	4
191	63
191	88
191	92
191	99
191	102
191	104
191	120
191	121
191	162
191	188
191	197
192	59
192	60
192	73
192	133
192	144
192	181
192	194
193	19
193	39
193	43
193	118
193	127
193	158
193	174
194	56
194	86
194	100
194	130
194	135
194	141
194	172
194	180
194	183
194	187
195	96
195	105
195	137
196	15
196	82
196	86
196	111
196	133
196	179
196	185
197	3
197	10
197	13
197	15
197	23
197	78
197	98
197	104
197	156
198	11
198	24
198	28
198	50
198	60
198	82
198	88
198	90
198	110
198	136
198	144
198	174
198	180
199	21
199	31
199	103
199	118
199	123
199	140
199	190
199	196
199	200
200	10
200	38
200	43
200	90
200	99
200	143
200	179
200	184
201	63
201	156
201	159
201	165
202	1
202	51
202	124
203	21
203	66
203	81
203	90
203	128
203	147
203	173
204	11
204	13
204	37
204	70
204	79
204	141
204	174
204	179
205	8
205	60
205	65
205	78
205	115
205	191
205	195
205	205
206	89
206	100
206	107
206	119
206	139
206	188
206	189
207	110
207	138
207	143
207	155
208	5
208	33
208	42
208	49
208	53
208	70
208	87
208	102
208	114
208	165
208	186
208	195
209	31
209	49
209	107
209	153
209	194
210	13
210	23
210	24
210	32
210	108
210	189
211	48
211	76
211	128
211	154
211	175
212	59
212	73
212	88
212	92
212	120
212	139
212	164
213	25
213	40
213	52
213	92
213	126
213	134
213	175
213	196
214	17
214	19
214	79
214	130
214	142
214	172
215	4
215	69
215	173
216	7
216	11
216	34
216	37
216	44
216	74
216	100
216	177
216	191
216	198
216	205
217	36
217	45
217	59
217	84
217	112
217	117
217	137
217	170
217	181
217	196
218	40
218	57
218	81
218	83
218	94
218	133
218	164
218	185
219	14
219	39
219	55
219	56
219	109
219	143
219	144
219	165
220	37
220	99
220	110
220	113
220	127
220	176
220	190
221	5
221	13
221	21
221	33
221	38
221	64
221	97
221	117
221	124
221	159
221	186
222	116
222	132
223	8
223	51
223	68
223	100
223	114
223	148
223	203
224	63
224	82
224	88
224	91
224	151
224	192
225	7
225	24
225	28
225	54
225	65
225	70
225	86
225	103
225	108
225	159
225	169
225	184
226	31
226	61
226	67
226	138
226	187
227	2
227	67
227	69
227	112
227	119
227	151
227	157
227	166
227	167
227	176
227	198
228	30
228	41
228	85
228	144
228	160
228	163
228	204
229	46
229	61
229	82
229	106
229	180
230	40
230	83
230	96
230	126
230	134
230	152
230	160
230	182
230	199
231	21
231	29
231	43
231	63
231	77
231	124
231	142
231	170
231	191
232	28
232	81
232	113
232	171
233	9
233	32
233	34
233	59
233	66
233	92
233	130
233	137
233	147
233	184
233	199
234	14
234	19
234	39
234	90
234	140
234	143
234	174
235	26
235	35
235	62
235	84
235	131
235	141
235	190
236	73
236	110
236	163
236	202
236	203
237	5
237	13
237	32
237	59
237	61
237	91
237	106
237	112
237	152
237	197
237	199
238	62
238	114
238	121
238	125
238	150
238	183
238	193
238	201
239	22
239	58
239	149
239	160
240	14
240	44
240	98
240	196
241	36
241	48
241	160
241	189
242	4
242	20
242	54
242	61
242	84
242	88
242	97
242	112
242	138
242	152
243	26
243	37
243	51
243	67
243	177
243	204
244	9
244	44
244	66
244	89
244	93
244	179
244	197
244	205
245	1
245	69
245	73
245	87
245	125
245	177
245	179
245	205
246	22
246	24
246	34
246	56
246	63
246	90
246	91
246	103
246	131
246	185
247	99
247	101
247	105
247	124
247	142
247	156
247	187
248	22
248	42
248	46
248	62
248	117
248	121
249	31
249	74
249	83
249	132
249	156
249	170
249	198
250	17
250	77
250	87
250	106
250	151
251	10
251	27
251	35
251	39
251	61
251	66
251	101
251	131
251	171
252	2
252	8
252	51
252	137
252	176
252	194
252	203
252	204
253	13
253	63
253	74
253	79
253	99
253	107
253	142
254	4
254	30
254	44
254	51
254	56
254	100
254	121
254	123
254	169
254	199
255	92
255	140
255	141
255	175
256	23
256	27
256	48
256	61
256	84
256	87
256	105
256	119
256	121
256	138
256	145
256	176
256	204
257	19
257	33
257	88
257	129
257	134
257	174
258	25
258	50
258	69
258	129
258	140
258	201
259	25
259	128
259	152
259	155
259	179
259	182
259	188
260	39
260	68
260	91
260	105
260	112
260	128
260	146
260	148
260	152
261	5
261	37
261	92
261	164
262	3
262	18
262	57
262	97
262	109
262	130
263	10
263	83
263	99
263	166
263	200
263	204
264	6
264	71
264	78
264	116
264	117
264	162
265	26
265	63
265	64
265	73
265	89
265	119
265	138
265	143
265	186
266	35
266	45
266	48
266	190
267	14
267	169
267	189
267	200
267	205
268	135
268	155
269	11
269	20
269	40
269	48
269	70
269	71
269	158
269	163
269	176
270	32
270	34
270	46
270	49
270	54
270	64
270	80
270	142
270	179
270	202
271	7
271	8
271	17
271	100
271	113
271	146
271	152
271	176
271	177
271	186
272	17
272	86
272	87
272	147
272	180
273	17
273	27
273	73
273	113
273	118
273	142
274	28
274	37
274	38
274	45
274	102
274	139
274	165
274	194
275	10
275	28
275	54
275	81
275	86
275	119
275	190
275	191
276	5
276	21
276	26
276	32
276	56
276	65
276	72
276	78
276	90
276	93
276	113
276	156
276	191
276	198
277	2
277	32
277	95
277	110
278	9
278	35
278	79
278	98
278	108
278	184
278	198
279	7
279	31
279	51
279	71
279	161
280	75
280	76
280	122
280	173
280	178
280	203
281	109
281	134
281	136
281	147
281	170
282	24
282	56
282	131
282	133
282	149
282	151
282	155
282	174
282	181
283	57
283	74
283	129
284	1
284	5
284	15
284	18
284	55
284	97
284	120
284	195
285	42
285	64
285	71
285	80
285	138
285	156
285	167
285	202
286	6
286	51
286	92
286	98
286	158
286	159
286	161
286	172
287	6
287	77
287	79
287	85
287	187
288	2
288	4
288	16
288	48
288	58
288	165
288	169
289	44
289	60
289	73
289	75
289	82
289	179
289	180
290	8
290	43
290	61
290	75
290	130
290	148
290	194
291	78
291	178
292	7
292	15
292	54
292	72
292	74
292	80
292	84
292	175
293	12
293	53
293	77
293	129
293	146
293	149
293	186
293	199
294	36
294	51
294	64
294	66
294	75
294	90
294	95
294	121
294	160
294	184
294	203
295	6
295	8
295	13
295	17
295	51
295	75
295	108
295	136
295	192
295	194
295	195
296	11
296	26
296	37
296	53
296	74
296	90
296	104
296	105
297	22
297	41
297	70
297	91
297	163
297	164
298	16
298	20
298	25
298	75
298	104
298	106
298	124
298	133
298	142
298	186
298	197
299	53
299	84
299	89
300	60
300	72
300	87
300	106
300	196
300	203
301	59
301	87
301	154
301	200
302	66
302	78
302	83
302	85
302	101
302	118
302	164
302	184
302	200
303	47
303	77
303	91
303	139
303	180
304	80
304	118
304	166
304	173
304	185
304	193
304	203
305	37
305	49
305	140
305	159
305	162
305	190
306	21
306	53
306	97
306	104
306	178
306	186
307	13
307	19
307	20
307	27
307	33
307	49
307	62
307	72
307	98
307	150
307	205
308	10
308	12
308	21
308	23
308	46
308	107
308	186
308	191
309	23
309	96
309	175
309	188
309	193
309	203
310	84
310	95
310	122
310	133
310	135
310	140
310	161
311	7
311	16
311	47
311	57
311	63
311	73
311	80
311	90
311	102
311	157
312	17
312	22
312	25
312	50
312	65
312	91
312	118
312	120
312	131
312	139
312	173
313	12
313	93
313	113
313	164
313	167
313	173
313	195
313	198
314	13
314	90
314	112
314	113
314	156
314	159
314	162
314	182
314	188
314	193
314	201
314	202
315	82
315	155
315	169
315	188
316	11
316	12
316	13
316	14
316	15
316	17
316	58
316	120
316	141
316	151
316	181
316	193
317	54
317	190
317	203
318	8
318	12
318	21
318	33
318	35
318	84
318	123
318	134
318	151
319	2
319	42
319	59
319	68
319	75
319	116
319	136
319	141
319	153
319	155
319	196
320	3
320	9
320	29
320	60
320	83
320	143
\.


--
-- Data for Name: organisme; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.organisme (id_organisme, nom, adresse, email_contact) FROM stdin;
1	École Centrale de Lyon	chemin de Moulin, Lyon	conferences@écolecentral.edu
2	Université Claude Bernard Lyon 1	181 Johnson Course, Lyon	conferences@universitécl.edu
3	Sorbonne Université	908 Jennifer Squares, Paris	conferences@sorbonneuniv.edu
4	Université Paris-Saclay	Pasaje Dolores Lobo 3 Puerta 6 , Paris	conferences@universitépa.edu
5	Université de Toulouse	Heinz-Dieter-Wiek-Ring 71, Toulouse	conferences@universitéde.edu
6	Université Grenoble Alpes	59, avenue Regnier, Grenoble	conferences@universitégr.edu
7	TU Berlin	9, boulevard Agnès Verdier, Berlin	conferences@tuberlin.edu
8	TU München	34131 Ramirez Roads, Munich	conferences@tumünchen.edu
9	Sapienza Università di Roma	Klappplatz 2/3, Rome	conferences@sapienzauniv.edu
10	Politecnico di Milano	Pasaje Reynaldo Lerma 135, Milan	conferences@politecnicod.edu
11	Universidad Politécnica de Madrid	6413 Lewis Parks, Madrid	conferences@universidadp.edu
12	Universitat de Barcelona	Contrada Elladio, 768 Appartamento 22, Barcelone	conferences@universitatd.edu
13	University of Edinburgh	rue Bazin, Édimbourg	conferences@universityof.edu
14	Imperial College London	Incrocio Scialpi, 8, Londres	conferences@imperialcoll.edu
15	TU Delft	Via de Lázaro Royo 17 Puerta 4 , Delft	conferences@tudelft.edu
16	KU Leuven	Cañada Prudencia Vera 632, Louvain	conferences@kuleuven.edu
17	ETH Zürich	570 Sarah Wells, Zurich	conferences@ethzürich.edu
18	EPFL	Ilija-Rosenow-Gasse 27, Lausanne	conferences@epfl.edu
19	Université de Montréal	Cuesta Carmela Dalmau 78, Montréal	conferences@universitéde.edu
20	University of Toronto	465 Lam Mission, Toronto	conferences@universityof.edu
21	MIT	61, boulevard Lenoir, Boston	conferences@mit.edu
22	Stanford University	10310 Jones Freeway, San Francisco	conferences@stanforduniv.edu
23	University of Tokyo	Auguste-Eigenwillig-Allee 73-47, Tokyo	conferences@universityof.edu
24	Tsinghua University	avenue de Monnier, Pékin	conferences@tsinghuauniv.edu
25	Universidade de São Paulo	Piazza Caironi, 26 Appartamento 33, São Paulo	conferences@universidade.edu
26	Université de Tunis El Manar	Viale Greco, 7, Tunis	conferences@universitéde.edu
27	University of Sydney	Urbanización Flavio Ramos 47, Sydney	conferences@universityof.edu
\.


--
-- Data for Name: pays; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.pays (id_pays, nom_pays) FROM stdin;
1	France
2	Allemagne
3	Italie
4	Espagne
5	Royaume-Uni
6	Pays-Bas
7	Belgique
8	Suisse
9	Canada
10	États-Unis
11	Japon
12	Chine
13	Brésil
14	Tunisie
15	Australie
\.


--
-- Data for Name: personne; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.personne (id_personne, nom, prenom, adresse_pro, email) FROM stdin;
1	Dupont	Jean	École Centrale de Lyon, 36 av. Guy de Collongue, Ecully	jean.dupont@univ-lyon.fr
2	Martin	Alice	Université Claude Bernard Lyon 1, Villeurbanne	alice.martin@univ-lyon.fr
3	Gray	Atenulf	Tsinghua University, Contrada Ramazzotti, 42 Appartamento 9	atenulf.gray@research.org
4	Mary	Bodo	TU München, Stretto Biagio, 1	bodo.mary@uni.edu
5	Hoz	Dante	Université de Toulouse, Ronda Gema Yáñez 44	dante.hoz@univ-lyon.fr
6	Kroker	Ignatz	Stanford University, 5107 Charles Forest Suite 251	ignatz.kroker@lab.eu
7	Kim	Mike	Sorbonne Université, Paseo Marcelino Calleja 24 Apt. 82 	mike.kim@lab.eu
8	Galvez	Karl-Peter	Imperial College London, Pärtzeltstraße 1/2	karlpeter.galvez@univ-lyon.fr
9	Beyer	Renata	École Centrale de Lyon, 34, avenue de Courtois	renata.beyer@univ-lyon.fr
10	Marie	Annamaria	TU Berlin, 18, boulevard Françoise Caron	annamaria.marie@uni.edu
11	Le Gall	Dionigi	ETH Zürich, Häringweg 7158	dionigi.legall@lab.eu
12	Frost	Maribel	École Centrale de Lyon, 60256 Joseph Turnpike	maribel.frost@lab.eu
13	Lelièvre	Alex	TU Berlin, 5433 Donna Locks	alex.lelievre@lab.eu
14	Leleu	Karl-Heinrich	Imperial College London, Stiebitzallee 50/31	karlheinrich.leleu@uni.edu
15	Nicolas	Juan Manuel	TU Delft, Alameda de Tristán Vidal 7 Puerta 3 	juanmanuel.nicolas@lab.eu
16	Abbagnale	Baldur	Sapienza Università di Roma, Ronda de Buenaventura Murillo 551	baldur.abbagnale@univ-lyon.fr
17	Mogherini	Martin	Universidade de São Paulo, Borgo Pierpaolo, 72 Piano 4	martin.mogherini@uni.edu
18	Montserrat	Russell	University of Tokyo, Canale Fuseli, 92 Piano 1	russell.montserrat@ec-lyon.fr
19	Drake	Emily	Universidad Politécnica de Madrid, 37917 Mercado Ports	emily.drake@research.org
20	Tagliafierro	Jennifer	Université de Toulouse, Canale Gloria, 41	jennifer.tagliafierro@uni.edu
21	Pascal	Abril	Universidade de São Paulo, 2788 Dodson Mills	abril.pascal@research.org
22	Roldan	Ofelia	Université Paris-Saclay, Cuesta Vinicio Jove 94 Piso 3 	ofelia.roldan@univ-lyon.fr
23	Delannoy	Theodor	University of Edinburgh, Kästerring 32	theodor.delannoy@univ-lyon.fr
24	Mccarthy	Patrick	Universitat de Barcelona, 95, avenue Charles Leclerc	patrick.mccarthy@research.org
25	Aller	Ottavio	University of Toronto, Plaza de Pastor Martín 96 Puerta 8 	ottavio.aller@research.org
26	Freeman	Tomasa	Université de Tunis El Manar, Baumstraße 86/32	tomasa.freeman@univ-lyon.fr
27	Carlier	Bibiana	Tsinghua University, Ronda Elpidio Serrano 50	bibiana.carlier@ec-lyon.fr
28	Gibson	Marcantonio	EPFL, Wellerallee 5-2	marcantonio.gibson@univ-lyon.fr
29	Azorin	Aldo	University of Edinburgh, Lidwina-Siering-Gasse 3	aldo.azorin@univ-lyon.fr
30	Corominas	Mary	EPFL, 1937 Wang Expressway	mary.corominas@research.org
31	Merle	Elvira	University of Sydney, 90496 David Flat Apt. 931	elvira.merle@lab.eu
32	Carrillo	Mirjam	Universitat de Barcelona, Paseo de Tiburcio Pellicer 9	mirjam.carrillo@lab.eu
33	Stoppani	Aleksandr	TU Berlin, 37, rue Nath Barbe	aleksandr.stoppani@univ-lyon.fr
34	Tomás	Elise	Université Claude Bernard Lyon 1, Rotonda Govoni, 474 Piano 0	elise.tomas@uni.edu
35	Gnatz	Serafina	Universidade de São Paulo, Contrada Morricone, 99	serafina.gnatz@research.org
36	Guillot	Graciano	Sorbonne Université, Viale Fabia, 7 Piano 3	graciano.guillot@uni.edu
37	Torres	Greca	Université Paris-Saclay, Paseo de Bernarda Núñez 68 Piso 7 	greca.torres@ec-lyon.fr
38	Heinrich	Leonardo	Sapienza Università di Roma, 25, boulevard de Ledoux	leonardo.heinrich@ec-lyon.fr
39	Lercari	James	MIT, Glorieta Manu Gordillo 52 Apt. 82 	james.lercari@research.org
40	Lenoir	Bartholomäus	Université Grenoble Alpes, Dobesallee 9	bartholomaus.lenoir@research.org
41	Rossetti	Walter	Universitat de Barcelona, Janos-Müller-Gasse 86	walter.rossetti@uni.edu
42	Fernandes	Hortense	Stanford University, 31869 Kimberly Light Suite 749	hortense.fernandes@research.org
43	Barrena	Liberto	University of Tokyo, Glorieta Juan Luis Bertrán 33	liberto.barrena@univ-lyon.fr
44	Smith	Carlito	University of Toronto, Piazza Giannelli, 24 Piano 9	carlito.smith@uni.edu
45	Gomila	Ronald	EPFL, 10249 Gonzales Mountain Suite 648	ronald.gomila@uni.edu
46	Botticelli	Ana	Université Grenoble Alpes, Alameda de Elisabet Ibáñez 2	ana.botticelli@ec-lyon.fr
47	Almansa	Suzanne	University of Edinburgh, Wenzel-Pohl-Allee 74-82	suzanne.almansa@research.org
48	Lange	Charlotte	MIT, Nadja-Fritsch-Ring 8-5	charlotte.lange@lab.eu
49	Arco	Paoletta	TU München, Contrada Missoni, 76	paoletta.arco@research.org
50	Pardo	Laurent	University of Sydney, Calle de Herminio Lasa 824 Puerta 7 	laurent.pardo@univ-lyon.fr
51	Heras	Antoine	TU München, 086 Jeffrey Ville Apt. 712	antoine.heras@univ-lyon.fr
52	Pechel	Lauretta	Université de Tunis El Manar, Mudeplatz 78-42	lauretta.pechel@research.org
53	Shields	Apolonia	University of Edinburgh, Zirmestr. 1/5	apolonia.shields@research.org
54	Tovar	Maya	Sorbonne Université, 755 Gibson Islands Apt. 396	maya.tovar@uni.edu
55	Battelli	Melissa	Université de Montréal, Krauseweg 370	melissa.battelli@research.org
56	Ditschlerin	Dominga	TU Berlin, Piazza Collina, 52	dominga.ditschlerin@ec-lyon.fr
57	Botticelli	Emilia	University of Edinburgh, Schomberweg 28-40	emilia.botticelli@ec-lyon.fr
58	Gay	Henry	Université de Toulouse, 8, chemin Leroy	henry.gay@research.org
59	Cousin	Victor	Université de Toulouse, Fiebigplatz 3-3	victor.cousin@uni.edu
60	Giusti	Christian	Tsinghua University, Viale Etta, 157	christian.giusti@lab.eu
61	Pichon	Fausto	EPFL, Stumpfring 74-83	fausto.pichon@research.org
62	Oliboni	Noël	Tsinghua University, Plaza de Paula Priego 10 Puerta 7 	noel.oliboni@lab.eu
63	Lawson	Lene	Imperial College London, Elsbeth-Hermann-Allee 510	lene.lawson@lab.eu
64	Patiño	Amico	University of Edinburgh, 5623 Kristin Wells	amico.patino@research.org
65	Llamas	Anni	TU München, 4517 Donald Fork Suite 851	anni.llamas@uni.edu
66	Reising	Alberto	ETH Zürich, 74, chemin de Nicolas	alberto.reising@ec-lyon.fr
340	Neuschäfer	Margot	\N	margot.neuschafer@research.org
67	Mosquera	Thomas	Sorbonne Université, Pasaje Virginia Matas 31	thomas.mosquera@univ-lyon.fr
68	Nohlmans	Auguste	Université Paris-Saclay, boulevard Dufour	auguste.nohlmans@uni.edu
69	Steckel	Rodolfo	MIT, Ronda Fátima Cabeza 79 Piso 0 	rodolfo.steckel@uni.edu
70	Ruggieri	Heinz-Günther	Université de Tunis El Manar, 58506 Lopez Crossing Suite 139	heinzgunther.ruggieri@ec-lyon.fr
71	Henk	Benoît	University of Toronto, 83933 Schroeder Turnpike	benoit.henk@univ-lyon.fr
72	Fiebig	Abilio	University of Edinburgh, 10205 Brianna Brook Apt. 402	abilio.fiebig@ec-lyon.fr
73	Vallet	Vincentio	University of Toronto, 95, rue de Sauvage	vincentio.vallet@ec-lyon.fr
74	Aroca	Ismael	ETH Zürich, Plaza de Benjamín Tejero 26 Piso 7 	ismael.aroca@research.org
75	Schlosser	Édouard	EPFL, 49985 Vang Pines	edouard.schlosser@univ-lyon.fr
76	Ros	Udo	Stanford University, 9, rue de Perret	udo.ros@univ-lyon.fr
77	Gutierrez	Vanessa	Stanford University, Strada Mazzeo, 65 Piano 1	vanessa.gutierrez@lab.eu
78	Morin	Véronique	Universidade de São Paulo, Via Viviani, 269	veronique.morin@research.org
79	Hervé	Stella	Universidade de São Paulo, Via de Crescencia Vera 82 Apt. 15 	stella.herve@research.org
80	Ledoux	Quirino	Université Paris-Saclay, Rörrichtallee 9	quirino.ledoux@research.org
81	Nelson	Angelo	Imperial College London, Albersplatz 296	angelo.nelson@uni.edu
82	Robin	Joyce	TU Delft, Ronda de Wilfredo Nogueira 55	joyce.robin@univ-lyon.fr
83	Blazquez	Leokadia	Tsinghua University, 19, rue de Maillard	leokadia.blazquez@research.org
84	Spanevello	Fortunata	ETH Zürich, Callejón de Ildefonso Vila 6 Piso 1 	fortunata.spanevello@uni.edu
85	Torrecilla	Halina	ETH Zürich, Urbanización Ruperto Ballesteros 4 Piso 3 	halina.torrecilla@univ-lyon.fr
86	Junken	Kathryn	MIT, avenue Jérôme Dumont	kathryn.junken@research.org
87	Mason	Vito	University of Sydney, Weihmanngasse 1-8	vito.mason@lab.eu
88	Román	Thomas	University of Toronto, Cañada de Darío Quirós 6 Apt. 97 	thomas.roman@uni.edu
89	Camuccini	Diethelm	Université de Toulouse, 681 Harrell Summit Suite 352	diethelm.camuccini@research.org
90	Laporte	Danielle	Universidade de São Paulo, Acceso de Lucía Coloma 31	danielle.laporte@uni.edu
91	Morrison	Hans-Rudolf	EPFL, 87, boulevard de Weiss	hansrudolf.morrison@lab.eu
92	Flantz	Mohamed	École Centrale de Lyon, Viale Marcacci, 99	mohamed.flantz@lab.eu
93	Salvo	Thierry	Universidad Politécnica de Madrid, chemin Denis Imbert	thierry.salvo@ec-lyon.fr
94	Vendrell	Laetitia	École Centrale de Lyon, Viale Paloma, 95 Appartamento 7	laetitia.vendrell@univ-lyon.fr
95	Bodin	Inken	Universitat de Barcelona, 77889 Michael Haven	inken.bodin@research.org
96	Stiebitz	Pierangelo	TU München, Avenida de Narciso Busquets 564	pierangelo.stiebitz@univ-lyon.fr
97	Cook	Samanta	TU München, Cañada de Gabriela Pou 29	samanta.cook@lab.eu
98	Mondaini	Britta	Sorbonne Université, 685 Michael Falls	britta.mondaini@univ-lyon.fr
99	Ferrabosco	Matthew	Tsinghua University, 14188 Ebony Wells	matthew.ferrabosco@ec-lyon.fr
100	Peñas	Eleuterio	University of Sydney, 92706 Rhodes Freeway	eleuterio.penas@univ-lyon.fr
101	Weller	Cristina	Universidade de São Paulo, Contrada Paloma, 853	cristina.weller@lab.eu
102	Riquelme	Tiziano	Universidade de São Paulo, 240 Sawyer Plaza	tiziano.riquelme@uni.edu
103	Casanovas	Michèle	Université de Toulouse, Jörn-Mende-Weg 461	michele.casanovas@ec-lyon.fr
104	Bauer	Valentina	EPFL, Stretto Paltrinieri, 46	valentina.bauer@uni.edu
105	Delannoy	Timothée	Sapienza Università di Roma, Arnim-Hörle-Straße 177	timothee.delannoy@lab.eu
106	Hande	Alfred	University of Toronto, 43410 Robert Underpass Suite 117	alfred.hande@ec-lyon.fr
107	Lefort	Blanca	TU Berlin, Cañada Timoteo Abellán 753	blanca.lefort@lab.eu
108	Hardy	Elizabeth	Universidade de São Paulo, Reinhart-Möchlichen-Gasse 6-5	elizabeth.hardy@uni.edu
109	Barre	Agathe	University of Tokyo, 520 Payne Via	agathe.barre@research.org
110	Soderini	Maria	University of Edinburgh, 70430 Nina Island	maria.soderini@research.org
111	Vento	Anke	TU Delft, Canale Franco, 55 Appartamento 75	anke.vento@lab.eu
112	Morlacchi	Virginia	TU Delft, 758 Owen Stream Suite 169	virginia.morlacchi@univ-lyon.fr
113	Dobes	Amy	TU München, 84, avenue de Brun	amy.dobes@uni.edu
114	Basso	Maurizio	Sorbonne Université, Schwitalallee 1	maurizio.basso@research.org
115	Cuesta	Mirco	École Centrale de Lyon, 370, rue Merle	mirco.cuesta@lab.eu
116	Zola	Othmar	EPFL, 67, avenue Paulette Garnier	othmar.zola@uni.edu
117	Pedraza	Emigdio	Université de Montréal, Borgo Carli, 992 Appartamento 84	emigdio.pedraza@uni.edu
118	Täsche	Wendy	École Centrale de Lyon, Via Serena, 27	wendy.tasche@univ-lyon.fr
119	Tröst	Gloria	University of Tokyo, 344, rue de Étienne	gloria.trost@univ-lyon.fr
120	Bourgeois	Jacobo	TU München, 0589 Mcdonald Plaza	jacobo.bourgeois@univ-lyon.fr
121	François	Cheryl	Université Claude Bernard Lyon 1, Putzstraße 2-3	cheryl.francois@research.org
122	Lebreton	Franca	Sorbonne Université, Stretto Eugenia, 92 Appartamento 8	franca.lebreton@lab.eu
123	Morris	Grzegorz	TU München, 414 Cynthia Plaza Suite 249	grzegorz.morris@research.org
124	Domingo	Ciro	Stanford University, Alameda Purificación Armengol 2	ciro.domingo@ec-lyon.fr
125	Landa	Lucy	TU Berlin, 078 May Hollow Suite 364	lucy.landa@lab.eu
126	Barbier	Benito	Université de Toulouse, Viale Fischetti, 69 Piano 6	benito.barbier@lab.eu
127	Camino	Kathleen	Université de Montréal, Eberhardtring 23-12	kathleen.camino@ec-lyon.fr
128	Prodi	Traudel	TU München, 9532 Ferrell Mountain	traudel.prodi@ec-lyon.fr
129	Oestrovsky	Tiziana	Université de Tunis El Manar, boulevard Céline Guillot	tiziana.oestrovsky@ec-lyon.fr
130	Girard	Brandy	TU Berlin, Hörlestr. 1	brandy.girard@univ-lyon.fr
131	Vogt	Donato	Université Paris-Saclay, Bienstraße 9	donato.vogt@ec-lyon.fr
132	Röhrdanz	Guiomar	Universitat de Barcelona, Pärtzeltstraße 2/3	guiomar.rohrdanz@ec-lyon.fr
133	Kambs	Anaïs	Imperial College London, Glorieta Eligia Verdú 18 Apt. 02 	anais.kambs@ec-lyon.fr
134	Traversa	Magda	Tsinghua University, Rotonda Daria, 592	magda.traversa@univ-lyon.fr
135	Zanichelli	Berta	Stanford University, Paul-Kabus-Allee 56	berta.zanichelli@univ-lyon.fr
136	Impastato	Jeannine	Université Claude Bernard Lyon 1, Camino Alexandra Donaire 396	jeannine.impastato@ec-lyon.fr
137	Aubert	Anthony	Tsinghua University, 36, rue Antoinette Charrier	anthony.aubert@research.org
138	Blasi	Zoraida	Université de Tunis El Manar, 578 Edwards Extensions	zoraida.blasi@univ-lyon.fr
139	Ritter	Vito	TU München, Gröttnerplatz 9/5	vito.ritter@uni.edu
140	Winkler	Shelly	TU Berlin, Junckstraße 58/24	shelly.winkler@lab.eu
141	Pino	Inmaculada	TU Delft, Contrada Ansaldo, 881 Appartamento 93	inmaculada.pino@uni.edu
142	Chauvet	Freddy	Imperial College London, Calle Haydée Gonzalez 20	freddy.chauvet@uni.edu
143	Callegari	Marco	Sapienza Università di Roma, 267 Santos Throughway	marco.callegari@ec-lyon.fr
144	Seidel	Marijan	TU München, boulevard de Grondin	marijan.seidel@univ-lyon.fr
145	Roger	Mamen	TU Delft, Incrocio Milena, 12	mamen.roger@lab.eu
146	Campo	Catharina	Université Paris-Saclay, Segebahnstr. 82-58	catharina.campo@univ-lyon.fr
147	Fröhlich	Lisa	MIT, Piazza Loredana, 4 Piano 6	lisa.frohlich@lab.eu
148	Maréchal	Nacio	University of Sydney, 67, rue Bertin	nacio.marechal@univ-lyon.fr
149	Interiano	Gianpietro	Sorbonne Université, John-Söding-Ring 5017	gianpietro.interiano@uni.edu
150	Mercader	Richard	Université Grenoble Alpes, 45, rue Martel	richard.mercader@ec-lyon.fr
151	Pereira	Spencer	KU Leuven, Borgo Giulia, 928 Appartamento 0	spencer.pereira@ec-lyon.fr
152	Martin	Brunilda	TU Berlin, Glorieta Liliana Torrijos 9 Piso 0 	brunilda.martin@ec-lyon.fr
153	Ribes	Donatello	Université Claude Bernard Lyon 1, Canale Mascagni, 16	donatello.ribes@uni.edu
154	Briand	Camilo	University of Edinburgh, Sylvia-Bohnbach-Straße 4	camilo.briand@univ-lyon.fr
155	Cannon	Filippo	University of Edinburgh, Viale Papafava, 21 Appartamento 98	filippo.cannon@research.org
156	Davenport	Jessica	Université de Tunis El Manar, 78, avenue de Rolland	jessica.davenport@ec-lyon.fr
157	Hill	Steven	Politecnico di Milano, avenue de Bonneau	steven.hill@ec-lyon.fr
158	Jones	Olivier	University of Tokyo, Calle de Jose Ignacio Arregui 47	olivier.jones@lab.eu
159	Joly	Isaac	Stanford University, Camino Melchor Montes 34 Puerta 8 	isaac.joly@ec-lyon.fr
160	Bolander	Robert	Université de Toulouse, Paseo de Ana Sofía Arévalo 96	robert.bolander@uni.edu
161	Pizzetti	Hermine	Politecnico di Milano, 2873 Kevin Station Apt. 708	hermine.pizzetti@uni.edu
162	Cañete	Piermaria	Université Claude Bernard Lyon 1, Borgo Montalcini, 27	piermaria.canete@lab.eu
163	Barracco	René	Tsinghua University, 883, chemin Bailly	rene.barracco@lab.eu
164	Hayden	Marcel	Université Claude Bernard Lyon 1, 43, rue Françoise Lebrun	marcel.hayden@research.org
165	Ubaldi	Rainer	Université Claude Bernard Lyon 1, Klingelhöferstr. 87-61	rainer.ubaldi@univ-lyon.fr
166	Beccheria	Nathan	Université de Montréal, Plaza Juan Carlos Rios 42	nathan.beccheria@ec-lyon.fr
167	Gozzano	Hermann-Josef	ETH Zürich, Viale Storladi, 32 Piano 2	hermannjosef.gozzano@lab.eu
168	Hardy	Felisa	Université Grenoble Alpes, rue de Salmon	felisa.hardy@univ-lyon.fr
169	Kirby	Antoinette	ETH Zürich, 203 Brooks River	antoinette.kirby@univ-lyon.fr
170	Sraffa	Ximena	Université Grenoble Alpes, boulevard de Bouchet	ximena.sraffa@univ-lyon.fr
171	Llobet	Alfred	University of Toronto, Pasadizo Odalis Ros 21 Puerta 2 	alfred.llobet@univ-lyon.fr
172	Iniesta	James	Stanford University, Budigring 8-4	james.iniesta@uni.edu
173	Guibert	Kevin	University of Edinburgh, avenue Alexandria Courtois	kevin.guibert@univ-lyon.fr
174	Boutin	Arsenio	Université de Montréal, 6591 Jerry Ways	arsenio.boutin@uni.edu
175	Bien	Aitana	Université de Montréal, 18, chemin Durand	aitana.bien@lab.eu
176	Borsiere	Brenda	Université Claude Bernard Lyon 1, Carolina-Krebs-Allee 26/92	brenda.borsiere@lab.eu
177	Nguyen	Bernt	Sorbonne Université, 9996 Johnson Groves	bernt.nguyen@ec-lyon.fr
178	Kelly	Silvestro	Stanford University, Canale Bettina, 41 Appartamento 4	silvestro.kelly@lab.eu
179	Singh	Lara	Université de Montréal, Dirk-Adolph-Ring 25-34	lara.singh@lab.eu
180	Salandra	Julien	Universidad Politécnica de Madrid, Plaza Chuy Otero 619 Piso 0 	julien.salandra@research.org
181	Brenna	Sebastian	TU Berlin, C. Fortunato Chamorro 54	sebastian.brenna@research.org
182	Brun	Ennio	TU München, Contrada Sorrentino, 445 Piano 1	ennio.brun@research.org
183	Montanelli	Kevin	University of Edinburgh, Pasaje de Nicanor Ros 624 Puerta 3 	kevin.montanelli@uni.edu
184	Oconnell	Luca	Stanford University, Ruppertallee 7564	luca.oconnell@research.org
185	Folch	Ercan	TU Delft, Pasaje Leandra Gallego 24	ercan.folch@research.org
186	Cilea	Giada	Universidade de São Paulo, Sorgatzplatz 7-2	giada.cilea@univ-lyon.fr
187	Piccio	Caterina	École Centrale de Lyon, Acceso Judith Blázquez 4 Puerta 5 	caterina.piccio@ec-lyon.fr
188	Thibault	Deborah	University of Toronto, Strada Altera, 4 Piano 5	deborah.thibault@lab.eu
189	Vall	Ronaldo	Université Paris-Saclay, 71461 Marie Stream Apt. 545	ronaldo.vall@univ-lyon.fr
190	Boyd	Mercedes	EPFL, Thaddäus-Ullmann-Allee 55-11	mercedes.boyd@uni.edu
191	Seifert	Alphonse	ETH Zürich, 93, boulevard Leroux	alphonse.seifert@research.org
192	Scamarcio	Brunhilde	Université de Toulouse, 226 Johnson Ridges Apt. 796	brunhilde.scamarcio@research.org
193	Harris	Adelmo	Sorbonne Université, 9, chemin Germain	adelmo.harris@uni.edu
194	Steckel	Stephen	Universitat de Barcelona, Vicolo Perini, 85 Piano 9	stephen.steckel@research.org
195	Edwards	Cesar	Université Grenoble Alpes, 25286 Carlson Ports Suite 627	cesar.edwards@ec-lyon.fr
196	Peters	Joaquina	University of Sydney, Via Luchino, 19 Piano 2	joaquina.peters@lab.eu
197	Vega	Lisa	University of Tokyo, Incrocio Ruggeri, 2 Appartamento 4	lisa.vega@research.org
198	Malo	Helmuth	University of Toronto, 788 Ashley Grove Suite 807	helmuth.malo@lab.eu
199	Camicione	Isaías	École Centrale de Lyon, 74517 Kimberly Freeway Apt. 959	isaias.camicione@lab.eu
200	Chaparro	Ezio	Politecnico di Milano, 95849 Mario Squares	ezio.chaparro@univ-lyon.fr
201	Lastra	Klaas	Université de Toulouse, Ronda Zaida Barranco 32	klaas.lastra@research.org
202	Hentschel	Dustin	Université Paris-Saclay, Vicolo Elvira, 86 Appartamento 66	dustin.hentschel@univ-lyon.fr
203	Salz	Sergius	Tsinghua University, 8, chemin de Andre	sergius.salz@lab.eu
204	Donaldson	Rómulo	Université de Toulouse, 5458 Ashlee Oval Suite 001	romulo.donaldson@research.org
205	Barbier	Alderano	Politecnico di Milano, Incrocio Gaspare, 24 Piano 4	alderano.barbier@lab.eu
206	Williams	Alix	TU Berlin, Sölzergasse 40	alix.williams@research.org
207	Wheeler	Beppe	TU Berlin, Plaza Josefa Nuñez 7 Puerta 2 	beppe.wheeler@research.org
208	Reyes	Benedetto	ETH Zürich, chemin Théophile Dos Santos	benedetto.reyes@ec-lyon.fr
209	May	Matilda	Sapienza Università di Roma, 909 Scott Stravenue	matilda.may@univ-lyon.fr
210	Gillespie	Courtney	Sorbonne Université, Avenida Teófila Cabrera 71 Piso 6 	courtney.gillespie@ec-lyon.fr
211	Wright	Lissi	University of Sydney, 599, rue de Delmas	lissi.wright@research.org
212	Vergara	Harm	Université Claude Bernard Lyon 1, 0376 John Route Apt. 805	harm.vergara@univ-lyon.fr
213	Puglisi	Franco	Universidad Politécnica de Madrid, Winklergasse 9	franco.puglisi@uni.edu
214	Hande	Alexandre	MIT, boulevard Sébastien Techer	alexandre.hande@research.org
215	Randazzo	María Fernanda	Université Grenoble Alpes, Contrada Bruno, 1	mariafernanda.randazzo@ec-lyon.fr
216	Boezio	Nacho	EPFL, Bogdan-Henschel-Gasse 2-8	nacho.boezio@ec-lyon.fr
217	Ruiz	Emelina	EPFL, 20275 Jackson Crossroad	emelina.ruiz@univ-lyon.fr
218	Pires	Jaqueline	Université Paris-Saclay, 94, chemin Mendès	jaqueline.pires@univ-lyon.fr
219	Mahe	Eulalia	University of Tokyo, Viale Sole, 25 Appartamento 3	eulalia.mahe@uni.edu
220	Williams	Alexandre	EPFL, Hans Jörg-Beier-Weg 4-6	alexandre.williams@univ-lyon.fr
221	Hiller	Robert	University of Sydney, 91, rue de Colin	robert.hiller@research.org
222	Maréchal	Linda	Université de Montréal, 64, boulevard Pineau	linda.marechal@lab.eu
223	Carter	Alexandrie	Université de Toulouse, Kochstr. 43-38	alexandrie.carter@ec-lyon.fr
224	Rey	Anouk	Université de Toulouse, Alameda Abel Peñalver 41 Puerta 3 	anouk.rey@univ-lyon.fr
225	Blanchard	Silvestro	Politecnico di Milano, Sonia-Heinrich-Weg 6-8	silvestro.blanchard@research.org
226	Bodin	Inès	Université de Tunis El Manar, 99062 Kelly Vista Suite 655	ines.bodin@univ-lyon.fr
227	Jones	Guarino	Universitat de Barcelona, 121 Shannon Island	guarino.jones@uni.edu
228	Palma	Dante	Stanford University, 7411 Lindsey Hollow Apt. 352	dante.palma@uni.edu
229	Schmitt	Michèle	Stanford University, Contrada Draghi, 96	michele.schmitt@univ-lyon.fr
230	Joly	Célina	Universitat de Barcelona, rue Dumont	celina.joly@lab.eu
231	Striebitz	Madison	Imperial College London, 141, rue Imbert	madison.striebitz@lab.eu
232	Davis	Paloma	Tsinghua University, Theres-Misicher-Gasse 796	paloma.davis@uni.edu
233	Regge	Amadeo	TU München, 24472 Christina Ridges Apt. 476	amadeo.regge@uni.edu
234	Fernandez	Alejandra	Université de Tunis El Manar, Siegbert-Gute-Allee 6806	alejandra.fernandez@uni.edu
235	Muratori	Alessia	Imperial College London, Callejón de Geraldo Amo 49 Apt. 40 	alessia.muratori@univ-lyon.fr
236	Wilms	Virgilio	Université Grenoble Alpes, Via Jose Miguel Hernando 18	virgilio.wilms@research.org
237	Nonis	Barbara	Université de Tunis El Manar, 95590 Meza Port	barbara.nonis@ec-lyon.fr
238	Copeland	Anna	Université de Tunis El Manar, Viale Angelo, 0 Appartamento 18	anna.copeland@uni.edu
239	Fortuny	Sina	Sapienza Università di Roma, 250 Dylan Squares Apt. 185	sina.fortuny@uni.edu
240	Callegaro	Alix	Université de Tunis El Manar, Ernstplatz 8-6	alix.callegaro@univ-lyon.fr
241	Palacios	Jasmine	University of Edinburgh, 4422 Stacy Ports	jasmine.palacios@univ-lyon.fr
242	Antúnez	Serafina	KU Leuven, 391 Taylor Summit Apt. 355	serafina.antunez@uni.edu
243	Neveu	Daisy	TU Berlin, Josip-Häring-Platz 55	daisy.neveu@ec-lyon.fr
244	Rousseau	Michelle	Universitat de Barcelona, Via Porcellato, 926 Piano 9	michelle.rousseau@research.org
245	Fontaine	Francisco	University of Sydney, Heßgasse 35	francisco.fontaine@uni.edu
246	Lévy	Ernesto	TU München, 197, rue Julie Gay	ernesto.levy@univ-lyon.fr
247	Haering	Brian	Stanford University, 884 Evans Court Apt. 698	brian.haering@uni.edu
248	Alves	Eraldo	University of Edinburgh, 5, boulevard de Voisin	eraldo.alves@research.org
249	Jackson	Collin	Sapienza Università di Roma, Drubring 8-8	collin.jackson@univ-lyon.fr
250	Ponce	Dino	Universidade de São Paulo, 5270 Gonzales Greens Apt. 490	dino.ponce@research.org
251	Clément	Karen	Universitat de Barcelona, Birgitta-Bolander-Straße 9-8	karen.clement@lab.eu
252	Alvarez	Socorro	University of Edinburgh, 9, boulevard de Masse	socorro.alvarez@lab.eu
253	Boulay	Eugenio	Universidad Politécnica de Madrid, Borgo Ornella, 22	eugenio.boulay@univ-lyon.fr
254	Flowers	Gaspare	Université Paris-Saclay, Dieter-Kraushaar-Weg 9-6	gaspare.flowers@research.org
255	Anastasi	Annamaria	Université Grenoble Alpes, Ronda Eutimio Colomer 299 Apt. 91 	annamaria.anastasi@lab.eu
256	Núñez	Nurten	Sapienza Università di Roma, Canale Spanevello, 70 Appartamento 19	nurten.nunez@univ-lyon.fr
257	Stumpf	Veronica	Université Paris-Saclay, 745 Matthew Underpass	veronica.stumpf@lab.eu
258	Noack	Louis	Imperial College London, 84, chemin Nathalie Delattre	louis.noack@research.org
259	Roche	Flavia	Tsinghua University, Viale Tozzo, 0	flavia.roche@research.org
260	Quintanilla	Inge	Imperial College London, 33030 Williams Lake	inge.quintanilla@lab.eu
261	Tirabassi	Joshua	ETH Zürich, Borgo Niccolò, 399	joshua.tirabassi@univ-lyon.fr
262	Monroe	Moritz	University of Edinburgh, Baumstraße 2	moritz.monroe@lab.eu
263	Vincent	Melisa	TU Berlin, 6800 Buck Rue	melisa.vincent@research.org
264	Hubert	Carolyn	Université Claude Bernard Lyon 1, Löchelstraße 47/84	carolyn.hubert@ec-lyon.fr
265	Puerta	Gülsen	École Centrale de Lyon, Pasadizo Gloria Perelló 599	gulsen.puerta@lab.eu
266	Leduc	Hedwig	Université de Tunis El Manar, 55, chemin Laurent Gérard	hedwig.leduc@lab.eu
267	Yoder	María Del Carmen	Stanford University, Vial de Lorena Amigó 54 Piso 6 	mariadelcarmen.yoder@uni.edu
268	Guillon	Loredana	Universitat de Barcelona, Urbanización de Itziar Tamarit 58	loredana.guillon@ec-lyon.fr
269	Escrivá	Mary	Sorbonne Université, Eckbauerweg 9/3	mary.escriva@research.org
270	Louis	Geraldine	University of Toronto, Linkeallee 55/84	geraldine.louis@research.org
271	Couturier	Charlotte	Stanford University, Glorieta de Angelita Carretero 58	charlotte.couturier@univ-lyon.fr
272	Taylor	Arnulfo	Tsinghua University, 9725 Kimberly Oval Suite 250	arnulfo.taylor@research.org
273	Häring	Catherine	ETH Zürich, 1296 Powell Neck	catherine.haring@research.org
274	Joubert	Adelmo	Stanford University, 58300 Jeremy Wells Suite 421	adelmo.joubert@ec-lyon.fr
275	Maza	Tiziano	Universidad Politécnica de Madrid, 44789 Hamilton Spur	tiziano.maza@ec-lyon.fr
276	Oliboni	Matthew	University of Tokyo, 0332 Jessica Radial	matthew.oliboni@research.org
277	Poulain	Fortunato	EPFL, 18, rue de Peltier	fortunato.poulain@uni.edu
278	Rousseau	Marcelle	TU Berlin, 26, chemin de Reynaud	marcelle.rousseau@ec-lyon.fr
279	Hernandez	Jamie	Stanford University, Vicolo Ciani, 21	jamie.hernandez@ec-lyon.fr
280	Lynch	Colette	Stanford University, Tlustekstraße 3/1	colette.lynch@uni.edu
281	Watts	Anabel	University of Toronto, Piazza Alberico, 31 Appartamento 41	anabel.watts@lab.eu
282	Mitschke	Laureano	Politecnico di Milano, rue Charpentier	laureano.mitschke@ec-lyon.fr
283	Loos	Luzie	EPFL, rue Dos Santos	luzie.loos@univ-lyon.fr
284	Inzaghi	Mark	Politecnico di Milano, 22, avenue Cécile Maillard	mark.inzaghi@research.org
285	Quasimodo	Graziella	TU Berlin, 02169 Pham Springs	graziella.quasimodo@ec-lyon.fr
286	Pino	Filippo	Université de Tunis El Manar, Xaver-Neuschäfer-Gasse 8-1	filippo.pino@lab.eu
287	Aumann	Raymond	University of Toronto, Pasadizo de Azeneth Bustos 83	raymond.aumann@research.org
288	Condoleo	Gina	TU Delft, Rambla Anselma Soria 22	gina.condoleo@ec-lyon.fr
289	Rivera	Ludovico	TU Delft, Betty-Seifert-Straße 4-2	ludovico.rivera@uni.edu
290	Samper	Renzo	ETH Zürich, 25, rue François Antoine	renzo.samper@ec-lyon.fr
291	Abad	Amleto	Université de Tunis El Manar, 948, avenue Leblanc	amleto.abad@uni.edu
292	Hubert	Marieluise	Stanford University, Canale Ortese, 1 Appartamento 55	marieluise.hubert@univ-lyon.fr
293	Tintzmann	Azahara	Politecnico di Milano, avenue Joly	azahara.tintzmann@lab.eu
294	Schmidt	Coriolano	Stanford University, 63735 Katherine Cape	coriolano.schmidt@lab.eu
295	Saragat	Duilio	Universidad Politécnica de Madrid, Plaza de Bernarda Atienza 869	duilio.saragat@univ-lyon.fr
296	Holt	Mercedes	University of Sydney, 69958 Barnes Rest	mercedes.holt@uni.edu
297	Hornig	Joshua	Stanford University, Incrocio Chiara, 98	joshua.hornig@research.org
298	Striebitz	Jason	TU München, Almuth-Riehl-Allee 91/85	jason.striebitz@uni.edu
299	Udinese	Concepción	Université de Toulouse, Annedore-Döring-Gasse 3-1	concepcion.udinese@univ-lyon.fr
300	Weitzel	Luc	Université Claude Bernard Lyon 1, 420 Harris Plains Apt. 571	luc.weitzel@uni.edu
301	Gomez	Rufina	KU Leuven, Pasadizo Milagros Maestre 7 Piso 6 	rufina.gomez@lab.eu
302	Balaguer	Waltraud	Universidade de São Paulo, 83, chemin Faivre	waltraud.balaguer@univ-lyon.fr
303	Ferrándiz	Carina	TU Delft, 2122 Nicholas Meadow Suite 842	carina.ferrandiz@ec-lyon.fr
304	Adolph	Brandy	MIT, Arnulf-Fliegner-Ring 9	brandy.adolph@lab.eu
305	Palma	Adeline	TU Berlin, 48, boulevard Mercier	adeline.palma@ec-lyon.fr
306	Vento	Feliciano	KU Leuven, Acceso Ismael Garcés 65 Piso 3 	feliciano.vento@ec-lyon.fr
307	Zamorani	Bernarda	TU München, chemin de Cohen	bernarda.zamorani@uni.edu
308	Hervás	Rebecca	MIT, 26, chemin Élodie Ramos	rebecca.hervas@univ-lyon.fr
309	Perera	Andree	Universidade de São Paulo, Calle de Manu Fernández 28 Apt. 28 	andree.perera@univ-lyon.fr
310	Lacroix	Adrián	Universidade de São Paulo, 38612 Stephen Isle Apt. 110	adrian.lacroix@ec-lyon.fr
311	Bejarano	Laura	TU München, Ronda de Román Sanmartín 66	laura.bejarano@uni.edu
312	Joubert	Amélie	Université de Tunis El Manar, 119, rue de Pelletier	amelie.joubert@lab.eu
313	Zimmer	Curro	TU Delft, Wielochstraße 7-1	curro.zimmer@univ-lyon.fr
314	Gimeno	Ermenegildo	EPFL, 424 Bernard Branch Apt. 100	ermenegildo.gimeno@uni.edu
315	Valmarana	Débora	Université Paris-Saclay, Glorieta de Marianela Núñez 96	debora.valmarana@ec-lyon.fr
316	Jensen	Eugene	Université de Toulouse, Hans-Bernd-Steckel-Weg 8	eugene.jensen@ec-lyon.fr
317	Beltran	Fabia	Stanford University, Dippelplatz 35-45	fabia.beltran@lab.eu
318	Baños	Roland	EPFL, 7594 Ariana Lakes Suite 620	roland.banos@lab.eu
319	Joseph	Ismet	Universidad Politécnica de Madrid, Via Montanariello, 687 Appartamento 2	ismet.joseph@ec-lyon.fr
320	Vance	Natali	University of Toronto, 110 Lisa Prairie Suite 930	natali.vance@lab.eu
321	Admin	Système	\N	admin@gestion-conferences.fr
322	Suarez	Juan Bautista	\N	juanbautista.suarez@ec-lyon.fr
323	Vance	Michael	\N	michael.vance@lab.eu
324	Eimer	Luz	\N	luz.eimer@ec-lyon.fr
325	Botella	Temistocle	\N	temistocle.botella@uni.edu
326	Alarcón	Mirco	\N	mirco.alarcon@ec-lyon.fr
327	Daza	Melanie	\N	melanie.daza@ec-lyon.fr
328	Cuomo	Enrique	\N	enrique.cuomo@research.org
329	Coll	Ashley	\N	ashley.coll@uni.edu
330	Vasseur	Micheletto	\N	micheletto.vasseur@research.org
331	Aubry	Gianni	\N	gianni.aubry@lab.eu
332	Laroche	Horst-Dieter	\N	horstdieter.laroche@ec-lyon.fr
333	Kraushaar	April	\N	april.kraushaar@uni.edu
334	Fournier	Rodolfo	\N	rodolfo.fournier@research.org
335	Llanos	Edward	\N	edward.llanos@ec-lyon.fr
336	Dávila	Clara	\N	clara.davila@univ-lyon.fr
337	Ossola	Fiamma	\N	fiamma.ossola@research.org
338	Blondel	Francisca	\N	francisca.blondel@uni.edu
339	Black	Phillip	\N	phillip.black@research.org
341	Agudo	Vanessa	\N	vanessa.agudo@research.org
342	Gonzales	Sofía	\N	sofia.gonzales@lab.eu
343	Hahn	Chris	\N	chris.hahn@univ-lyon.fr
344	Schleich	Jacob	\N	jacob.schleich@uni.edu
345	Perry	Margaud	\N	margaud.perry@uni.edu
346	Leduc	Irmi	\N	irmi.leduc@uni.edu
347	Garza	Sante	\N	sante.garza@ec-lyon.fr
348	Williams	Alessio	\N	alessio.williams@uni.edu
349	Taylor	Dora	\N	dora.taylor@uni.edu
350	Collado	Aníbal	\N	anibal.collado@univ-lyon.fr
351	Girschner	Jacques	\N	jacques.girschner@ec-lyon.fr
352	Alfonso	Santiago	\N	santiago.alfonso@ec-lyon.fr
353	Fabre	Trude	\N	trude.fabre@research.org
354	Sommaruga	Clelia	\N	clelia.sommaruga@lab.eu
355	Cocci	Jeffrey	\N	jeffrey.cocci@ec-lyon.fr
356	Hanson	Otilia	\N	otilia.hanson@ec-lyon.fr
357	Ramsey	Juan Luis	\N	juanluis.ramsey@univ-lyon.fr
358	Bombieri	Sophia	\N	sophia.bombieri@uni.edu
359	Rodriguez	Nicholas	\N	nicholas.rodriguez@ec-lyon.fr
360	Rivas	Alexandra	\N	alexandra.rivas@ec-lyon.fr
361	Alvarez	Catherine	\N	catherine.alvarez@lab.eu
362	Rossi	Eli	\N	eli.rossi@univ-lyon.fr
363	Morin	Marina	\N	marina.morin@lab.eu
364	Winters	Flora	\N	flora.winters@ec-lyon.fr
365	Becker	Pastora	\N	pastora.becker@ec-lyon.fr
366	Paganini	Valerio	\N	valerio.paganini@univ-lyon.fr
\.


--
-- Data for Name: responsable_de; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.responsable_de (id_personne, id_conf, id_type) FROM stdin;
1	1	1
1	3	1
1	5	1
1	7	1
3	38	7
3	146	2
4	31	2
4	79	1
4	102	6
4	124	5
4	125	2
5	60	5
5	72	2
5	79	4
5	115	6
6	16	1
6	34	2
6	85	1
6	114	4
6	150	4
7	10	1
7	79	5
7	128	2
8	18	3
8	70	7
8	136	3
8	152	1
9	29	2
9	49	1
9	122	1
9	176	7
10	113	6
10	157	4
11	6	4
11	125	3
12	54	1
12	68	2
13	98	4
14	66	1
15	165	1
16	136	1
17	21	2
18	11	1
18	22	3
18	24	1
18	50	2
19	51	2
19	90	2
19	159	6
19	198	1
20	1	1
20	105	2
20	152	5
20	189	6
21	51	1
21	71	2
21	133	7
23	186	1
24	44	1
25	47	1
25	92	1
25	122	2
26	60	2
26	119	7
26	157	2
27	68	1
27	74	2
28	4	1
28	21	6
29	97	2
29	159	2
29	163	2
29	179	1
30	50	3
30	61	1
30	148	3
30	158	2
31	7	7
31	56	6
31	151	2
31	202	4
32	114	2
33	78	1
35	32	2
36	13	2
36	17	2
36	47	2
36	131	7
37	10	2
37	29	1
37	83	1
38	84	2
38	91	1
40	30	1
40	165	6
41	53	2
41	110	6
42	26	1
42	124	7
42	176	1
43	7	2
43	101	2
43	192	1
43	202	2
44	34	1
44	187	2
45	93	1
45	203	2
46	9	2
46	15	2
46	71	1
46	101	7
46	173	2
47	109	7
47	183	2
48	2	1
48	34	4
48	147	2
49	94	7
51	108	1
52	23	7
52	52	7
52	133	6
53	29	4
53	50	7
54	102	4
54	137	2
56	49	6
56	158	1
57	5	7
57	21	4
57	62	6
58	147	4
59	80	1
60	9	3
61	46	1
62	66	2
62	67	2
62	104	2
63	167	2
64	63	6
64	142	1
65	151	3
66	113	1
66	148	2
67	97	7
67	138	1
67	142	2
67	150	1
67	164	2
68	110	1
68	176	5
68	200	7
69	8	2
69	21	1
69	91	3
69	118	2
69	119	1
69	130	2
69	193	2
70	40	4
70	122	7
70	165	4
71	50	1
72	8	4
72	36	1
72	45	3
72	149	6
73	179	2
74	90	3
74	115	2
74	126	6
75	97	4
76	73	1
77	45	1
77	70	2
77	105	1
78	42	1
78	123	2
78	200	5
79	124	3
79	126	1
80	12	2
80	144	1
80	169	2
81	63	2
81	66	6
81	143	3
82	9	1
82	98	1
82	121	2
82	200	2
83	69	2
83	155	1
83	172	4
85	41	4
85	109	5
85	115	1
85	154	1
85	197	5
86	99	1
87	19	2
87	127	7
87	167	1
88	41	2
88	66	3
88	101	1
88	139	2
88	165	2
90	33	3
90	194	7
92	27	1
92	201	2
93	13	3
93	51	7
93	196	1
94	34	3
94	191	6
95	48	1
96	58	2
96	61	4
96	126	2
96	183	1
97	38	2
97	161	1
97	187	5
98	54	5
98	65	6
98	183	4
99	12	4
100	113	3
101	97	1
101	154	4
101	197	3
102	83	4
102	99	2
102	106	2
102	147	6
104	1	2
104	172	2
105	94	3
105	131	1
105	149	1
106	18	5
106	84	1
107	13	1
107	97	5
107	125	5
108	59	1
108	91	6
108	109	2
108	147	1
109	129	1
110	35	2
110	39	1
110	120	2
110	194	1
110	199	2
110	205	6
111	18	6
111	65	5
112	53	5
112	180	5
113	59	6
113	74	3
114	95	1
114	133	4
118	39	2
120	61	2
122	28	1
122	186	2
123	24	2
123	72	7
123	195	1
125	86	2
125	92	2
125	94	6
127	93	3
128	16	2
129	37	2
129	146	6
130	2	2
130	94	1
130	120	1
130	122	3
130	157	6
130	204	1
131	35	3
131	149	2
131	177	1
133	56	5
133	110	5
133	178	7
135	104	1
136	189	3
137	3	1
137	28	5
138	65	1
138	124	2
138	135	1
138	199	5
139	191	2
140	138	2
140	160	2
141	173	1
142	78	5
143	12	1
143	138	6
143	167	5
144	30	2
145	75	2
145	80	2
145	174	1
146	11	7
147	89	2
147	106	1
148	6	1
148	35	1
148	63	1
148	74	7
148	134	1
148	174	3
149	123	4
150	155	2
150	167	3
151	104	7
151	116	3
151	119	2
152	17	4
152	69	5
153	40	1
153	101	6
153	191	4
153	200	1
155	63	3
156	64	2
156	89	1
156	151	6
156	205	1
157	44	2
157	95	7
157	192	5
158	44	6
158	51	5
158	152	7
159	74	6
159	117	5
159	159	4
159	178	1
160	135	2
160	187	1
161	55	1
161	91	5
161	128	1
162	26	4
162	143	1
163	127	1
165	76	2
165	77	1
165	141	1
165	183	7
166	45	2
166	142	3
168	62	4
168	153	1
168	185	6
169	22	2
169	23	2
171	131	6
172	22	1
172	102	2
172	118	5
173	57	3
173	111	2
174	7	3
175	88	4
175	192	2
176	42	3
176	72	3
176	107	2
177	52	1
177	65	2
177	84	4
177	204	2
179	52	4
179	100	2
180	67	7
180	89	4
180	141	2
180	158	5
180	180	2
180	188	1
181	7	6
182	18	1
183	123	7
184	48	2
184	115	4
184	184	1
185	102	1
185	114	3
185	170	5
186	68	7
187	43	1
187	118	6
188	15	1
188	69	1
188	81	5
188	85	2
188	111	1
188	125	1
188	160	1
189	184	6
190	3	3
190	4	2
190	182	1
191	58	1
191	124	1
191	178	2
192	38	5
192	86	4
192	166	2
193	86	5
193	185	7
193	190	1
194	62	2
194	87	2
194	94	2
194	96	1
194	162	1
195	176	2
195	195	2
196	112	1
196	147	5
197	28	2
197	48	6
197	52	2
197	127	4
198	7	1
200	123	1
201	10	7
201	20	2
201	189	1
202	28	6
202	32	1
202	91	2
202	194	6
202	197	1
203	137	1
203	145	6
203	151	1
203	170	6
203	171	1
204	62	1
204	145	4
205	49	5
205	121	1
206	14	2
206	43	2
206	144	2
207	196	2
208	131	2
209	89	6
209	150	2
209	175	1
209	178	4
210	38	1
210	89	7
210	113	2
210	127	2
210	145	2
211	117	1
211	198	2
212	56	2
213	29	7
213	95	2
213	158	6
214	57	7
215	5	2
215	135	6
215	193	1
216	40	2
216	46	2
216	149	7
217	132	2
218	74	1
218	140	1
218	189	4
219	110	2
220	25	1
220	48	5
220	180	3
221	88	3
222	37	1
222	52	6
223	144	7
224	168	1
225	8	1
225	35	4
225	115	3
225	116	1
225	140	2
225	154	2
226	134	2
226	136	2
227	13	4
228	14	1
228	56	1
228	130	6
228	161	7
228	179	6
229	42	4
229	69	4
229	70	1
229	75	1
229	171	2
229	203	1
231	82	1
232	67	6
233	133	1
233	139	1
234	132	1
235	3	7
235	22	6
235	72	6
235	143	2
235	166	4
235	181	2
236	33	1
236	41	1
236	86	1
236	102	7
237	36	2
238	1	5
238	20	1
238	46	4
239	45	5
239	150	7
239	177	3
240	23	1
240	38	6
240	55	2
240	77	2
240	87	6
241	81	1
241	88	1
241	180	1
242	185	1
243	126	4
243	162	2
243	169	1
244	17	6
244	21	3
244	57	2
244	177	2
245	28	4
245	67	1
245	175	4
245	190	2
246	79	3
246	203	5
247	31	3
247	64	1
248	116	2
249	8	5
249	78	2
249	98	2
249	103	1
249	189	2
249	201	1
250	174	2
250	199	1
251	55	3
251	169	5
251	170	1
252	22	7
252	114	1
252	167	7
253	146	5
253	170	2
253	188	2
254	31	4
254	49	2
254	57	1
254	63	7
255	168	2
256	67	4
256	81	2
257	53	1
257	156	1
258	54	6
258	87	7
258	95	5
258	96	2
260	144	3
261	73	2
262	69	3
262	156	2
262	161	2
262	186	5
263	87	1
263	144	5
264	179	4
264	197	7
265	88	2
266	31	5
266	107	1
267	54	2
267	70	4
267	81	3
267	182	2
268	87	4
268	150	5
270	175	5
271	29	3
271	117	2
271	132	3
273	76	1
273	154	5
273	163	1
275	159	1
275	194	2
276	19	1
277	41	5
277	53	7
277	172	1
278	202	1
279	26	2
279	103	2
280	3	2
280	40	7
280	191	1
283	16	6
283	93	2
283	106	6
284	17	1
284	110	3
285	25	2
285	118	1
285	197	2
286	77	7
286	149	4
287	11	2
287	23	6
288	5	1
288	51	6
288	125	7
289	18	2
289	55	6
290	109	6
290	178	3
291	185	3
292	42	2
293	90	1
293	112	2
293	157	1
294	164	1
295	19	3
295	205	5
296	72	1
296	100	1
297	31	1
297	109	1
298	54	7
299	26	7
299	82	2
299	133	2
299	161	5
299	184	2
300	152	2
301	146	1
302	44	7
303	185	2
304	56	7
304	153	2
305	27	2
305	33	7
305	62	3
305	183	6
306	34	7
306	83	2
306	108	2
306	136	4
306	148	1
306	166	1
308	6	2
309	60	1
309	78	7
309	95	4
309	170	7
310	59	2
314	79	2
314	181	1
315	33	2
315	129	2
315	205	2
316	26	5
318	13	5
318	113	7
318	114	5
318	175	2
319	41	7
320	130	1
320	134	6
320	145	1
\.


--
-- Data for Name: serie; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.serie (id_serie, sigle, nom_serie) FROM stdin;
1	SDH	International Symposium on Spatial Data Handling
2	CAISE	Conference on Advanced Information Systems Engineering
3	VLDB	International Conference on Very Large Data Bases
4	ICDE	International Conference on Data Engineering
5	ER	International Conference on Conceptual Modeling
6	DEXA	Database and Expert Systems Applications
7	EDBT	International Conference on Extending Database Technology
8	TIME	Symposium on Temporal Representation and Reasoning
9	BDA	Gestion de Données – Principes, Technologies et Applications
\.


--
-- Data for Name: session; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.session (id_conf, num_session, intitule_session) FROM stdin;
1	1	Session 1 : Trajectory data
1	2	Session 2 : Moving objects
2	1	Session 1 : Spatio-temporal data
2	2	Session 2 : Spatial databases
2	3	Session 3 : Trajectory data
2	4	Session 4 : GIS
2	5	Session 5 : Geographic information retrieval
3	1	Session 1 : Spatial indexing
3	2	Session 2 : Moving objects
3	3	Session 3 : Spatial indexing
3	4	Session 4 : Location-based services
4	1	Session 1 : Quadtree
4	2	Session 2 : Spatio-temporal data
5	1	Session 1 : Quadtree
5	2	Session 2 : GIS
6	1	Session 1 : Spatial databases
6	2	Session 2 : Trajectory data
6	3	Session 3 : R-tree
6	4	Session 4 : Geographic information retrieval
6	5	Session 5 : Cartographic generalization
7	1	Session 1 : Remote sensing data
7	2	Session 2 : Remote sensing data
7	3	Session 3 : Spatial databases
7	4	Session 4 : R-tree
8	1	Session 1 : Spatial databases
8	2	Session 2 : Spatio-temporal data
8	3	Session 3 : Quadtree
8	4	Session 4 : Quadtree
8	5	Session 5 : Remote sensing data
9	1	Session 1 : Temporal data models
9	2	Session 2 : Temporal databases
9	3	Session 3 : Temporal database design
10	1	Session 1 : Business process management
10	2	Session 2 : Requirements engineering
10	3	Session 3 : Business process management
11	1	Session 1 : Knowledge graphs
11	2	Session 2 : Natural language processing
11	3	Session 3 : Reinforcement learning
11	4	Session 4 : Reinforcement learning
11	5	Session 5 : Reinforcement learning
12	1	Session 1 : Stream processing
12	2	Session 2 : Distributed computing
13	1	Session 1 : Access control
13	2	Session 2 : Access control
14	1	Session 1 : R-tree
14	2	Session 2 : Spatio-temporal data
14	3	Session 3 : R-tree
15	1	Session 1 : Temporal data models
15	2	Session 2 : Temporal database design
15	3	Session 3 : Indexing of temporal data
15	4	Session 4 : Indexing of temporal data
15	5	Session 5 : Temporal data models
16	1	Session 1 : Data anonymization
16	2	Session 2 : Access control
17	1	Session 1 : Information systems engineering
17	2	Session 2 : Requirements engineering
17	3	Session 3 : Business process management
17	4	Session 4 : Requirements engineering
17	5	Session 5 : Entity-relationship model
18	1	Session 1 : Reinforcement learning
18	2	Session 2 : Natural language processing
18	3	Session 3 : Natural language processing
18	4	Session 4 : Reinforcement learning
18	5	Session 5 : Deep learning
19	1	Session 1 : Entity-relationship model
19	2	Session 2 : Information systems engineering
19	3	Session 3 : Conceptual modeling
19	4	Session 4 : Requirements engineering
19	5	Session 5 : Information systems engineering
20	1	Session 1 : Artificial intelligence
20	2	Session 2 : Deep learning
20	3	Session 3 : Machine learning
20	4	Session 4 : Natural language processing
20	5	Session 5 : Reinforcement learning
21	1	Session 1 : Data lakes
21	2	Session 2 : Data lakes
21	3	Session 3 : Big data
22	1	Session 1 : Query optimization
22	2	Session 2 : Transaction processing
22	3	Session 3 : Graph databases
22	4	Session 4 : Document stores
23	1	Session 1 : Big data
23	2	Session 2 : Distributed computing
23	3	Session 3 : Big data
23	4	Session 4 : Stream processing
23	5	Session 5 : Distributed computing
24	1	Session 1 : Temporal query languages
24	2	Session 2 : Temporal data models
24	3	Session 3 : Temporal database design
25	1	Session 1 : Security and privacy
25	2	Session 2 : Data anonymization
26	1	Session 1 : Business process management
26	2	Session 2 : Entity-relationship model
26	3	Session 3 : Entity-relationship model
26	4	Session 4 : Requirements engineering
26	5	Session 5 : Requirements engineering
27	1	Session 1 : Data lakes
27	2	Session 2 : Distributed computing
28	1	Session 1 : Graph databases
28	2	Session 2 : Data quality
29	1	Session 1 : Security and privacy
29	2	Session 2 : Data anonymization
30	1	Session 1 : Cartographic generalization
30	2	Session 2 : R-tree
30	3	Session 3 : R-tree
31	1	Session 1 : Indexing of temporal data
31	2	Session 2 : Temporal databases
31	3	Session 3 : Temporal data models
31	4	Session 4 : Temporal database design
32	1	Session 1 : Knowledge graphs
32	2	Session 2 : Knowledge graphs
32	3	Session 3 : Reinforcement learning
33	1	Session 1 : Access control
33	2	Session 2 : Data anonymization
33	3	Session 3 : Data anonymization
33	4	Session 4 : Security and privacy
34	1	Session 1 : Document stores
34	2	Session 2 : Transaction processing
34	3	Session 3 : Data management
34	4	Session 4 : Data management
34	5	Session 5 : Data quality
35	1	Session 1 : Data anonymization
35	2	Session 2 : Access control
35	3	Session 3 : Security and privacy
35	4	Session 4 : Security and privacy
35	5	Session 5 : Data anonymization
36	1	Session 1 : Conceptual modeling
36	2	Session 2 : Requirements engineering
37	1	Session 1 : Temporal databases
37	2	Session 2 : Temporal query languages
37	3	Session 3 : Temporal databases
37	4	Session 4 : Temporal databases
37	5	Session 5 : Temporal data models
38	1	Session 1 : Temporal data models
38	2	Session 2 : Temporal data models
38	3	Session 3 : Temporal data models
39	1	Session 1 : Information systems engineering
39	2	Session 2 : Business process management
39	3	Session 3 : Conceptual modeling
40	1	Session 1 : Indexing of temporal data
40	2	Session 2 : Indexing of temporal data
41	1	Session 1 : Data anonymization
41	2	Session 2 : Data anonymization
41	3	Session 3 : Security and privacy
41	4	Session 4 : Access control
42	1	Session 1 : Artificial intelligence
42	2	Session 2 : Deep learning
43	1	Session 1 : Temporal databases
43	2	Session 2 : Temporal database design
43	3	Session 3 : Temporal query languages
43	4	Session 4 : Indexing of temporal data
43	5	Session 5 : Indexing of temporal data
44	1	Session 1 : GIS
44	2	Session 2 : Trajectory data
44	3	Session 3 : Location-based services
45	1	Session 1 : Conceptual modeling
45	2	Session 2 : Business process management
45	3	Session 3 : Entity-relationship model
45	4	Session 4 : Conceptual modeling
45	5	Session 5 : Information systems engineering
46	1	Session 1 : Access control
46	2	Session 2 : Security and privacy
46	3	Session 3 : Data anonymization
46	4	Session 4 : Data anonymization
47	1	Session 1 : Access control
47	2	Session 2 : Access control
47	3	Session 3 : Data anonymization
47	4	Session 4 : Security and privacy
48	1	Session 1 : Temporal databases
48	2	Session 2 : Temporal database design
49	1	Session 1 : Natural language processing
49	2	Session 2 : Knowledge graphs
49	3	Session 3 : Knowledge graphs
50	1	Session 1 : Access control
50	2	Session 2 : Security and privacy
51	1	Session 1 : Entity-relationship model
51	2	Session 2 : Entity-relationship model
51	3	Session 3 : Entity-relationship model
51	4	Session 4 : Conceptual modeling
52	1	Session 1 : Security and privacy
52	2	Session 2 : Data anonymization
52	3	Session 3 : Data anonymization
52	4	Session 4 : Access control
52	5	Session 5 : Security and privacy
53	1	Session 1 : Machine learning
53	2	Session 2 : Reinforcement learning
54	1	Session 1 : Artificial intelligence
54	2	Session 2 : Artificial intelligence
55	1	Session 1 : Transaction processing
55	2	Session 2 : Data integration
55	3	Session 3 : Document stores
55	4	Session 4 : NoSQL databases
55	5	Session 5 : Transaction processing
56	1	Session 1 : Access control
56	2	Session 2 : Access control
56	3	Session 3 : Security and privacy
56	4	Session 4 : Access control
56	5	Session 5 : Security and privacy
57	1	Session 1 : Trajectory data
57	2	Session 2 : Geographic information retrieval
57	3	Session 3 : Trajectory data
57	4	Session 4 : GIS
58	1	Session 1 : Distributed computing
58	2	Session 2 : Big data
58	3	Session 3 : Big data
59	1	Session 1 : Temporal query languages
59	2	Session 2 : Temporal databases
59	3	Session 3 : Temporal data models
60	1	Session 1 : Data lakes
60	2	Session 2 : Distributed computing
60	3	Session 3 : Stream processing
60	4	Session 4 : Big data
60	5	Session 5 : Distributed computing
61	1	Session 1 : Information systems engineering
61	2	Session 2 : Business process management
61	3	Session 3 : Conceptual modeling
61	4	Session 4 : Business process management
61	5	Session 5 : Requirements engineering
62	1	Session 1 : Natural language processing
62	2	Session 2 : Reinforcement learning
63	1	Session 1 : Big data
63	2	Session 2 : Stream processing
63	3	Session 3 : Big data
64	1	Session 1 : Temporal data models
64	2	Session 2 : Temporal database design
64	3	Session 3 : Indexing of temporal data
65	1	Session 1 : Graph databases
65	2	Session 2 : NoSQL databases
65	3	Session 3 : Document stores
65	4	Session 4 : Transaction processing
65	5	Session 5 : Document stores
66	1	Session 1 : Indexing of temporal data
66	2	Session 2 : Temporal database design
66	3	Session 3 : Temporal query languages
67	1	Session 1 : Remote sensing data
67	2	Session 2 : Spatio-temporal data
67	3	Session 3 : Remote sensing data
68	1	Session 1 : Entity-relationship model
68	2	Session 2 : Requirements engineering
68	3	Session 3 : Requirements engineering
69	1	Session 1 : Temporal data models
69	2	Session 2 : Temporal database design
70	1	Session 1 : Big data
70	2	Session 2 : Distributed computing
70	3	Session 3 : Stream processing
71	1	Session 1 : Data quality
71	2	Session 2 : Data integration
72	1	Session 1 : Data anonymization
72	2	Session 2 : Data anonymization
72	3	Session 3 : Access control
72	4	Session 4 : Security and privacy
72	5	Session 5 : Security and privacy
73	1	Session 1 : Data quality
73	2	Session 2 : Data integration
74	1	Session 1 : Machine learning
74	2	Session 2 : Knowledge graphs
75	1	Session 1 : Big data
75	2	Session 2 : Data lakes
75	3	Session 3 : Big data
75	4	Session 4 : Data lakes
76	1	Session 1 : Spatio-temporal data
76	2	Session 2 : Quadtree
76	3	Session 3 : Spatial indexing
76	4	Session 4 : Quadtree
77	1	Session 1 : Spatio-temporal data
77	2	Session 2 : Moving objects
78	1	Session 1 : Entity-relationship model
78	2	Session 2 : Requirements engineering
79	1	Session 1 : Reinforcement learning
79	2	Session 2 : Reinforcement learning
79	3	Session 3 : Knowledge graphs
79	4	Session 4 : Natural language processing
79	5	Session 5 : Machine learning
80	1	Session 1 : Temporal databases
80	2	Session 2 : Temporal query languages
80	3	Session 3 : Temporal database design
81	1	Session 1 : R-tree
81	2	Session 2 : Remote sensing data
81	3	Session 3 : Quadtree
81	4	Session 4 : Moving objects
81	5	Session 5 : Spatial indexing
82	1	Session 1 : Access control
82	2	Session 2 : Data anonymization
82	3	Session 3 : Security and privacy
82	4	Session 4 : Security and privacy
83	1	Session 1 : Deep learning
83	2	Session 2 : Deep learning
83	3	Session 3 : Knowledge graphs
83	4	Session 4 : Deep learning
84	1	Session 1 : Data lakes
84	2	Session 2 : Data lakes
85	1	Session 1 : Security and privacy
85	2	Session 2 : Security and privacy
86	1	Session 1 : Cartographic generalization
86	2	Session 2 : Remote sensing data
86	3	Session 3 : Trajectory data
87	1	Session 1 : Spatial databases
87	2	Session 2 : Geographic information retrieval
88	1	Session 1 : Transaction processing
88	2	Session 2 : Query optimization
88	3	Session 3 : NoSQL databases
88	4	Session 4 : NoSQL databases
89	1	Session 1 : Spatial databases
89	2	Session 2 : Location-based services
89	3	Session 3 : Cartographic generalization
89	4	Session 4 : Remote sensing data
89	5	Session 5 : R-tree
90	1	Session 1 : Requirements engineering
90	2	Session 2 : Requirements engineering
90	3	Session 3 : Requirements engineering
90	4	Session 4 : Business process management
90	5	Session 5 : Entity-relationship model
91	1	Session 1 : Distributed computing
91	2	Session 2 : Big data
91	3	Session 3 : Data lakes
91	4	Session 4 : Big data
92	1	Session 1 : Reinforcement learning
92	2	Session 2 : Knowledge graphs
92	3	Session 3 : Machine learning
92	4	Session 4 : Deep learning
93	1	Session 1 : GIS
93	2	Session 2 : Trajectory data
93	3	Session 3 : R-tree
94	1	Session 1 : Access control
94	2	Session 2 : Access control
94	3	Session 3 : Data anonymization
94	4	Session 4 : Security and privacy
95	1	Session 1 : Temporal data models
95	2	Session 2 : Temporal query languages
95	3	Session 3 : Temporal databases
96	1	Session 1 : Temporal databases
96	2	Session 2 : Temporal data models
96	3	Session 3 : Temporal query languages
97	1	Session 1 : Requirements engineering
97	2	Session 2 : Business process management
98	1	Session 1 : Artificial intelligence
98	2	Session 2 : Deep learning
98	3	Session 3 : Machine learning
98	4	Session 4 : Machine learning
98	5	Session 5 : Deep learning
99	1	Session 1 : Security and privacy
99	2	Session 2 : Access control
99	3	Session 3 : Data anonymization
99	4	Session 4 : Access control
100	1	Session 1 : Temporal data models
100	2	Session 2 : Temporal databases
100	3	Session 3 : Temporal data models
100	4	Session 4 : Indexing of temporal data
100	5	Session 5 : Temporal databases
101	1	Session 1 : Spatial databases
101	2	Session 2 : Spatial databases
102	1	Session 1 : Temporal query languages
102	2	Session 2 : Temporal data models
102	3	Session 3 : Temporal databases
102	4	Session 4 : Indexing of temporal data
102	5	Session 5 : Temporal query languages
103	1	Session 1 : Remote sensing data
103	2	Session 2 : Spatio-temporal data
104	1	Session 1 : Indexing of temporal data
104	2	Session 2 : Temporal database design
104	3	Session 3 : Temporal query languages
105	1	Session 1 : Query optimization
105	2	Session 2 : Data quality
106	1	Session 1 : Data anonymization
106	2	Session 2 : Access control
107	1	Session 1 : Artificial intelligence
107	2	Session 2 : Knowledge graphs
108	1	Session 1 : Data management
108	2	Session 2 : Transaction processing
109	1	Session 1 : Security and privacy
109	2	Session 2 : Access control
109	3	Session 3 : Data anonymization
109	4	Session 4 : Security and privacy
110	1	Session 1 : Information systems engineering
110	2	Session 2 : Business process management
111	1	Session 1 : Security and privacy
111	2	Session 2 : Access control
111	3	Session 3 : Access control
111	4	Session 4 : Data anonymization
112	1	Session 1 : Stream processing
112	2	Session 2 : Distributed computing
112	3	Session 3 : Data lakes
113	1	Session 1 : Geographic information retrieval
113	2	Session 2 : Cartographic generalization
113	3	Session 3 : Trajectory data
113	4	Session 4 : Quadtree
113	5	Session 5 : Spatio-temporal data
114	1	Session 1 : Temporal databases
114	2	Session 2 : Indexing of temporal data
115	1	Session 1 : Data anonymization
115	2	Session 2 : Access control
116	1	Session 1 : Stream processing
116	2	Session 2 : Data lakes
116	3	Session 3 : Big data
117	1	Session 1 : R-tree
117	2	Session 2 : Spatial indexing
117	3	Session 3 : Spatial databases
118	1	Session 1 : Knowledge graphs
118	2	Session 2 : Artificial intelligence
118	3	Session 3 : Artificial intelligence
118	4	Session 4 : Machine learning
118	5	Session 5 : Knowledge graphs
119	1	Session 1 : Data anonymization
119	2	Session 2 : Security and privacy
119	3	Session 3 : Security and privacy
119	4	Session 4 : Data anonymization
119	5	Session 5 : Access control
120	1	Session 1 : Business process management
120	2	Session 2 : Entity-relationship model
120	3	Session 3 : Conceptual modeling
121	1	Session 1 : Conceptual modeling
121	2	Session 2 : Requirements engineering
121	3	Session 3 : Requirements engineering
121	4	Session 4 : Entity-relationship model
122	1	Session 1 : Data anonymization
122	2	Session 2 : Access control
122	3	Session 3 : Security and privacy
123	1	Session 1 : Data management
123	2	Session 2 : Graph databases
124	1	Session 1 : Knowledge graphs
124	2	Session 2 : Natural language processing
124	3	Session 3 : Natural language processing
125	1	Session 1 : Data lakes
125	2	Session 2 : Data lakes
125	3	Session 3 : Stream processing
126	1	Session 1 : Access control
126	2	Session 2 : Data anonymization
126	3	Session 3 : Data anonymization
127	1	Session 1 : Data management
127	2	Session 2 : Transaction processing
128	1	Session 1 : Deep learning
128	2	Session 2 : Artificial intelligence
128	3	Session 3 : Natural language processing
128	4	Session 4 : Natural language processing
129	1	Session 1 : Entity-relationship model
129	2	Session 2 : Requirements engineering
129	3	Session 3 : Business process management
129	4	Session 4 : Information systems engineering
130	1	Session 1 : Deep learning
130	2	Session 2 : Natural language processing
130	3	Session 3 : Machine learning
131	1	Session 1 : Location-based services
131	2	Session 2 : GIS
131	3	Session 3 : Spatial indexing
132	1	Session 1 : Data anonymization
132	2	Session 2 : Access control
132	3	Session 3 : Security and privacy
132	4	Session 4 : Data anonymization
133	1	Session 1 : Business process management
133	2	Session 2 : Business process management
133	3	Session 3 : Business process management
134	1	Session 1 : Artificial intelligence
134	2	Session 2 : Artificial intelligence
135	1	Session 1 : Access control
135	2	Session 2 : Access control
135	3	Session 3 : Security and privacy
135	4	Session 4 : Access control
135	5	Session 5 : Access control
136	1	Session 1 : Big data
136	2	Session 2 : Big data
136	3	Session 3 : Data lakes
136	4	Session 4 : Stream processing
137	1	Session 1 : Transaction processing
137	2	Session 2 : Data integration
137	3	Session 3 : NoSQL databases
137	4	Session 4 : Document stores
138	1	Session 1 : Conceptual modeling
138	2	Session 2 : Conceptual modeling
138	3	Session 3 : Information systems engineering
139	1	Session 1 : Information systems engineering
139	2	Session 2 : Business process management
139	3	Session 3 : Information systems engineering
139	4	Session 4 : Conceptual modeling
140	1	Session 1 : Requirements engineering
140	2	Session 2 : Requirements engineering
140	3	Session 3 : Business process management
140	4	Session 4 : Business process management
140	5	Session 5 : Conceptual modeling
141	1	Session 1 : Document stores
141	2	Session 2 : Query optimization
141	3	Session 3 : Transaction processing
141	4	Session 4 : Query optimization
141	5	Session 5 : Data management
142	1	Session 1 : Indexing of temporal data
142	2	Session 2 : Temporal query languages
142	3	Session 3 : Temporal database design
143	1	Session 1 : Stream processing
143	2	Session 2 : Distributed computing
144	1	Session 1 : Natural language processing
144	2	Session 2 : Machine learning
144	3	Session 3 : Artificial intelligence
145	1	Session 1 : Distributed computing
145	2	Session 2 : Data lakes
145	3	Session 3 : Big data
146	1	Session 1 : Graph databases
146	2	Session 2 : Transaction processing
146	3	Session 3 : Query optimization
146	4	Session 4 : Data integration
147	1	Session 1 : Spatio-temporal data
147	2	Session 2 : Geographic information retrieval
147	3	Session 3 : Cartographic generalization
147	4	Session 4 : Moving objects
148	1	Session 1 : Big data
148	2	Session 2 : Distributed computing
148	3	Session 3 : Big data
148	4	Session 4 : Distributed computing
148	5	Session 5 : Big data
149	1	Session 1 : Data lakes
149	2	Session 2 : Stream processing
149	3	Session 3 : Data lakes
150	1	Session 1 : Geographic information retrieval
150	2	Session 2 : Spatial indexing
150	3	Session 3 : Moving objects
150	4	Session 4 : GIS
150	5	Session 5 : Location-based services
151	1	Session 1 : Data management
151	2	Session 2 : Query optimization
151	3	Session 3 : Data management
152	1	Session 1 : Business process management
152	2	Session 2 : Conceptual modeling
152	3	Session 3 : Entity-relationship model
152	4	Session 4 : Business process management
152	5	Session 5 : Entity-relationship model
153	1	Session 1 : Conceptual modeling
153	2	Session 2 : Requirements engineering
153	3	Session 3 : Information systems engineering
153	4	Session 4 : Business process management
153	5	Session 5 : Requirements engineering
154	1	Session 1 : Deep learning
154	2	Session 2 : Machine learning
154	3	Session 3 : Reinforcement learning
154	4	Session 4 : Deep learning
154	5	Session 5 : Reinforcement learning
155	1	Session 1 : Conceptual modeling
155	2	Session 2 : Requirements engineering
155	3	Session 3 : Information systems engineering
155	4	Session 4 : Business process management
155	5	Session 5 : Information systems engineering
156	1	Session 1 : Requirements engineering
156	2	Session 2 : Conceptual modeling
156	3	Session 3 : Information systems engineering
156	4	Session 4 : Entity-relationship model
156	5	Session 5 : Requirements engineering
157	1	Session 1 : NoSQL databases
157	2	Session 2 : Graph databases
158	1	Session 1 : Temporal query languages
158	2	Session 2 : Temporal databases
158	3	Session 3 : Temporal database design
158	4	Session 4 : Temporal data models
159	1	Session 1 : Temporal databases
159	2	Session 2 : Indexing of temporal data
159	3	Session 3 : Temporal databases
159	4	Session 4 : Temporal database design
159	5	Session 5 : Temporal database design
160	1	Session 1 : Business process management
160	2	Session 2 : Conceptual modeling
160	3	Session 3 : Entity-relationship model
160	4	Session 4 : Conceptual modeling
160	5	Session 5 : Requirements engineering
161	1	Session 1 : Temporal database design
161	2	Session 2 : Temporal data models
162	1	Session 1 : NoSQL databases
163	1	Session 1 : Temporal data models
164	1	Session 1 : GIS
164	2	Session 2 : Location-based services
165	1	Session 1 : Deep learning
166	1	Session 1 : Machine learning
166	2	Session 2 : Natural language processing
167	1	Session 1 : Natural language processing
167	2	Session 2 : Knowledge graphs
168	1	Session 1 : Requirements engineering
169	1	Session 1 : Conceptual modeling
170	1	Session 1 : Data anonymization
170	2	Session 2 : Access control
171	1	Session 1 : Security and privacy
171	2	Session 2 : Access control
172	1	Session 1 : Distributed computing
173	1	Session 1 : Data lakes
173	2	Session 2 : Distributed computing
174	1	Session 1 : Spatial databases
175	1	Session 1 : Trajectory data
176	1	Session 1 : Big data
176	2	Session 2 : Distributed computing
177	1	Session 1 : Information systems engineering
177	2	Session 2 : Entity-relationship model
178	1	Session 1 : Access control
178	2	Session 2 : Security and privacy
179	1	Session 1 : Temporal query languages
179	2	Session 2 : Temporal data models
180	1	Session 1 : Requirements engineering
180	2	Session 2 : Information systems engineering
181	1	Session 1 : Entity-relationship model
182	1	Session 1 : Data lakes
182	2	Session 2 : Data lakes
183	1	Session 1 : Distributed computing
184	1	Session 1 : Security and privacy
185	1	Session 1 : Reinforcement learning
186	1	Session 1 : Requirements engineering
187	1	Session 1 : Business process management
188	1	Session 1 : Temporal database design
189	1	Session 1 : Spatial databases
190	1	Session 1 : Access control
190	2	Session 2 : Data anonymization
191	1	Session 1 : Remote sensing data
191	2	Session 2 : Location-based services
192	1	Session 1 : NoSQL databases
192	2	Session 2 : Data integration
193	1	Session 1 : Data anonymization
194	1	Session 1 : Access control
195	1	Session 1 : Access control
195	2	Session 2 : Data anonymization
196	1	Session 1 : Quadtree
196	2	Session 2 : Quadtree
197	1	Session 1 : NoSQL databases
197	2	Session 2 : Graph databases
198	1	Session 1 : Temporal data models
198	2	Session 2 : Temporal databases
199	1	Session 1 : Moving objects
199	2	Session 2 : Spatial databases
200	1	Session 1 : Big data
201	1	Session 1 : Spatio-temporal data
202	1	Session 1 : R-tree
202	2	Session 2 : R-tree
203	1	Session 1 : GIS
204	1	Session 1 : Spatio-temporal data
205	1	Session 1 : Spatial databases
205	2	Session 2 : Cartographic generalization
\.


--
-- Data for Name: session_theme; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.session_theme (id_conf, num_session, id_theme) FROM stdin;
1	1	9
1	2	10
2	1	8
2	1	1
2	1	11
2	2	1
2	2	12
2	3	9
2	3	5
2	3	28
2	4	2
2	5	3
2	5	4
2	5	11
3	1	5
3	1	7
3	1	26
3	2	10
3	2	4
3	3	5
3	4	11
4	1	7
4	2	8
4	2	1
4	2	11
5	1	7
5	1	11
5	2	2
5	2	9
5	2	1
6	1	1
6	1	2
6	2	9
6	2	10
6	3	6
6	3	14
6	4	3
6	4	7
6	4	2
6	5	4
6	5	10
6	5	7
7	1	12
7	1	3
7	2	12
7	2	2
7	2	9
7	3	1
7	3	2
7	4	6
8	1	1
8	1	11
8	2	8
8	2	4
8	3	7
8	3	3
8	4	7
8	4	2
8	4	10
8	5	12
8	5	18
9	1	14
9	1	16
9	2	13
9	2	20
9	3	15
9	3	17
9	3	6
10	1	29
10	1	30
10	1	6
10	2	30
10	2	26
10	3	29
10	3	26
11	1	36
11	2	35
11	3	34
11	3	32
11	3	35
11	4	34
11	4	32
11	4	28
11	5	34
11	5	33
12	1	39
12	1	37
12	2	38
12	2	40
12	2	20
13	1	42
13	1	43
13	2	42
13	2	43
14	1	6
14	1	10
14	2	8
14	3	6
14	3	5
15	1	14
15	1	15
15	1	17
15	2	15
15	2	13
15	3	17
15	4	17
15	4	30
15	5	14
15	5	16
15	5	17
16	1	43
16	1	42
16	1	20
16	2	42
17	1	26
17	1	29
17	2	30
17	2	29
17	3	29
17	3	26
17	3	27
17	4	30
17	4	26
17	4	29
17	5	28
17	5	27
17	5	30
18	1	34
18	1	31
18	1	17
18	2	35
18	3	35
18	3	36
18	3	32
18	4	34
18	4	35
18	5	33
19	1	28
19	2	26
19	3	27
19	3	28
19	3	30
19	4	30
19	5	26
19	5	29
20	1	31
20	1	33
20	1	8
20	2	33
20	3	32
20	3	36
20	3	35
20	4	35
20	4	34
20	5	34
21	1	40
21	1	38
21	1	37
21	2	40
21	3	37
21	3	39
22	1	19
22	1	22
22	1	18
22	2	20
22	2	25
22	2	24
22	3	22
22	4	23
22	4	22
23	1	37
23	1	38
23	1	39
23	2	38
23	2	39
23	2	40
23	3	37
23	3	39
23	3	40
23	4	39
23	4	24
23	5	38
23	5	39
23	5	40
24	1	16
24	1	17
24	1	13
24	2	14
24	2	17
24	2	16
24	3	15
25	1	41
25	1	42
25	1	25
25	2	43
25	2	42
25	2	41
26	1	29
26	1	30
26	1	26
26	1	2
26	2	28
26	2	15
26	3	28
26	3	27
26	3	29
26	4	30
26	4	26
26	5	30
26	5	28
27	1	40
27	1	39
27	1	37
27	2	38
28	1	22
28	1	20
28	2	25
29	1	41
29	2	43
29	2	42
29	2	41
30	1	4
30	2	6
30	2	9
30	2	5
30	3	6
31	1	17
31	1	15
31	2	13
31	2	14
31	2	16
31	3	14
31	3	17
31	4	15
31	4	14
31	4	17
32	1	36
32	1	33
32	1	34
32	2	36
32	3	34
33	1	42
33	1	43
33	1	41
33	2	43
33	2	30
33	3	43
33	3	42
33	3	41
33	4	41
33	4	42
34	1	23
34	1	24
34	2	20
34	2	22
34	2	21
34	3	18
34	3	25
34	3	24
34	4	18
34	4	25
34	5	25
35	1	43
35	2	42
35	2	41
35	2	43
35	2	24
35	3	41
35	3	42
35	4	41
35	4	43
35	4	42
35	5	43
35	5	41
35	5	42
36	1	27
36	2	30
37	1	13
37	2	16
37	3	13
37	3	14
37	4	13
37	4	17
37	4	14
37	5	14
37	5	16
38	1	14
38	1	13
38	1	15
38	2	14
38	2	16
38	2	17
38	3	14
38	3	16
38	3	15
39	1	26
39	1	8
39	2	29
39	2	28
39	2	27
39	3	27
40	1	17
40	2	17
40	2	15
40	2	16
40	2	43
41	1	43
41	2	43
41	3	41
41	3	43
41	3	42
41	4	42
42	1	31
42	1	33
42	1	35
42	1	37
42	2	33
42	2	35
43	1	13
43	2	15
43	3	16
43	4	17
43	4	16
43	4	14
43	5	17
44	1	2
44	1	5
44	1	14
44	2	9
44	3	11
44	3	12
44	3	2
45	1	27
45	1	26
45	1	29
45	1	28
45	2	29
45	3	28
45	4	27
45	4	26
45	4	29
45	5	26
45	5	27
45	5	29
46	1	42
46	1	18
46	2	41
46	2	43
46	2	42
46	3	43
46	3	41
46	4	43
46	4	41
46	4	42
47	1	42
47	2	42
47	3	43
47	4	41
48	1	13
48	2	15
48	2	16
49	1	35
49	2	36
49	2	34
49	2	32
49	3	36
49	3	33
50	1	42
50	1	41
50	1	43
50	2	41
50	2	42
50	2	43
51	1	28
51	1	26
51	2	28
51	3	28
51	3	27
51	3	29
51	4	27
51	4	30
52	1	41
52	2	43
52	2	41
52	2	42
52	3	43
52	3	42
52	3	34
52	4	42
52	5	41
53	1	32
53	2	34
53	2	33
53	2	36
54	1	31
54	1	35
54	1	32
54	2	31
54	2	35
55	1	20
55	1	19
55	1	25
55	2	24
55	2	23
55	3	23
55	3	21
55	4	21
55	4	38
55	5	20
55	5	29
56	1	42
56	1	41
56	2	42
56	3	41
56	3	43
56	4	42
56	4	41
56	4	43
56	5	41
56	5	43
57	1	9
57	1	1
57	2	3
57	2	1
57	3	9
57	3	12
57	4	2
57	4	3
57	4	4
58	1	38
58	2	37
58	2	39
58	3	37
59	1	16
59	1	14
59	1	13
59	2	13
59	2	17
59	3	14
60	1	40
60	1	38
60	1	37
60	2	38
60	2	40
60	3	39
60	4	37
60	5	38
60	5	39
60	5	40
61	1	26
61	2	29
61	3	27
61	3	26
61	3	30
61	4	29
61	4	30
61	5	30
61	5	28
61	5	27
62	1	35
62	1	32
62	1	18
62	2	34
63	1	37
63	2	39
63	3	37
63	3	40
63	3	38
64	1	14
64	2	15
64	2	13
64	2	17
64	3	17
64	3	14
64	3	15
65	1	22
65	1	19
65	1	21
65	1	4
65	2	21
65	2	31
65	3	23
65	4	20
65	5	23
65	5	10
66	1	17
66	2	15
66	3	16
66	3	13
66	3	14
67	1	12
67	2	8
67	2	11
67	2	6
67	3	12
67	3	10
67	3	6
68	1	28
68	1	30
68	1	1
68	2	30
68	2	29
68	2	28
68	2	39
68	3	30
68	3	27
69	1	14
69	1	15
69	2	15
70	1	37
70	1	39
70	1	38
70	2	38
70	2	37
70	3	39
70	3	37
71	1	25
71	1	23
71	2	24
72	1	43
72	1	42
72	1	31
72	2	43
72	2	41
72	2	42
72	3	42
72	3	17
72	4	41
72	5	41
72	5	43
73	1	25
73	1	23
73	1	42
73	2	24
74	1	32
74	1	36
74	2	36
74	2	35
74	2	33
75	1	37
75	2	40
75	2	37
75	2	39
75	3	37
75	3	38
75	4	40
75	4	37
75	4	39
75	4	11
76	1	8
76	2	7
76	2	8
76	3	5
76	3	2
76	3	9
76	4	7
76	4	6
77	1	8
77	1	12
77	2	10
77	2	1
78	1	28
78	2	30
78	2	27
79	1	34
79	1	35
79	1	36
79	2	34
79	3	36
79	3	31
79	4	35
79	4	36
79	4	32
79	4	29
79	5	32
80	1	13
80	2	16
80	2	14
80	2	15
80	2	39
80	3	15
80	3	13
80	3	36
81	1	6
81	1	5
81	1	9
81	2	12
81	3	7
81	3	2
81	3	12
81	3	37
81	4	10
81	4	2
81	4	11
81	5	5
82	1	42
82	1	43
82	2	43
82	2	42
82	2	41
82	3	41
82	3	42
82	3	22
82	4	41
82	4	43
82	4	42
83	1	33
83	2	33
83	2	36
83	3	36
83	3	31
83	3	32
83	3	29
83	4	33
83	4	34
84	1	40
84	2	40
84	2	39
85	1	41
85	1	43
85	1	42
85	2	41
85	2	43
86	1	4
86	2	12
86	2	4
86	3	9
86	3	7
87	1	1
87	1	4
87	1	6
87	2	3
87	2	8
88	1	20
88	1	24
88	2	19
88	2	20
88	2	18
88	3	21
88	4	21
88	4	23
88	4	19
89	1	1
89	1	11
89	1	12
89	2	11
89	3	4
89	4	12
89	4	11
89	5	6
89	5	8
90	1	30
90	1	29
90	2	30
90	3	30
90	3	28
90	4	29
90	4	18
90	5	28
90	5	30
90	5	27
91	1	38
91	2	37
91	3	40
91	3	39
91	3	38
91	4	37
91	4	39
91	4	38
92	1	34
92	1	36
92	2	36
92	2	35
92	2	32
92	3	32
92	3	35
92	3	34
92	4	33
92	4	35
92	4	36
93	1	2
93	1	8
93	1	17
93	2	9
93	2	3
93	2	6
93	3	6
94	1	42
94	1	43
94	2	42
94	2	41
94	3	43
94	3	41
94	3	42
94	4	41
94	4	42
94	4	43
95	1	14
95	2	16
95	2	14
95	2	17
95	3	13
96	1	13
96	1	17
96	2	14
96	3	16
97	1	30
97	2	29
97	2	30
98	1	31
98	2	33
98	2	31
98	2	36
98	3	32
98	3	31
98	3	35
98	4	32
98	5	33
98	5	32
99	1	41
99	2	42
99	2	43
99	3	43
99	3	42
99	3	41
99	4	42
100	1	14
100	1	17
100	2	13
100	2	14
100	3	14
100	4	17
100	4	14
100	4	13
100	5	13
100	5	16
100	5	15
101	1	1
101	1	11
101	1	2
101	2	1
102	1	16
102	1	13
102	2	14
102	2	17
102	3	13
102	3	15
102	3	14
102	4	17
102	4	15
102	4	16
102	5	16
103	1	12
103	1	10
103	1	2
103	2	8
104	1	17
104	1	14
104	2	15
104	2	14
104	2	32
104	3	16
105	1	19
105	2	25
105	2	19
105	2	18
106	1	43
106	1	41
106	1	42
106	2	42
106	2	43
107	1	31
107	2	36
107	2	33
108	1	18
108	1	9
108	2	20
108	2	25
108	2	24
109	1	41
109	1	42
109	1	43
109	2	42
109	2	43
109	3	43
109	3	42
109	4	41
109	4	43
109	4	42
110	1	26
110	2	29
110	2	30
110	2	26
111	1	41
111	1	43
111	1	42
111	2	42
111	3	42
111	4	43
112	1	39
112	1	40
112	1	37
112	2	38
112	2	40
112	2	39
112	3	40
112	3	37
112	3	39
112	3	11
113	1	3
113	1	2
113	2	4
113	2	6
113	3	9
113	4	7
113	4	12
113	4	4
113	4	29
113	5	8
113	5	2
113	5	12
114	1	13
114	1	17
114	2	17
115	1	43
115	1	42
115	1	41
115	2	42
115	2	43
116	1	39
116	1	40
116	2	40
116	2	39
116	2	38
116	3	37
117	1	6
117	2	5
117	2	9
117	2	11
117	3	1
118	1	36
118	2	31
118	2	33
118	3	31
118	4	32
118	4	34
118	5	36
119	1	43
119	2	41
119	2	42
119	2	43
119	3	41
119	3	42
119	3	43
119	4	43
119	5	42
119	5	41
119	5	43
120	1	29
120	2	28
120	2	29
120	2	27
120	3	27
120	3	28
120	3	30
121	1	27
121	1	30
121	2	30
121	2	28
121	2	29
121	3	30
121	3	27
121	4	28
121	4	30
121	4	29
121	4	42
122	1	43
122	1	42
122	1	41
122	2	42
122	2	43
122	2	41
122	3	41
122	3	43
122	3	10
123	1	18
123	1	19
123	1	20
123	2	22
124	1	36
124	2	35
124	2	29
124	3	35
125	1	40
125	1	37
125	1	38
125	2	40
125	3	39
125	3	40
125	3	37
125	3	17
126	1	42
126	1	41
126	1	43
126	2	43
126	2	41
126	2	42
126	3	43
126	3	12
127	1	18
127	1	21
127	2	20
127	2	19
128	1	33
128	2	31
128	3	35
128	3	31
128	4	35
128	4	33
128	4	34
129	1	28
129	2	30
129	2	33
129	3	29
129	4	26
129	4	28
130	1	33
130	1	36
130	1	35
130	2	35
130	2	34
130	2	31
130	2	23
130	3	32
130	3	35
131	1	11
131	2	2
131	2	7
131	3	5
131	3	1
131	3	9
132	1	43
132	1	42
132	1	41
132	2	42
132	3	41
132	4	43
132	4	41
132	4	42
133	1	29
133	1	26
133	1	30
133	2	29
133	2	26
133	2	28
133	3	29
134	1	31
134	1	17
134	2	31
134	2	35
134	2	32
135	1	42
135	1	43
135	2	42
135	3	41
135	3	43
135	3	42
135	4	42
135	5	42
136	1	37
136	1	38
136	1	39
136	2	37
136	2	38
136	2	40
136	3	40
136	4	39
136	4	40
136	4	37
137	1	20
137	1	1
137	2	24
137	2	22
137	2	25
137	3	21
137	3	23
137	4	23
137	4	19
137	4	21
138	1	27
138	2	27
138	2	26
138	3	26
138	3	29
138	3	28
139	1	26
139	1	28
139	1	30
139	2	29
139	2	28
139	2	27
139	2	42
139	3	26
139	4	27
140	1	30
140	1	28
140	2	30
140	3	29
140	3	27
140	3	16
140	4	29
140	5	27
140	5	28
141	1	23
141	1	24
141	2	19
141	2	25
141	2	23
141	3	20
141	3	22
141	4	19
141	4	23
141	4	18
141	5	18
141	5	24
141	5	22
142	1	17
142	2	16
142	2	14
142	2	17
142	3	15
142	3	14
142	3	16
143	1	39
143	1	40
143	1	16
143	2	38
143	2	39
143	2	37
144	1	35
144	1	32
144	1	34
144	2	32
144	3	31
145	1	38
145	2	40
145	2	38
145	3	37
146	1	22
146	2	20
146	2	21
146	3	19
146	3	22
146	4	24
147	1	8
147	1	10
147	1	9
147	2	3
147	2	4
147	2	42
147	3	4
147	3	3
147	4	10
147	4	2
148	1	37
148	1	38
148	2	38
148	2	39
148	3	37
148	3	40
148	4	38
148	4	37
148	4	39
148	5	37
149	1	40
149	1	39
149	1	37
149	2	39
149	2	37
149	2	40
149	3	40
149	3	37
150	1	3
150	1	10
150	1	12
150	2	5
150	2	3
150	2	6
150	3	10
150	3	2
150	3	4
150	4	2
150	4	34
150	5	11
150	5	7
150	5	3
151	1	18
151	1	24
151	2	19
151	3	18
152	1	29
152	1	28
152	1	26
152	2	27
152	2	29
152	3	28
152	3	26
152	4	29
152	4	27
152	5	28
153	1	27
153	1	26
153	2	30
153	3	26
153	3	29
153	3	28
153	4	29
153	4	28
153	5	30
153	5	28
153	5	27
154	1	33
154	1	35
154	1	36
154	2	32
154	2	34
154	3	34
154	3	32
154	3	33
154	4	33
154	4	36
154	5	34
154	5	32
154	5	31
155	1	27
155	1	26
155	1	29
155	2	30
155	2	26
155	3	26
155	3	30
155	3	29
155	4	29
155	4	26
155	4	30
155	5	26
155	5	30
156	1	30
156	1	28
156	1	29
156	2	27
156	3	26
156	3	27
156	4	28
156	4	27
156	4	26
156	5	30
156	5	27
156	5	28
157	1	21
157	1	23
157	1	11
157	2	22
158	1	16
158	1	17
158	1	15
158	2	13
158	3	15
158	3	17
158	3	14
158	4	14
158	4	17
159	1	13
159	1	15
159	1	17
159	2	17
159	2	19
159	3	13
159	3	15
159	4	15
159	4	16
159	4	14
159	5	15
160	1	29
160	1	26
160	1	27
160	1	5
160	2	27
160	2	30
160	3	28
160	3	26
160	4	27
160	4	28
160	4	22
160	5	30
161	1	15
161	1	14
161	2	14
161	2	17
162	1	21
163	1	14
164	1	2
164	1	6
164	2	11
164	2	8
164	2	10
164	2	35
165	1	33
165	1	35
166	1	32
166	1	35
166	2	35
166	2	34
167	1	35
167	1	31
167	2	36
167	2	32
168	1	30
168	1	29
168	1	27
169	1	27
169	1	29
169	1	28
169	1	24
170	1	43
170	2	42
170	2	43
171	1	41
171	1	42
171	2	42
171	2	43
172	1	38
172	1	39
172	1	37
173	1	40
173	2	38
174	1	1
174	1	3
175	1	9
175	1	12
175	1	6
176	1	37
176	1	38
176	1	11
176	2	38
177	1	26
177	1	29
177	1	28
177	2	28
177	2	30
178	1	42
178	2	41
178	2	43
178	2	42
179	1	16
179	1	13
179	1	14
179	2	14
179	2	17
180	1	30
180	1	29
180	2	26
181	1	28
181	1	30
182	1	40
182	1	38
182	2	40
182	2	38
182	2	37
183	1	38
184	1	41
185	1	34
186	1	30
186	1	26
186	1	40
187	1	29
188	1	15
188	1	16
188	1	17
188	1	34
189	1	1
190	1	42
190	1	43
190	2	43
191	1	12
191	1	11
191	1	10
191	2	11
191	2	9
191	2	5
192	1	21
192	1	24
192	1	18
192	2	24
192	2	20
193	1	43
194	1	42
194	1	43
195	1	42
195	1	41
195	2	43
195	2	41
196	1	7
196	2	7
196	2	4
197	1	21
197	1	20
197	1	41
197	2	22
198	1	14
198	1	13
198	2	13
198	2	16
199	1	10
199	1	8
199	1	4
199	2	1
200	1	37
201	1	8
201	1	1
201	1	4
202	1	6
202	2	6
202	2	8
203	1	2
203	1	3
203	1	26
204	1	8
204	1	3
204	1	4
205	1	1
205	1	2
205	2	4
205	2	7
205	2	8
\.


--
-- Data for Name: specification; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.specification (id_conf, id_categorie, nb_pages_max, police, taille_police, logiciel, date_limite_soumission, date_notification, date_limite_version_finale) FROM stdin;
1	1	14	Computer Modern	10	LaTeX	2020-05-02	2020-06-06	2020-06-27
1	9	4	Arial	11	LaTeX	2020-04-22	2020-06-08	2020-07-03
1	8	\N	\N	\N	\N	2020-05-13	2020-06-19	2020-07-11
2	1	16	Computer Modern	12	Word	2020-12-15	2021-02-03	2021-02-19
2	7	2	Arial	11	LaTeX	2020-12-21	2021-01-26	2021-02-13
2	9	4	Times New Roman	11	Word	2020-11-16	2020-12-30	2021-01-17
3	1	16	Arial	12	Word	2022-04-06	2022-05-17	2022-06-03
3	4	\N	\N	\N	\N	2022-04-09	2022-05-23	2022-06-07
3	8	\N	\N	\N	\N	2022-04-17	2022-05-24	2022-06-18
3	3	\N	\N	\N	\N	2022-03-02	2022-04-17	2022-05-16
3	6	6	Computer Modern	11	LaTeX	2022-03-09	2022-04-19	2022-05-09
4	1	12	Computer Modern	11	LaTeX	2023-04-25	2023-05-30	2023-06-18
4	6	6	Arial	11	Word	2023-04-10	2023-05-16	2023-06-11
4	4	\N	\N	\N	\N	2023-05-02	2023-06-15	2023-07-10
5	1	14	Computer Modern	12	Word	2024-03-19	2024-04-25	2024-05-13
5	3	\N	\N	\N	\N	2024-04-12	2024-05-19	2024-06-16
6	1	14	Arial	12	Word	2025-02-10	2025-03-27	2025-04-13
6	9	4	Arial	11	LaTeX	2024-12-29	2025-02-15	2025-03-02
6	5	8	Times New Roman	12	Word	2025-02-19	2025-04-02	2025-04-27
6	7	2	Arial	10	LaTeX	2025-01-01	2025-02-15	2025-03-16
7	1	12	Computer Modern	10	LaTeX	2026-05-30	2026-07-07	2026-07-22
7	5	8	Times New Roman	11	LaTeX	2026-04-16	2026-05-31	2026-06-22
7	4	\N	\N	\N	\N	2026-05-27	2026-07-07	2026-08-02
8	1	16	Arial	12	LaTeX	2027-02-13	2027-04-03	2027-04-21
8	4	\N	\N	\N	\N	2027-03-17	2027-04-22	2027-05-21
9	1	14	Times New Roman	10	LaTeX	2025-09-26	2025-11-03	2025-11-20
9	8	\N	\N	\N	\N	2025-09-16	2025-11-01	2025-11-26
9	3	\N	\N	\N	\N	2025-10-07	2025-11-17	2025-12-08
9	9	4	Times New Roman	10	LaTeX	2025-10-28	2025-12-13	2026-01-12
9	5	8	Computer Modern	10	LaTeX	2025-09-12	2025-10-30	2025-11-26
10	1	12	Arial	11	LaTeX	2026-06-17	2026-08-03	2026-09-02
10	5	10	Times New Roman	10	Word	2026-07-19	2026-08-30	2026-09-19
10	7	2	Arial	11	LaTeX	2026-06-28	2026-08-03	2026-08-19
10	2	4	Times New Roman	10	LaTeX	2026-07-02	2026-08-11	2026-08-31
11	1	12	Times New Roman	11	LaTeX	2026-01-22	2026-03-06	2026-03-31
11	5	10	Arial	12	LaTeX	2026-02-02	2026-03-13	2026-04-10
11	4	\N	\N	\N	\N	2026-03-11	2026-04-18	2026-05-03
11	9	4	Computer Modern	11	LaTeX	2026-02-27	2026-04-10	2026-04-27
11	8	\N	\N	\N	\N	2026-01-26	2026-03-16	2026-04-04
12	1	14	Arial	11	Word	2025-10-21	2025-12-10	2026-01-02
12	6	6	Times New Roman	12	LaTeX	2025-10-09	2025-11-16	2025-12-16
13	1	15	Times New Roman	11	LaTeX	2026-08-11	2026-09-18	2026-10-15
13	5	6	Computer Modern	11	LaTeX	2026-07-01	2026-08-14	2026-09-08
13	7	2	Times New Roman	10	LaTeX	2026-07-05	2026-08-13	2026-08-29
14	1	12	Computer Modern	10	Word	2026-06-19	2026-08-05	2026-08-30
14	5	10	Computer Modern	12	LaTeX	2026-05-05	2026-06-21	2026-07-20
15	1	14	Computer Modern	12	LaTeX	2025-11-19	2026-01-03	2026-01-28
15	6	8	Computer Modern	12	LaTeX	2025-11-18	2025-12-26	2026-01-20
16	1	15	Computer Modern	11	LaTeX	2026-02-26	2026-04-05	2026-04-23
16	3	\N	\N	\N	\N	2026-02-20	2026-03-29	2026-04-18
16	9	4	Arial	12	LaTeX	2026-03-02	2026-04-12	2026-05-01
17	1	14	Times New Roman	12	LaTeX	2026-02-28	2026-04-15	2026-05-07
17	2	4	Times New Roman	11	LaTeX	2026-02-22	2026-04-05	2026-04-24
17	8	\N	\N	\N	\N	2026-03-10	2026-04-27	2026-05-27
18	1	15	Arial	12	LaTeX	2026-07-24	2026-08-30	2026-09-22
18	7	2	Times New Roman	11	LaTeX	2026-07-21	2026-09-07	2026-09-26
18	3	\N	\N	\N	\N	2026-06-13	2026-07-31	2026-08-27
18	9	4	Computer Modern	10	LaTeX	2026-06-17	2026-07-28	2026-08-19
18	4	\N	\N	\N	\N	2026-07-17	2026-08-25	2026-09-15
19	1	12	Arial	11	LaTeX	2026-06-13	2026-07-21	2026-08-14
19	4	\N	\N	\N	\N	2026-04-22	2026-05-30	2026-06-28
19	7	2	Computer Modern	10	Word	2026-06-04	2026-07-11	2026-08-05
19	9	4	Arial	10	LaTeX	2026-05-15	2026-07-02	2026-07-22
19	8	\N	\N	\N	\N	2026-04-28	2026-06-13	2026-07-05
20	1	15	Arial	11	LaTeX	2026-04-18	2026-05-31	2026-06-23
20	8	\N	\N	\N	\N	2026-06-07	2026-07-12	2026-07-30
20	5	10	Computer Modern	12	LaTeX	2026-04-28	2026-06-17	2026-07-09
20	2	4	Times New Roman	12	Word	2026-06-06	2026-07-26	2026-08-22
20	7	2	Arial	12	Word	2026-06-06	2026-07-14	2026-08-01
21	1	12	Arial	11	Word	2026-03-01	2026-04-19	2026-05-18
21	8	\N	\N	\N	\N	2026-01-24	2026-02-28	2026-03-21
21	7	2	Computer Modern	10	Word	2026-02-15	2026-03-27	2026-04-11
21	9	4	Computer Modern	11	LaTeX	2026-02-22	2026-04-06	2026-05-02
21	2	4	Arial	12	LaTeX	2026-03-03	2026-04-21	2026-05-14
22	1	15	Computer Modern	10	Word	2025-10-10	2025-11-16	2025-12-11
22	7	2	Times New Roman	11	Word	2025-11-28	2026-01-14	2026-02-08
22	8	\N	\N	\N	\N	2025-11-02	2025-12-18	2026-01-12
22	3	\N	\N	\N	\N	2025-10-13	2025-12-01	2025-12-27
22	5	6	Times New Roman	12	LaTeX	2025-10-16	2025-11-25	2025-12-15
23	1	12	Arial	12	LaTeX	2026-06-09	2026-07-16	2026-08-06
23	4	\N	\N	\N	\N	2026-05-30	2026-07-12	2026-07-31
23	5	8	Times New Roman	12	LaTeX	2026-06-08	2026-07-23	2026-08-18
23	6	6	Times New Roman	12	LaTeX	2026-06-14	2026-07-21	2026-08-15
24	1	14	Times New Roman	10	LaTeX	2027-04-03	2027-05-15	2027-06-06
24	2	6	Arial	12	Word	2027-05-08	2027-06-19	2027-07-04
24	5	10	Computer Modern	12	LaTeX	2027-05-14	2027-07-01	2027-07-21
24	3	\N	\N	\N	\N	2027-04-05	2027-05-18	2027-06-15
25	1	14	Times New Roman	12	Word	2019-11-25	2020-01-10	2020-01-27
25	7	2	Times New Roman	12	LaTeX	2019-12-21	2020-01-28	2020-02-27
25	3	\N	\N	\N	\N	2019-11-14	2019-12-26	2020-01-24
25	4	\N	\N	\N	\N	2019-12-12	2020-01-17	2020-02-15
26	1	12	Arial	10	LaTeX	2023-06-27	2023-08-01	2023-08-30
26	9	4	Times New Roman	12	Word	2023-05-25	2023-07-10	2023-07-27
26	6	10	Computer Modern	11	Word	2023-06-06	2023-07-24	2023-08-12
26	5	6	Arial	12	Word	2023-05-24	2023-07-07	2023-08-01
26	2	4	Arial	10	Word	2023-06-17	2023-07-22	2023-08-07
27	1	12	Times New Roman	11	LaTeX	2022-12-22	2023-01-31	2023-02-20
27	4	\N	\N	\N	\N	2023-01-23	2023-03-11	2023-04-07
27	7	2	Times New Roman	10	LaTeX	2022-12-09	2023-01-26	2023-02-22
27	3	\N	\N	\N	\N	2023-01-07	2023-02-16	2023-03-16
27	8	\N	\N	\N	\N	2022-12-04	2023-01-16	2023-02-15
28	1	14	Arial	10	LaTeX	2027-07-28	2027-09-13	2027-10-04
28	4	\N	\N	\N	\N	2027-07-16	2027-08-23	2027-09-15
29	1	12	Arial	10	LaTeX	2021-01-05	2021-02-10	2021-03-08
29	2	6	Times New Roman	10	Word	2021-01-20	2021-03-08	2021-04-01
30	1	14	Times New Roman	12	LaTeX	2023-12-18	2024-01-26	2024-02-21
30	4	\N	\N	\N	\N	2023-11-02	2023-12-21	2024-01-05
30	6	6	Computer Modern	12	LaTeX	2023-11-15	2023-12-21	2024-01-08
30	3	\N	\N	\N	\N	2023-11-17	2023-12-27	2024-01-14
30	9	4	Arial	11	LaTeX	2023-11-23	2024-01-03	2024-01-22
31	1	14	Times New Roman	11	LaTeX	2026-11-24	2027-01-05	2027-01-31
31	3	\N	\N	\N	\N	2026-11-23	2026-12-29	2027-01-28
32	1	14	Times New Roman	11	LaTeX	2020-04-09	2020-05-24	2020-06-20
32	3	\N	\N	\N	\N	2020-05-03	2020-06-20	2020-07-17
33	1	16	Computer Modern	11	Word	2024-07-03	2024-08-10	2024-09-04
33	8	\N	\N	\N	\N	2024-06-20	2024-07-26	2024-08-11
33	2	6	Times New Roman	12	LaTeX	2024-07-22	2024-08-28	2024-09-21
33	5	10	Times New Roman	12	LaTeX	2024-07-31	2024-09-13	2024-10-10
33	9	4	Computer Modern	10	LaTeX	2024-06-17	2024-07-27	2024-08-22
34	1	12	Arial	10	LaTeX	2026-10-28	2026-12-08	2026-12-23
34	3	\N	\N	\N	\N	2026-11-28	2027-01-09	2027-02-03
34	7	2	Times New Roman	10	Word	2026-11-17	2027-01-03	2027-01-25
34	9	4	Arial	11	LaTeX	2026-11-13	2026-12-26	2027-01-23
35	1	15	Computer Modern	12	LaTeX	2027-01-16	2027-03-05	2027-04-01
35	8	\N	\N	\N	\N	2027-01-28	2027-03-16	2027-04-01
36	1	14	Times New Roman	12	LaTeX	2020-07-12	2020-08-19	2020-09-06
36	4	\N	\N	\N	\N	2020-07-06	2020-08-18	2020-09-14
36	7	2	Computer Modern	10	LaTeX	2020-06-28	2020-08-11	2020-09-04
36	8	\N	\N	\N	\N	2020-06-11	2020-07-31	2020-08-21
36	3	\N	\N	\N	\N	2020-07-08	2020-08-13	2020-09-12
37	1	12	Computer Modern	12	LaTeX	2023-01-04	2023-02-20	2023-03-12
37	3	\N	\N	\N	\N	2023-01-29	2023-03-09	2023-04-07
37	2	6	Arial	10	LaTeX	2023-01-19	2023-02-24	2023-03-17
37	9	4	Arial	10	LaTeX	2023-02-05	2023-03-20	2023-04-09
37	8	\N	\N	\N	\N	2023-02-02	2023-03-13	2023-04-06
38	1	16	Times New Roman	10	Word	2022-12-22	2023-02-01	2023-02-26
38	5	6	Times New Roman	12	LaTeX	2022-11-30	2023-01-13	2023-02-02
39	1	12	Arial	10	LaTeX	2026-10-27	2026-12-11	2027-01-06
39	2	4	Arial	10	Word	2026-11-18	2026-12-23	2027-01-08
39	6	8	Arial	12	LaTeX	2026-11-08	2026-12-15	2026-12-30
39	7	2	Computer Modern	11	LaTeX	2026-11-14	2026-12-26	2027-01-25
39	3	\N	\N	\N	\N	2026-11-13	2026-12-29	2027-01-20
40	1	15	Arial	10	LaTeX	2023-04-18	2023-05-28	2023-06-24
40	6	8	Arial	12	LaTeX	2023-04-13	2023-05-27	2023-06-15
40	7	2	Computer Modern	11	Word	2023-05-09	2023-06-17	2023-07-13
41	1	14	Times New Roman	12	LaTeX	2025-06-08	2025-07-23	2025-08-19
41	9	4	Arial	11	LaTeX	2025-05-24	2025-07-04	2025-07-30
41	5	8	Arial	11	LaTeX	2025-06-04	2025-07-13	2025-08-12
41	8	\N	\N	\N	\N	2025-06-17	2025-07-28	2025-08-22
41	4	\N	\N	\N	\N	2025-05-25	2025-07-04	2025-07-31
42	1	14	Times New Roman	10	LaTeX	2026-12-04	2027-01-13	2027-02-05
42	4	\N	\N	\N	\N	2026-12-08	2027-01-26	2027-02-17
42	5	10	Times New Roman	10	LaTeX	2026-11-03	2026-12-12	2027-01-11
42	2	4	Computer Modern	10	Word	2026-12-27	2027-01-31	2027-02-16
42	3	\N	\N	\N	\N	2026-12-19	2027-01-29	2027-02-22
43	1	16	Times New Roman	11	LaTeX	2023-06-23	2023-08-07	2023-09-05
43	7	2	Arial	12	LaTeX	2023-07-26	2023-09-04	2023-09-23
44	1	14	Times New Roman	10	LaTeX	2025-12-12	2026-01-23	2026-02-10
44	9	4	Arial	11	LaTeX	2025-11-29	2026-01-15	2026-02-14
44	7	2	Arial	11	LaTeX	2025-11-22	2026-01-01	2026-01-30
45	1	15	Times New Roman	12	LaTeX	2025-12-27	2026-02-05	2026-02-24
45	7	2	Computer Modern	10	Word	2025-11-21	2026-01-05	2026-01-29
46	1	16	Times New Roman	12	LaTeX	2026-02-20	2026-04-04	2026-04-19
46	4	\N	\N	\N	\N	2026-02-08	2026-03-24	2026-04-16
46	9	4	Arial	11	Word	2026-02-24	2026-04-13	2026-05-08
46	8	\N	\N	\N	\N	2026-03-19	2026-05-03	2026-05-19
46	3	\N	\N	\N	\N	2026-03-16	2026-04-20	2026-05-05
47	1	15	Computer Modern	12	LaTeX	2021-04-29	2021-06-15	2021-07-01
47	8	\N	\N	\N	\N	2021-04-27	2021-06-11	2021-06-30
47	3	\N	\N	\N	\N	2021-03-24	2021-05-09	2021-06-01
47	5	6	Computer Modern	12	LaTeX	2021-04-18	2021-05-29	2021-06-28
48	1	12	Times New Roman	10	Word	2020-02-05	2020-03-14	2020-04-05
48	3	\N	\N	\N	\N	2020-02-05	2020-03-18	2020-04-04
48	2	6	Times New Roman	10	Word	2020-02-01	2020-03-09	2020-03-24
48	9	4	Arial	10	LaTeX	2020-02-16	2020-04-05	2020-04-30
49	1	16	Times New Roman	12	LaTeX	2022-01-05	2022-02-11	2022-02-26
49	4	\N	\N	\N	\N	2021-12-17	2022-01-31	2022-02-21
50	1	15	Times New Roman	12	LaTeX	2027-01-06	2027-02-15	2027-03-17
50	5	10	Arial	10	Word	2027-02-15	2027-03-27	2027-04-17
50	7	2	Times New Roman	11	Word	2027-02-13	2027-03-22	2027-04-12
50	9	4	Computer Modern	11	Word	2026-12-29	2027-02-11	2027-03-11
50	6	6	Times New Roman	10	LaTeX	2027-02-05	2027-03-12	2027-04-04
51	1	12	Computer Modern	12	Word	2024-05-12	2024-06-30	2024-07-15
51	2	6	Arial	11	LaTeX	2024-04-09	2024-05-16	2024-06-08
51	6	6	Arial	10	LaTeX	2024-04-16	2024-05-30	2024-06-29
51	5	8	Computer Modern	11	LaTeX	2024-04-03	2024-05-19	2024-06-16
52	1	15	Times New Roman	11	LaTeX	2024-02-15	2024-03-21	2024-04-09
52	4	\N	\N	\N	\N	2024-03-12	2024-04-29	2024-05-19
52	3	\N	\N	\N	\N	2024-03-03	2024-04-12	2024-05-03
52	7	2	Computer Modern	10	LaTeX	2024-03-06	2024-04-10	2024-05-07
52	5	6	Times New Roman	11	Word	2024-02-10	2024-03-28	2024-04-17
53	1	12	Arial	11	Word	2027-01-25	2027-03-02	2027-03-28
53	8	\N	\N	\N	\N	2027-02-18	2027-03-29	2027-04-20
53	5	6	Computer Modern	12	LaTeX	2027-02-03	2027-03-25	2027-04-15
53	3	\N	\N	\N	\N	2027-02-15	2027-03-31	2027-04-28
53	9	4	Computer Modern	12	LaTeX	2027-01-28	2027-03-07	2027-03-26
54	1	14	Arial	10	LaTeX	2024-04-27	2024-06-12	2024-07-10
54	9	4	Times New Roman	10	LaTeX	2024-04-15	2024-06-04	2024-06-27
54	2	6	Computer Modern	10	LaTeX	2024-04-05	2024-05-17	2024-06-08
54	8	\N	\N	\N	\N	2024-04-23	2024-05-31	2024-06-27
55	1	15	Computer Modern	10	LaTeX	2022-11-16	2023-01-05	2023-02-03
55	7	2	Times New Roman	12	LaTeX	2022-11-04	2022-12-13	2023-01-08
55	2	6	Computer Modern	11	Word	2022-11-29	2023-01-14	2023-02-13
56	1	12	Arial	11	LaTeX	2027-02-03	2027-03-13	2027-04-06
56	5	8	Times New Roman	10	LaTeX	2027-01-22	2027-03-10	2027-04-07
56	6	8	Times New Roman	11	Word	2027-03-12	2027-04-16	2027-05-14
57	1	15	Arial	11	LaTeX	2026-07-19	2026-08-31	2026-09-29
57	4	\N	\N	\N	\N	2026-07-15	2026-08-23	2026-09-17
57	6	8	Times New Roman	11	Word	2026-07-24	2026-08-31	2026-09-16
57	5	6	Computer Modern	12	LaTeX	2026-07-01	2026-08-05	2026-09-02
57	9	4	Arial	12	LaTeX	2026-06-14	2026-07-28	2026-08-22
58	1	12	Computer Modern	10	LaTeX	2026-04-15	2026-05-25	2026-06-16
58	3	\N	\N	\N	\N	2026-03-31	2026-05-07	2026-06-06
58	2	4	Times New Roman	10	LaTeX	2026-03-27	2026-05-02	2026-05-30
58	9	4	Arial	12	Word	2026-04-11	2026-05-19	2026-06-11
58	7	2	Times New Roman	10	LaTeX	2026-04-20	2026-05-26	2026-06-17
59	1	15	Arial	12	Word	2024-04-15	2024-06-01	2024-06-16
59	7	2	Times New Roman	12	LaTeX	2024-04-13	2024-05-20	2024-06-05
59	4	\N	\N	\N	\N	2024-05-09	2024-06-24	2024-07-11
60	1	15	Computer Modern	10	LaTeX	2026-05-24	2026-06-28	2026-07-22
60	4	\N	\N	\N	\N	2026-04-15	2026-05-28	2026-06-22
60	5	10	Computer Modern	11	LaTeX	2026-05-21	2026-07-05	2026-07-28
60	3	\N	\N	\N	\N	2026-05-05	2026-06-21	2026-07-12
61	1	14	Arial	10	Word	2021-05-27	2021-07-04	2021-07-25
61	3	\N	\N	\N	\N	2021-04-29	2021-06-12	2021-07-08
61	2	4	Times New Roman	11	LaTeX	2021-05-22	2021-06-27	2021-07-19
62	1	16	Computer Modern	12	LaTeX	2024-11-11	2024-12-22	2025-01-21
62	4	\N	\N	\N	\N	2024-10-05	2024-11-24	2024-12-24
62	8	\N	\N	\N	\N	2024-10-28	2024-12-11	2025-01-02
63	1	12	Times New Roman	11	LaTeX	2026-10-03	2026-11-07	2026-11-22
63	3	\N	\N	\N	\N	2026-11-04	2026-12-14	2027-01-01
64	1	15	Computer Modern	12	LaTeX	2022-11-04	2022-12-15	2023-01-12
64	7	2	Computer Modern	10	LaTeX	2022-10-29	2022-12-04	2022-12-22
65	1	12	Arial	12	Word	2021-12-07	2022-01-11	2022-01-29
65	9	4	Arial	10	LaTeX	2021-12-01	2022-01-13	2022-01-28
66	1	12	Computer Modern	11	LaTeX	2024-09-08	2024-10-25	2024-11-09
66	8	\N	\N	\N	\N	2024-10-21	2024-11-26	2024-12-13
67	1	15	Arial	11	LaTeX	2025-06-20	2025-08-02	2025-08-17
67	6	10	Arial	10	LaTeX	2025-05-22	2025-06-27	2025-07-25
67	7	2	Times New Roman	11	Word	2025-06-09	2025-07-16	2025-08-11
67	5	8	Times New Roman	12	LaTeX	2025-05-06	2025-06-21	2025-07-10
68	1	15	Arial	11	LaTeX	2026-10-19	2026-12-08	2027-01-05
68	9	4	Computer Modern	12	Word	2026-10-07	2026-11-22	2026-12-21
68	4	\N	\N	\N	\N	2026-10-19	2026-12-03	2026-12-23
68	8	\N	\N	\N	\N	2026-09-04	2026-10-13	2026-11-03
69	1	12	Arial	10	Word	2024-11-25	2024-12-31	2025-01-18
69	3	\N	\N	\N	\N	2024-12-13	2025-01-27	2025-02-26
69	8	\N	\N	\N	\N	2024-12-20	2025-02-03	2025-03-01
69	5	10	Computer Modern	12	LaTeX	2024-11-22	2025-01-08	2025-02-04
69	2	4	Times New Roman	11	LaTeX	2024-12-13	2025-01-31	2025-02-19
70	1	14	Times New Roman	10	LaTeX	2020-11-25	2021-01-11	2021-02-04
70	6	6	Computer Modern	11	LaTeX	2020-11-22	2020-12-30	2021-01-20
71	1	16	Computer Modern	11	Word	2026-03-30	2026-05-13	2026-06-07
71	7	2	Computer Modern	11	LaTeX	2026-04-06	2026-05-26	2026-06-11
71	9	4	Arial	12	LaTeX	2026-04-27	2026-06-16	2026-07-13
71	5	8	Times New Roman	11	LaTeX	2026-03-14	2026-05-03	2026-05-18
71	2	4	Computer Modern	12	LaTeX	2026-04-09	2026-05-16	2026-06-02
72	1	14	Times New Roman	12	LaTeX	2025-11-11	2025-12-25	2026-01-23
72	9	4	Computer Modern	12	Word	2025-10-25	2025-11-29	2025-12-28
72	2	6	Computer Modern	11	LaTeX	2025-11-07	2025-12-13	2026-01-05
73	1	12	Times New Roman	11	LaTeX	2020-01-30	2020-03-15	2020-04-12
73	6	6	Computer Modern	10	LaTeX	2020-02-22	2020-03-28	2020-04-24
74	1	14	Arial	12	Word	2024-11-12	2024-12-20	2025-01-07
74	9	4	Arial	12	Word	2024-12-09	2025-01-27	2025-02-26
74	3	\N	\N	\N	\N	2024-11-17	2024-12-25	2025-01-22
74	7	2	Times New Roman	10	LaTeX	2024-11-10	2024-12-16	2025-01-08
75	1	12	Times New Roman	12	LaTeX	2019-11-16	2019-12-28	2020-01-16
75	9	4	Times New Roman	12	LaTeX	2019-12-02	2020-01-12	2020-02-10
75	5	6	Times New Roman	11	LaTeX	2019-12-07	2020-01-24	2020-02-11
75	6	10	Times New Roman	10	Word	2019-11-27	2020-01-13	2020-01-28
76	1	14	Computer Modern	11	LaTeX	2020-12-04	2021-01-15	2021-02-14
76	2	4	Arial	10	Word	2020-12-11	2021-01-18	2021-02-07
76	4	\N	\N	\N	\N	2020-12-15	2021-01-21	2021-02-20
76	3	\N	\N	\N	\N	2020-11-22	2020-12-29	2021-01-18
77	1	15	Computer Modern	10	LaTeX	2025-06-20	2025-08-05	2025-08-27
77	8	\N	\N	\N	\N	2025-06-11	2025-07-28	2025-08-12
77	9	4	Times New Roman	11	Word	2025-07-18	2025-09-02	2025-09-29
78	1	16	Times New Roman	12	LaTeX	2027-08-01	2027-09-20	2027-10-07
78	4	\N	\N	\N	\N	2027-07-05	2027-08-13	2027-08-29
78	3	\N	\N	\N	\N	2027-07-27	2027-09-08	2027-10-05
78	6	8	Computer Modern	12	LaTeX	2027-08-02	2027-09-20	2027-10-15
78	7	2	Computer Modern	11	Word	2027-07-26	2027-09-03	2027-10-03
79	1	15	Computer Modern	10	Word	2019-12-24	2020-02-05	2020-02-28
79	6	10	Arial	11	LaTeX	2020-01-21	2020-03-07	2020-03-31
80	1	14	Arial	12	LaTeX	2020-06-11	2020-07-20	2020-08-13
80	8	\N	\N	\N	\N	2020-06-10	2020-07-29	2020-08-18
80	7	2	Arial	11	LaTeX	2020-06-16	2020-07-30	2020-08-21
80	9	4	Computer Modern	10	LaTeX	2020-06-08	2020-07-25	2020-08-24
81	1	12	Computer Modern	11	LaTeX	2025-10-15	2025-12-01	2025-12-28
81	6	6	Computer Modern	12	LaTeX	2025-08-24	2025-10-06	2025-11-03
82	1	12	Times New Roman	11	LaTeX	2020-02-29	2020-04-16	2020-05-11
82	9	4	Times New Roman	12	Word	2020-03-25	2020-05-01	2020-05-24
83	1	15	Computer Modern	10	LaTeX	2026-08-07	2026-09-11	2026-09-29
83	5	6	Arial	12	LaTeX	2026-07-27	2026-09-08	2026-10-04
83	2	4	Arial	10	LaTeX	2026-06-23	2026-08-04	2026-08-24
83	7	2	Computer Modern	10	LaTeX	2026-08-05	2026-09-17	2026-10-17
83	6	6	Times New Roman	10	Word	2026-07-12	2026-08-21	2026-09-10
84	1	14	Times New Roman	11	Word	2023-02-14	2023-04-02	2023-05-01
84	8	\N	\N	\N	\N	2023-03-12	2023-04-30	2023-05-19
84	6	6	Arial	11	LaTeX	2023-02-21	2023-04-09	2023-05-06
84	9	4	Arial	11	LaTeX	2023-02-18	2023-04-04	2023-04-29
85	1	14	Times New Roman	11	LaTeX	2021-10-06	2021-11-12	2021-12-09
85	7	2	Arial	11	LaTeX	2021-10-26	2021-12-08	2021-12-30
85	3	\N	\N	\N	\N	2021-10-08	2021-11-19	2021-12-06
86	1	16	Computer Modern	11	LaTeX	2024-12-06	2025-01-22	2025-02-06
86	2	6	Computer Modern	11	LaTeX	2024-12-02	2025-01-14	2025-02-09
86	5	8	Times New Roman	10	LaTeX	2024-12-19	2025-01-30	2025-02-20
86	6	6	Arial	11	LaTeX	2024-11-14	2024-12-24	2025-01-10
86	4	\N	\N	\N	\N	2024-12-20	2025-02-02	2025-02-21
87	1	12	Arial	10	Word	2027-05-06	2027-06-19	2027-07-09
87	6	6	Times New Roman	10	LaTeX	2027-04-21	2027-05-31	2027-06-24
87	8	\N	\N	\N	\N	2027-04-24	2027-05-31	2027-06-17
87	3	\N	\N	\N	\N	2027-04-13	2027-05-21	2027-06-13
87	7	2	Times New Roman	10	Word	2027-04-10	2027-05-20	2027-06-07
88	1	15	Arial	10	LaTeX	2027-08-01	2027-09-15	2027-10-05
88	5	6	Times New Roman	12	LaTeX	2027-07-24	2027-09-02	2027-09-18
88	8	\N	\N	\N	\N	2027-06-26	2027-08-08	2027-09-06
89	1	14	Computer Modern	10	LaTeX	2021-05-14	2021-06-21	2021-07-13
89	9	4	Computer Modern	12	Word	2021-06-10	2021-07-29	2021-08-28
89	3	\N	\N	\N	\N	2021-06-06	2021-07-23	2021-08-15
90	1	12	Times New Roman	12	LaTeX	2025-01-14	2025-02-19	2025-03-12
90	4	\N	\N	\N	\N	2025-02-10	2025-03-29	2025-04-22
90	6	6	Times New Roman	11	Word	2025-02-11	2025-03-18	2025-04-12
90	5	8	Times New Roman	10	LaTeX	2025-01-17	2025-02-25	2025-03-26
90	3	\N	\N	\N	\N	2025-01-08	2025-02-19	2025-03-20
91	1	14	Computer Modern	10	LaTeX	2026-01-21	2026-03-11	2026-04-06
91	9	4	Computer Modern	11	LaTeX	2026-01-06	2026-02-14	2026-03-04
91	5	10	Arial	11	LaTeX	2026-01-10	2026-02-27	2026-03-16
91	8	\N	\N	\N	\N	2026-01-07	2026-02-26	2026-03-15
92	1	12	Arial	12	LaTeX	2024-03-02	2024-04-11	2024-04-26
92	7	2	Computer Modern	11	Word	2024-04-27	2024-06-01	2024-06-22
92	3	\N	\N	\N	\N	2024-04-01	2024-05-17	2024-06-11
92	4	\N	\N	\N	\N	2024-04-12	2024-05-28	2024-06-13
93	1	12	Computer Modern	11	Word	2026-05-13	2026-07-02	2026-07-30
93	9	4	Times New Roman	12	LaTeX	2026-05-16	2026-07-04	2026-07-27
94	1	14	Arial	10	LaTeX	2021-11-19	2022-01-02	2022-01-17
94	8	\N	\N	\N	\N	2021-10-01	2021-11-09	2021-12-07
94	3	\N	\N	\N	\N	2021-10-17	2021-11-29	2021-12-20
94	2	6	Computer Modern	10	LaTeX	2021-11-21	2021-12-28	2022-01-17
95	1	15	Arial	12	Word	2022-08-09	2022-09-27	2022-10-22
95	4	\N	\N	\N	\N	2022-06-19	2022-08-03	2022-08-28
95	7	2	Computer Modern	11	LaTeX	2022-07-12	2022-08-20	2022-09-12
95	5	10	Computer Modern	11	LaTeX	2022-07-24	2022-09-06	2022-10-06
95	2	4	Times New Roman	10	Word	2022-06-23	2022-08-01	2022-08-23
96	1	12	Arial	11	Word	2027-02-09	2027-03-26	2027-04-19
96	8	\N	\N	\N	\N	2027-03-03	2027-04-17	2027-05-03
96	7	2	Times New Roman	11	LaTeX	2027-02-08	2027-03-27	2027-04-24
96	5	8	Arial	10	LaTeX	2027-02-28	2027-04-13	2027-05-05
97	1	14	Computer Modern	10	LaTeX	2026-05-07	2026-06-16	2026-07-11
97	5	8	Times New Roman	12	Word	2026-06-22	2026-07-29	2026-08-13
97	4	\N	\N	\N	\N	2026-06-18	2026-07-24	2026-08-08
97	3	\N	\N	\N	\N	2026-05-28	2026-07-07	2026-07-23
97	6	6	Times New Roman	11	LaTeX	2026-06-19	2026-08-02	2026-08-28
98	1	12	Computer Modern	11	LaTeX	2020-05-09	2020-06-15	2020-07-01
98	2	4	Computer Modern	12	LaTeX	2020-05-29	2020-07-12	2020-07-29
99	1	12	Arial	10	Word	2027-05-25	2027-07-06	2027-07-30
99	3	\N	\N	\N	\N	2027-06-02	2027-07-21	2027-08-16
99	5	6	Computer Modern	12	LaTeX	2027-05-03	2027-06-16	2027-07-10
100	1	12	Times New Roman	10	LaTeX	2025-10-31	2025-12-09	2025-12-25
100	5	8	Arial	11	Word	2025-10-12	2025-11-20	2025-12-09
100	9	4	Arial	12	Word	2025-10-25	2025-12-14	2026-01-11
101	1	16	Times New Roman	10	LaTeX	2024-12-24	2025-02-08	2025-02-28
101	5	8	Arial	11	Word	2024-11-03	2024-12-16	2025-01-12
101	9	4	Arial	11	Word	2024-11-01	2024-12-16	2025-01-14
101	7	2	Times New Roman	11	LaTeX	2024-12-06	2025-01-15	2025-01-30
102	1	14	Times New Roman	10	Word	2020-10-07	2020-11-26	2020-12-19
102	2	4	Computer Modern	12	LaTeX	2020-09-29	2020-11-13	2020-12-09
102	3	\N	\N	\N	\N	2020-10-09	2020-11-17	2020-12-12
103	1	12	Arial	12	LaTeX	2023-02-05	2023-03-18	2023-04-15
103	8	\N	\N	\N	\N	2023-02-10	2023-03-31	2023-04-16
103	6	8	Computer Modern	11	Word	2023-02-26	2023-04-12	2023-04-27
103	9	4	Computer Modern	12	LaTeX	2023-02-08	2023-03-22	2023-04-16
104	1	12	Times New Roman	11	LaTeX	2020-06-16	2020-07-21	2020-08-12
104	6	6	Arial	12	Word	2020-06-05	2020-07-11	2020-07-28
104	5	10	Arial	12	LaTeX	2020-05-13	2020-06-26	2020-07-12
105	1	14	Arial	11	LaTeX	2021-09-27	2021-11-13	2021-12-08
105	5	6	Arial	12	LaTeX	2021-11-04	2021-12-16	2022-01-15
106	1	16	Times New Roman	11	LaTeX	2023-10-05	2023-11-22	2023-12-12
106	6	6	Times New Roman	10	LaTeX	2023-09-03	2023-10-17	2023-11-10
106	7	2	Times New Roman	12	Word	2023-10-17	2023-11-29	2023-12-19
107	1	12	Computer Modern	10	Word	2021-10-18	2021-11-24	2021-12-20
107	3	\N	\N	\N	\N	2021-09-05	2021-10-18	2021-11-02
107	5	8	Times New Roman	12	Word	2021-09-07	2021-10-14	2021-10-31
107	7	2	Computer Modern	11	LaTeX	2021-10-01	2021-11-11	2021-12-11
107	6	10	Arial	11	Word	2021-09-14	2021-10-31	2021-11-21
108	1	16	Computer Modern	10	LaTeX	2021-04-12	2021-06-01	2021-06-30
108	5	6	Arial	11	Word	2021-06-02	2021-07-21	2021-08-11
109	1	14	Arial	12	LaTeX	2027-01-30	2027-03-20	2027-04-06
109	8	\N	\N	\N	\N	2027-01-13	2027-02-21	2027-03-23
109	7	2	Computer Modern	12	LaTeX	2027-01-19	2027-03-05	2027-03-23
109	2	6	Times New Roman	12	LaTeX	2027-02-01	2027-03-09	2027-03-27
110	1	16	Computer Modern	11	LaTeX	2026-05-01	2026-06-16	2026-07-03
110	4	\N	\N	\N	\N	2026-05-04	2026-06-17	2026-07-12
110	9	4	Times New Roman	11	LaTeX	2026-04-24	2026-05-31	2026-06-19
110	8	\N	\N	\N	\N	2026-04-15	2026-05-23	2026-06-12
110	5	8	Computer Modern	12	Word	2026-03-30	2026-05-10	2026-05-27
111	1	16	Computer Modern	10	Word	2021-03-24	2021-05-07	2021-05-25
111	6	6	Arial	10	LaTeX	2021-04-30	2021-06-12	2021-06-28
112	1	14	Computer Modern	10	LaTeX	2024-04-24	2024-06-01	2024-06-24
112	2	4	Arial	10	LaTeX	2024-04-17	2024-05-25	2024-06-09
112	5	10	Arial	10	LaTeX	2024-04-11	2024-05-23	2024-06-20
112	4	\N	\N	\N	\N	2024-04-23	2024-06-04	2024-06-20
112	8	\N	\N	\N	\N	2024-05-01	2024-06-11	2024-07-08
113	1	15	Arial	10	Word	2026-02-22	2026-04-10	2026-05-08
113	6	8	Arial	10	Word	2026-02-04	2026-03-19	2026-04-18
113	4	\N	\N	\N	\N	2026-02-14	2026-03-25	2026-04-14
114	1	14	Times New Roman	12	LaTeX	2019-12-08	2020-01-13	2020-02-04
114	5	10	Times New Roman	12	LaTeX	2019-12-08	2020-01-18	2020-02-10
115	1	16	Arial	12	LaTeX	2025-04-15	2025-05-30	2025-06-20
115	8	\N	\N	\N	\N	2025-02-25	2025-04-12	2025-05-07
116	1	14	Times New Roman	12	Word	2022-11-12	2022-12-23	2023-01-11
116	8	\N	\N	\N	\N	2022-11-25	2023-01-14	2023-02-13
116	7	2	Computer Modern	11	LaTeX	2022-10-11	2022-11-23	2022-12-21
116	6	8	Times New Roman	11	LaTeX	2022-12-07	2023-01-12	2023-02-10
116	4	\N	\N	\N	\N	2022-11-22	2023-01-04	2023-01-24
117	1	15	Times New Roman	12	LaTeX	2024-05-14	2024-07-02	2024-07-28
117	2	4	Times New Roman	11	LaTeX	2024-04-28	2024-06-17	2024-07-14
117	5	10	Arial	12	LaTeX	2024-06-19	2024-07-31	2024-08-30
117	6	8	Arial	12	LaTeX	2024-06-13	2024-07-26	2024-08-21
117	9	4	Computer Modern	11	LaTeX	2024-05-04	2024-06-20	2024-07-05
118	1	15	Computer Modern	10	LaTeX	2025-04-08	2025-05-17	2025-06-01
118	9	4	Arial	11	Word	2025-03-27	2025-05-06	2025-05-24
118	6	8	Arial	10	LaTeX	2025-03-27	2025-05-13	2025-06-08
119	1	15	Computer Modern	12	LaTeX	2022-12-01	2023-01-20	2023-02-11
119	2	4	Times New Roman	10	LaTeX	2022-11-09	2022-12-16	2023-01-03
119	8	\N	\N	\N	\N	2022-11-27	2023-01-03	2023-01-21
119	4	\N	\N	\N	\N	2022-11-10	2022-12-29	2023-01-17
120	1	15	Computer Modern	10	LaTeX	2020-10-23	2020-11-30	2020-12-16
120	5	6	Arial	10	LaTeX	2020-10-05	2020-11-23	2020-12-14
120	3	\N	\N	\N	\N	2020-09-25	2020-11-07	2020-11-29
121	1	12	Computer Modern	11	LaTeX	2022-02-08	2022-03-23	2022-04-12
121	9	4	Computer Modern	11	LaTeX	2022-03-19	2022-04-30	2022-05-23
122	1	14	Times New Roman	12	LaTeX	2022-05-16	2022-06-20	2022-07-13
122	2	4	Computer Modern	11	LaTeX	2022-04-06	2022-05-16	2022-06-06
122	7	2	Arial	12	LaTeX	2022-04-10	2022-05-29	2022-06-20
123	1	14	Times New Roman	10	LaTeX	2023-03-12	2023-04-20	2023-05-07
123	6	6	Times New Roman	10	LaTeX	2023-04-06	2023-05-16	2023-06-13
123	8	\N	\N	\N	\N	2023-03-13	2023-04-20	2023-05-18
123	7	2	Arial	12	Word	2023-03-25	2023-05-04	2023-05-27
124	1	15	Times New Roman	12	LaTeX	2021-06-16	2021-08-04	2021-08-27
124	9	4	Arial	10	Word	2021-06-15	2021-08-01	2021-08-25
124	5	8	Arial	12	Word	2021-06-19	2021-07-25	2021-08-16
125	1	14	Arial	12	LaTeX	2019-11-12	2019-12-24	2020-01-12
125	2	6	Computer Modern	12	LaTeX	2019-11-08	2019-12-15	2020-01-09
125	6	6	Times New Roman	10	Word	2019-10-02	2019-11-11	2019-11-27
126	1	16	Computer Modern	11	LaTeX	2024-05-08	2024-06-26	2024-07-13
126	4	\N	\N	\N	\N	2024-05-04	2024-06-16	2024-07-11
127	1	12	Computer Modern	10	Word	2027-04-20	2027-05-25	2027-06-09
127	2	6	Computer Modern	12	Word	2027-04-17	2027-05-24	2027-06-10
128	1	15	Arial	10	Word	2022-03-04	2022-04-08	2022-04-27
128	2	4	Arial	10	Word	2022-03-10	2022-04-23	2022-05-17
128	8	\N	\N	\N	\N	2022-03-09	2022-04-28	2022-05-22
128	7	2	Arial	10	LaTeX	2022-03-20	2022-04-26	2022-05-15
129	1	12	Computer Modern	10	LaTeX	2020-10-09	2020-11-13	2020-11-29
129	9	4	Times New Roman	11	LaTeX	2020-10-16	2020-11-30	2020-12-17
129	2	4	Arial	10	LaTeX	2020-10-02	2020-11-09	2020-12-01
129	6	10	Computer Modern	12	LaTeX	2020-10-15	2020-11-20	2020-12-16
129	5	6	Times New Roman	11	Word	2020-10-03	2020-11-08	2020-12-08
130	1	12	Times New Roman	10	LaTeX	2022-11-14	2022-12-24	2023-01-12
130	7	2	Times New Roman	12	LaTeX	2022-12-17	2023-01-24	2023-02-08
130	8	\N	\N	\N	\N	2022-12-02	2023-01-13	2023-02-03
130	2	6	Times New Roman	12	LaTeX	2022-12-09	2023-01-19	2023-02-05
130	6	8	Computer Modern	10	LaTeX	2022-12-24	2023-02-09	2023-03-05
131	1	16	Computer Modern	11	LaTeX	2023-06-23	2023-08-01	2023-08-27
131	8	\N	\N	\N	\N	2023-07-09	2023-08-14	2023-09-10
131	9	4	Times New Roman	10	LaTeX	2023-07-20	2023-09-05	2023-09-25
132	1	14	Times New Roman	11	LaTeX	2022-01-22	2022-03-03	2022-03-27
132	7	2	Arial	10	LaTeX	2022-02-06	2022-03-26	2022-04-18
132	4	\N	\N	\N	\N	2022-02-10	2022-03-22	2022-04-14
133	1	12	Arial	10	LaTeX	2021-03-06	2021-04-11	2021-05-06
133	4	\N	\N	\N	\N	2021-04-13	2021-05-24	2021-06-14
133	5	10	Times New Roman	11	Word	2021-04-15	2021-05-31	2021-06-21
133	6	10	Arial	11	Word	2021-04-14	2021-05-23	2021-06-10
134	1	14	Times New Roman	11	Word	2026-04-10	2026-05-22	2026-06-08
134	3	\N	\N	\N	\N	2026-04-02	2026-05-14	2026-05-30
134	6	10	Arial	11	LaTeX	2026-02-25	2026-04-14	2026-04-30
134	2	4	Times New Roman	10	LaTeX	2026-03-29	2026-05-06	2026-06-04
134	8	\N	\N	\N	\N	2026-03-02	2026-04-06	2026-04-24
135	1	16	Arial	12	LaTeX	2019-12-14	2020-01-18	2020-02-09
135	8	\N	\N	\N	\N	2019-12-06	2020-01-19	2020-02-06
135	2	6	Arial	11	LaTeX	2019-11-06	2019-12-24	2020-01-08
135	6	6	Arial	12	Word	2019-10-27	2019-12-02	2019-12-19
136	1	16	Arial	10	LaTeX	2022-04-18	2022-05-30	2022-06-26
136	3	\N	\N	\N	\N	2022-04-20	2022-05-30	2022-06-19
136	6	8	Computer Modern	11	LaTeX	2022-03-03	2022-04-13	2022-05-02
136	4	\N	\N	\N	\N	2022-04-06	2022-05-13	2022-05-30
137	1	16	Arial	10	LaTeX	2026-08-28	2026-10-11	2026-10-30
137	2	6	Times New Roman	12	Word	2026-10-06	2026-11-25	2026-12-22
137	7	2	Times New Roman	10	Word	2026-10-15	2026-11-22	2026-12-11
137	8	\N	\N	\N	\N	2026-08-26	2026-10-06	2026-11-01
138	1	12	Times New Roman	10	LaTeX	2022-10-15	2022-11-23	2022-12-22
138	8	\N	\N	\N	\N	2022-09-20	2022-10-31	2022-11-23
138	6	10	Arial	10	LaTeX	2022-09-12	2022-10-27	2022-11-22
138	2	6	Arial	10	Word	2022-10-03	2022-11-10	2022-12-10
138	7	2	Computer Modern	12	LaTeX	2022-10-26	2022-12-08	2023-01-01
139	1	12	Arial	11	Word	2025-04-15	2025-05-24	2025-06-21
139	5	8	Arial	12	LaTeX	2025-03-30	2025-05-07	2025-05-23
139	4	\N	\N	\N	\N	2025-04-07	2025-05-13	2025-06-08
139	8	\N	\N	\N	\N	2025-04-09	2025-05-16	2025-06-09
139	3	\N	\N	\N	\N	2025-04-27	2025-06-06	2025-06-21
140	1	15	Arial	11	LaTeX	2025-04-27	2025-06-14	2025-07-11
140	6	8	Arial	10	LaTeX	2025-05-11	2025-06-26	2025-07-23
140	9	4	Times New Roman	10	LaTeX	2025-06-13	2025-07-27	2025-08-17
140	3	\N	\N	\N	\N	2025-04-26	2025-06-04	2025-07-02
140	5	6	Computer Modern	12	LaTeX	2025-05-20	2025-06-25	2025-07-23
141	1	14	Arial	12	Word	2027-01-08	2027-02-18	2027-03-14
141	8	\N	\N	\N	\N	2026-11-22	2027-01-07	2027-01-29
141	2	4	Computer Modern	12	LaTeX	2026-11-23	2027-01-01	2027-01-16
141	7	2	Arial	11	Word	2027-01-10	2027-02-27	2027-03-24
141	5	10	Computer Modern	12	LaTeX	2026-12-07	2027-01-15	2027-02-12
142	1	16	Arial	12	LaTeX	2024-01-09	2024-02-19	2024-03-05
142	8	\N	\N	\N	\N	2024-01-19	2024-02-29	2024-03-25
142	7	2	Computer Modern	12	LaTeX	2024-02-01	2024-03-17	2024-04-04
142	2	4	Computer Modern	10	LaTeX	2024-02-22	2024-04-06	2024-04-29
143	1	12	Computer Modern	12	LaTeX	2021-03-01	2021-04-17	2021-05-14
143	8	\N	\N	\N	\N	2021-04-04	2021-05-11	2021-06-01
144	1	12	Arial	10	Word	2023-11-28	2024-01-03	2024-01-26
144	2	4	Arial	10	Word	2023-12-02	2024-01-07	2024-02-05
144	9	4	Computer Modern	10	Word	2023-10-23	2023-12-11	2024-01-08
144	8	\N	\N	\N	\N	2023-12-05	2024-01-17	2024-02-01
145	1	16	Computer Modern	11	Word	2021-04-17	2021-05-27	2021-06-12
145	9	4	Computer Modern	12	Word	2021-05-04	2021-06-12	2021-07-08
145	5	10	Arial	12	LaTeX	2021-03-21	2021-05-10	2021-06-06
145	6	6	Times New Roman	10	LaTeX	2021-03-24	2021-05-06	2021-05-21
145	4	\N	\N	\N	\N	2021-04-13	2021-05-25	2021-06-11
146	1	15	Computer Modern	12	LaTeX	2026-12-09	2027-01-18	2027-02-08
146	7	2	Arial	10	LaTeX	2026-12-25	2027-01-29	2027-02-19
146	4	\N	\N	\N	\N	2026-12-30	2027-02-06	2027-02-28
147	1	15	Times New Roman	10	LaTeX	2022-05-06	2022-06-24	2022-07-24
147	5	10	Times New Roman	12	LaTeX	2022-05-10	2022-06-23	2022-07-17
147	8	\N	\N	\N	\N	2022-05-11	2022-06-19	2022-07-16
147	6	8	Times New Roman	10	LaTeX	2022-04-26	2022-06-01	2022-06-19
147	4	\N	\N	\N	\N	2022-05-01	2022-06-13	2022-07-01
148	1	14	Times New Roman	10	Word	2025-01-09	2025-02-27	2025-03-29
148	9	4	Arial	11	LaTeX	2025-03-02	2025-04-21	2025-05-11
148	6	8	Times New Roman	12	LaTeX	2025-01-30	2025-03-16	2025-04-15
148	2	6	Computer Modern	10	Word	2025-01-10	2025-02-17	2025-03-09
148	3	\N	\N	\N	\N	2025-01-18	2025-03-08	2025-03-23
149	1	16	Computer Modern	12	LaTeX	2022-05-06	2022-06-25	2022-07-11
149	8	\N	\N	\N	\N	2022-04-10	2022-05-15	2022-06-10
149	5	10	Times New Roman	10	LaTeX	2022-04-17	2022-05-22	2022-06-18
149	7	2	Arial	12	LaTeX	2022-04-25	2022-06-10	2022-07-05
149	2	6	Arial	10	Word	2022-06-04	2022-07-19	2022-08-17
150	1	16	Times New Roman	12	Word	2026-06-29	2026-08-07	2026-09-01
150	4	\N	\N	\N	\N	2026-05-30	2026-07-12	2026-08-03
151	1	12	Arial	12	Word	2023-03-30	2023-05-09	2023-05-28
151	6	8	Arial	11	Word	2023-05-15	2023-07-02	2023-07-25
151	8	\N	\N	\N	\N	2023-04-20	2023-05-27	2023-06-13
151	9	4	Arial	11	LaTeX	2023-05-11	2023-06-26	2023-07-25
151	2	6	Computer Modern	10	Word	2023-05-07	2023-06-16	2023-07-08
152	1	12	Arial	12	LaTeX	2027-02-19	2027-04-03	2027-04-30
152	2	6	Computer Modern	12	LaTeX	2027-02-16	2027-04-07	2027-05-04
152	6	10	Times New Roman	12	Word	2027-01-25	2027-03-05	2027-03-30
153	1	12	Arial	11	LaTeX	2022-06-03	2022-07-15	2022-08-10
153	2	4	Times New Roman	10	LaTeX	2022-05-21	2022-07-05	2022-08-03
153	5	8	Times New Roman	12	LaTeX	2022-04-18	2022-05-28	2022-06-22
153	7	2	Computer Modern	10	Word	2022-05-16	2022-07-02	2022-07-23
154	1	14	Arial	10	LaTeX	2023-07-11	2023-08-23	2023-09-19
154	4	\N	\N	\N	\N	2023-07-20	2023-08-29	2023-09-21
154	7	2	Computer Modern	11	LaTeX	2023-08-09	2023-09-23	2023-10-13
155	1	15	Arial	10	Word	2022-03-15	2022-04-26	2022-05-21
155	8	\N	\N	\N	\N	2022-02-12	2022-03-31	2022-04-26
155	6	10	Computer Modern	10	Word	2022-03-06	2022-04-10	2022-05-10
156	1	12	Arial	12	LaTeX	2022-06-14	2022-07-27	2022-08-18
156	9	4	Times New Roman	10	Word	2022-05-07	2022-06-13	2022-07-01
156	8	\N	\N	\N	\N	2022-05-10	2022-06-24	2022-07-16
156	7	2	Computer Modern	10	LaTeX	2022-06-15	2022-07-21	2022-08-07
157	1	12	Times New Roman	11	Word	2020-09-14	2020-10-29	2020-11-19
157	9	4	Computer Modern	11	LaTeX	2020-09-10	2020-10-21	2020-11-18
157	2	4	Times New Roman	10	LaTeX	2020-11-03	2020-12-08	2020-12-31
157	4	\N	\N	\N	\N	2020-10-25	2020-12-13	2021-01-09
158	1	16	Computer Modern	10	LaTeX	2022-04-11	2022-05-17	2022-06-05
158	9	4	Arial	11	LaTeX	2022-03-23	2022-05-08	2022-06-04
159	1	16	Times New Roman	10	LaTeX	2022-02-13	2022-04-02	2022-05-01
159	7	2	Arial	11	LaTeX	2022-02-23	2022-04-09	2022-05-04
160	1	12	Times New Roman	10	LaTeX	2024-05-29	2024-07-12	2024-07-30
160	6	8	Arial	10	Word	2024-04-11	2024-05-17	2024-06-02
160	3	\N	\N	\N	\N	2024-04-26	2024-06-07	2024-06-24
160	9	4	Times New Roman	10	LaTeX	2024-05-22	2024-06-30	2024-07-18
161	7	2	Computer Modern	12	Word	2025-09-22	2025-11-09	2025-11-29
162	2	6	Computer Modern	12	LaTeX	2021-04-10	2021-05-22	2021-06-19
163	7	2	Times New Roman	10	Word	2022-03-22	2022-05-07	2022-05-31
163	1	14	Times New Roman	12	LaTeX	2022-04-15	2022-05-23	2022-06-11
164	1	14	Computer Modern	10	LaTeX	2024-04-03	2024-05-08	2024-05-25
165	2	6	Computer Modern	11	LaTeX	2024-10-20	2024-12-08	2024-12-28
165	1	16	Times New Roman	12	LaTeX	2024-10-15	2024-11-30	2024-12-23
166	2	4	Computer Modern	10	Word	2027-01-24	2027-03-03	2027-03-30
166	1	16	Computer Modern	12	Word	2027-02-09	2027-03-21	2027-04-07
167	2	6	Times New Roman	12	LaTeX	2026-07-15	2026-08-24	2026-09-12
168	7	2	Computer Modern	12	LaTeX	2023-06-06	2023-07-15	2023-08-06
169	2	4	Computer Modern	11	LaTeX	2024-06-04	2024-07-24	2024-08-22
169	7	2	Computer Modern	12	Word	2024-04-12	2024-05-17	2024-06-11
170	7	2	Times New Roman	11	LaTeX	2025-04-20	2025-05-30	2025-06-19
170	2	4	Arial	11	LaTeX	2025-03-09	2025-04-27	2025-05-27
171	7	2	Arial	10	Word	2026-06-28	2026-08-05	2026-08-24
172	2	6	Times New Roman	12	Word	2026-10-14	2026-12-03	2027-01-01
173	1	15	Arial	10	Word	2025-11-13	2025-12-18	2026-01-10
173	7	2	Times New Roman	10	Word	2025-10-02	2025-11-16	2025-12-04
174	7	2	Times New Roman	11	LaTeX	2023-02-07	2023-03-19	2023-04-14
175	1	12	Arial	11	LaTeX	2026-01-27	2026-03-16	2026-04-15
176	1	14	Arial	12	LaTeX	2026-04-16	2026-05-25	2026-06-12
176	7	2	Arial	12	LaTeX	2026-05-06	2026-06-24	2026-07-13
177	2	4	Times New Roman	12	LaTeX	2025-05-10	2025-06-19	2025-07-05
177	1	14	Computer Modern	12	LaTeX	2025-04-06	2025-05-25	2025-06-16
178	7	2	Times New Roman	10	LaTeX	2027-03-01	2027-04-19	2027-05-13
179	7	2	Arial	11	LaTeX	2025-10-31	2025-12-15	2025-12-30
179	1	15	Computer Modern	10	Word	2025-12-21	2026-01-25	2026-02-15
180	1	14	Times New Roman	11	LaTeX	2020-05-24	2020-06-28	2020-07-16
180	2	6	Times New Roman	10	LaTeX	2020-06-18	2020-08-03	2020-08-28
181	1	12	Times New Roman	11	LaTeX	2020-10-11	2020-11-16	2020-12-14
182	2	4	Times New Roman	10	LaTeX	2019-12-01	2020-01-07	2020-02-04
183	1	14	Times New Roman	12	LaTeX	2021-05-01	2021-06-14	2021-06-30
183	7	2	Computer Modern	12	LaTeX	2021-03-18	2021-05-04	2021-06-03
184	2	6	Times New Roman	11	LaTeX	2020-02-28	2020-04-08	2020-04-30
184	7	2	Arial	10	LaTeX	2020-02-28	2020-04-03	2020-04-21
185	7	2	Times New Roman	11	Word	2026-08-03	2026-09-21	2026-10-18
185	1	15	Times New Roman	12	LaTeX	2026-08-07	2026-09-11	2026-09-29
186	2	6	Times New Roman	10	LaTeX	2021-06-20	2021-07-31	2021-08-16
187	2	4	Times New Roman	10	Word	2027-07-26	2027-09-07	2027-10-07
188	1	16	Computer Modern	11	LaTeX	2023-01-28	2023-03-15	2023-04-13
188	2	4	Times New Roman	12	LaTeX	2023-02-18	2023-03-28	2023-04-12
189	2	4	Times New Roman	10	Word	2026-06-02	2026-07-11	2026-07-28
189	7	2	Computer Modern	11	LaTeX	2026-05-31	2026-07-20	2026-08-04
190	7	2	Computer Modern	12	LaTeX	2023-09-02	2023-10-09	2023-10-27
190	1	12	Times New Roman	12	Word	2023-10-13	2023-11-25	2023-12-11
191	2	4	Arial	12	Word	2025-07-20	2025-08-26	2025-09-20
192	2	6	Computer Modern	12	LaTeX	2026-04-05	2026-05-17	2026-06-03
192	7	2	Computer Modern	10	LaTeX	2026-03-24	2026-05-11	2026-06-07
193	2	4	Computer Modern	10	LaTeX	2026-02-24	2026-04-08	2026-04-30
194	1	16	Times New Roman	11	LaTeX	2025-10-16	2025-11-28	2025-12-18
195	1	12	Computer Modern	12	Word	2022-04-09	2022-05-14	2022-06-06
196	7	2	Computer Modern	12	LaTeX	2020-10-31	2020-12-14	2020-12-29
197	7	2	Times New Roman	10	LaTeX	2026-12-21	2027-02-08	2027-03-06
197	1	16	Arial	10	LaTeX	2027-01-10	2027-02-15	2027-03-15
198	2	4	Computer Modern	12	Word	2022-07-06	2022-08-22	2022-09-08
199	7	2	Arial	11	LaTeX	2024-05-21	2024-07-07	2024-08-06
199	1	12	Computer Modern	11	LaTeX	2024-05-05	2024-06-12	2024-07-05
200	2	6	Arial	12	Word	2026-06-06	2026-07-23	2026-08-18
201	7	2	Computer Modern	10	LaTeX	2025-09-03	2025-10-20	2025-11-16
201	2	6	Times New Roman	12	LaTeX	2025-09-28	2025-11-11	2025-11-30
202	1	16	Arial	10	LaTeX	2027-04-02	2027-05-18	2027-06-09
203	7	2	Computer Modern	10	Word	2020-04-13	2020-05-19	2020-06-16
203	1	12	Computer Modern	10	LaTeX	2020-04-24	2020-05-31	2020-06-28
204	7	2	Computer Modern	12	LaTeX	2020-03-27	2020-05-07	2020-06-04
204	1	14	Computer Modern	11	Word	2020-03-22	2020-04-26	2020-05-21
205	7	2	Times New Roman	11	LaTeX	2020-11-16	2020-12-26	2021-01-21
205	1	15	Arial	11	LaTeX	2020-12-05	2021-01-12	2021-02-09
\.


--
-- Data for Name: theme; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.theme (id_theme, libelle, id_theme_parent) FROM stdin;
1	Spatial databases	\N
2	GIS	1
3	Geographic information retrieval	2
4	Cartographic generalization	2
5	Spatial indexing	1
6	R-tree	5
7	Quadtree	5
8	Spatio-temporal data	1
9	Trajectory data	8
10	Moving objects	8
11	Location-based services	1
12	Remote sensing data	1
13	Temporal databases	\N
14	Temporal data models	13
15	Temporal database design	13
16	Temporal query languages	13
17	Indexing of temporal data	13
18	Data management	\N
19	Query optimization	18
20	Transaction processing	18
21	NoSQL databases	18
22	Graph databases	21
23	Document stores	21
24	Data integration	18
25	Data quality	18
26	Information systems engineering	\N
27	Conceptual modeling	26
28	Entity-relationship model	27
29	Business process management	26
30	Requirements engineering	26
31	Artificial intelligence	\N
32	Machine learning	31
33	Deep learning	32
34	Reinforcement learning	32
35	Natural language processing	31
36	Knowledge graphs	31
37	Big data	\N
38	Distributed computing	37
39	Stream processing	37
40	Data lakes	37
41	Security and privacy	\N
42	Access control	41
43	Data anonymization	41
\.


--
-- Data for Name: type_responsabilite; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.type_responsabilite (id_type, libelle) FROM stdin;
1	General chair
2	Program Committee chair
3	Steering Committee
4	Poster chair
5	Industrial session chair
6	Workshop chair
7	Publication chair
\.


--
-- Data for Name: utilisateur; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.utilisateur (id_personne, login, mot_de_passe, role) FROM stdin;
321	admin	scrypt:32768:8:1$IKOVM3swa2ZNK49F$c5ffda1855fda0e86ec51f0bb52649e1fd98194da982804264860ae01ad5d6d26b0d418a80b105fdbdf7dff75092c004decd86072865d78540b20b1561b54831	admin
2	alice	scrypt:32768:8:1$XNGVTH38EVx0RND9$40327c29f726e1ba4c40c10c7b3573edbcbc7faacd3011eaba2fb1be29a30fba43a7cfc8baddf9327dbcf5f421ce4a721e2b681d08b3855de347358907f8cf6e	utilisateur
183	kmontanelli183	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
155	fcannon155	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
202	dhentschel202	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
217	eruiz217	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
278	mrousseau278	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
282	lmitschke282	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
311	lbejarano311	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
115	mcuesta115	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
252	salvarez252	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
142	fchauvet142	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
226	ibodin226	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
251	kclement251	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
17	mmogherini17	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
175	abien175	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
210	cgillespie210	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
87	vmason87	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
242	santunez242	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
68	anohlmans68	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
276	moliboni276	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
16	babbagnale16	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
204	rdonaldson204	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
306	fvento306	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
291	aabad291	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
45	rgomila45	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
322	jsuarez322	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
323	mvance323	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
324	leimer324	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
325	tbotella325	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
326	malarcon326	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
327	mdaza327	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
328	ecuomo328	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
329	acoll329	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
330	mvasseur330	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
331	gaubry331	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
332	hlaroche332	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
333	akraushaar333	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
334	rfournier334	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
335	ellanos335	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
336	cdavila336	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
337	fossola337	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
338	fblondel338	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
339	pblack339	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
340	mneuschafer340	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
341	vagudo341	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
342	sgonzales342	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
343	chahn343	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
344	jschleich344	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
345	mperry345	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
346	ileduc346	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
347	sgarza347	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
348	awilliams348	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
349	dtaylor349	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
350	acollado350	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
351	jgirschner351	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
352	salfonso352	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
353	tfabre353	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
354	csommaruga354	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
355	jcocci355	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
356	ohanson356	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
357	jramsey357	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
358	sbombieri358	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
359	nrodriguez359	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
360	arivas360	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
361	calvarez361	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
362	erossi362	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
363	mmorin363	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
364	fwinters364	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
365	pbecker365	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
366	vpaganini366	scrypt:32768:8:1$NvfoTEORrY1It5cG$a688ee9cb989d788f0151fd81c0c66281e100959f0b4f2b2c6e526a911c9f66925979174d3e49f526c314d7ced1e4f39316c00b2e837dcfb303d6faad85da9be	utilisateur
\.


--
-- Data for Name: utilisateur_theme; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.utilisateur_theme (id_personne, id_theme) FROM stdin;
2	1
16	5
16	8
16	31
17	20
17	25
17	33
17	37
45	7
45	9
45	33
45	42
68	31
87	8
115	7
115	27
115	34
142	26
142	41
155	5
155	26
155	31
155	34
175	6
175	21
175	22
183	37
202	17
202	39
204	28
210	4
210	21
210	43
217	35
226	17
226	28
226	35
226	40
242	12
242	39
251	26
251	38
252	21
252	40
276	3
276	16
276	25
278	26
282	7
282	10
282	18
282	36
291	14
291	16
291	21
291	27
306	15
311	29
322	21
322	24
322	39
323	25
324	1
324	2
324	4
324	39
325	9
325	20
325	34
326	4
326	12
326	19
327	18
327	25
327	36
327	40
328	4
328	27
328	28
328	32
329	11
329	17
329	28
330	20
331	24
331	28
331	32
332	2
332	22
332	35
332	37
333	13
333	15
333	20
333	21
334	28
335	16
335	24
336	9
336	25
336	26
337	22
337	27
338	4
338	7
338	26
339	15
339	23
339	39
340	1
341	8
341	10
341	11
341	12
342	12
342	28
342	29
343	20
343	26
343	31
343	43
344	21
344	40
345	25
346	7
347	12
348	6
348	7
348	24
349	34
349	35
349	41
350	1
350	4
350	7
350	35
351	26
351	31
351	34
351	38
352	6
352	9
352	13
352	36
353	37
353	39
354	1
354	18
354	29
355	9
355	11
355	17
355	27
356	5
356	8
356	10
356	11
357	14
358	15
358	22
358	31
359	23
359	28
360	4
360	30
360	35
360	36
361	11
361	24
361	41
362	12
362	20
362	33
363	8
363	43
364	21
364	33
365	4
365	18
365	24
366	28
\.


--
-- Data for Name: ville; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.ville (id_ville, nom_ville, id_pays) FROM stdin;
1	Lyon	1
2	Paris	1
3	Toulouse	1
4	Grenoble	1
5	Nantes	1
6	Berlin	2
7	Munich	2
8	Hambourg	2
9	Rome	3
10	Milan	3
11	Turin	3
12	Madrid	4
13	Barcelone	4
14	Valence	4
15	Londres	5
16	Édimbourg	5
17	Manchester	5
18	Amsterdam	6
19	Delft	6
20	Bruxelles	7
21	Louvain	7
22	Zurich	8
23	Genève	8
24	Lausanne	8
25	Montréal	9
26	Toronto	9
27	Vancouver	9
28	New York	10
29	San Francisco	10
30	Boston	10
31	Seattle	10
32	Tokyo	11
33	Kyoto	11
34	Pékin	12
35	Shanghai	12
36	São Paulo	13
37	Rio de Janeiro	13
38	Tunis	14
39	Sousse	14
40	Sydney	15
41	Melbourne	15
\.


--
-- Data for Name: workshop; Type: TABLE DATA; Schema: conferences; Owner: -
--

COPY conferences.workshop (id_conf, id_conf_mere) FROM stdin;
161	9
162	108
163	158
164	5
165	62
166	53
167	18
168	26
169	160
170	115
171	13
172	63
173	12
174	103
175	113
176	60
177	139
178	56
179	15
180	36
181	129
182	75
183	145
184	82
185	83
186	61
187	78
188	37
189	57
190	106
191	77
192	71
193	16
194	72
195	122
196	76
197	146
198	95
199	117
200	23
201	81
202	87
203	1
204	1
205	2
\.


--
-- Name: categorie_soumission_id_categorie_seq; Type: SEQUENCE SET; Schema: conferences; Owner: -
--

SELECT pg_catalog.setval('conferences.categorie_soumission_id_categorie_seq', 9, true);


--
-- Name: conference_id_conf_seq; Type: SEQUENCE SET; Schema: conferences; Owner: -
--

SELECT pg_catalog.setval('conferences.conference_id_conf_seq', 205, true);


--
-- Name: editeur_id_editeur_seq; Type: SEQUENCE SET; Schema: conferences; Owner: -
--

SELECT pg_catalog.setval('conferences.editeur_id_editeur_seq', 8, true);


--
-- Name: organisme_id_organisme_seq; Type: SEQUENCE SET; Schema: conferences; Owner: -
--

SELECT pg_catalog.setval('conferences.organisme_id_organisme_seq', 27, true);


--
-- Name: pays_id_pays_seq; Type: SEQUENCE SET; Schema: conferences; Owner: -
--

SELECT pg_catalog.setval('conferences.pays_id_pays_seq', 15, true);


--
-- Name: personne_id_personne_seq; Type: SEQUENCE SET; Schema: conferences; Owner: -
--

SELECT pg_catalog.setval('conferences.personne_id_personne_seq', 366, true);


--
-- Name: serie_id_serie_seq; Type: SEQUENCE SET; Schema: conferences; Owner: -
--

SELECT pg_catalog.setval('conferences.serie_id_serie_seq', 9, true);


--
-- Name: theme_id_theme_seq; Type: SEQUENCE SET; Schema: conferences; Owner: -
--

SELECT pg_catalog.setval('conferences.theme_id_theme_seq', 43, true);


--
-- Name: type_responsabilite_id_type_seq; Type: SEQUENCE SET; Schema: conferences; Owner: -
--

SELECT pg_catalog.setval('conferences.type_responsabilite_id_type_seq', 7, true);


--
-- Name: ville_id_ville_seq; Type: SEQUENCE SET; Schema: conferences; Owner: -
--

SELECT pg_catalog.setval('conferences.ville_id_ville_seq', 41, true);


--
-- Name: categorie_soumission categorie_soumission_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.categorie_soumission
    ADD CONSTRAINT categorie_soumission_pkey PRIMARY KEY (id_categorie);


--
-- Name: conference conference_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.conference
    ADD CONSTRAINT conference_pkey PRIMARY KEY (id_conf);


--
-- Name: editeur editeur_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.editeur
    ADD CONSTRAINT editeur_pkey PRIMARY KEY (id_editeur);


--
-- Name: organisme organisme_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.organisme
    ADD CONSTRAINT organisme_pkey PRIMARY KEY (id_organisme);


--
-- Name: pays pays_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.pays
    ADD CONSTRAINT pays_pkey PRIMARY KEY (id_pays);


--
-- Name: personne personne_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.personne
    ADD CONSTRAINT personne_pkey PRIMARY KEY (id_personne);


--
-- Name: evalue pk_evalue; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.evalue
    ADD CONSTRAINT pk_evalue PRIMARY KEY (id_personne, id_conf, num_session);


--
-- Name: membre_pc pk_membre_pc; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.membre_pc
    ADD CONSTRAINT pk_membre_pc PRIMARY KEY (id_personne, id_conf);


--
-- Name: responsable_de pk_responsable_de; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.responsable_de
    ADD CONSTRAINT pk_responsable_de PRIMARY KEY (id_personne, id_conf, id_type);


--
-- Name: session pk_session; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.session
    ADD CONSTRAINT pk_session PRIMARY KEY (id_conf, num_session);


--
-- Name: session_theme pk_session_theme; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.session_theme
    ADD CONSTRAINT pk_session_theme PRIMARY KEY (id_conf, num_session, id_theme);


--
-- Name: specification pk_specification; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.specification
    ADD CONSTRAINT pk_specification PRIMARY KEY (id_conf, id_categorie);


--
-- Name: utilisateur_theme pk_utilisateur_theme; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.utilisateur_theme
    ADD CONSTRAINT pk_utilisateur_theme PRIMARY KEY (id_personne, id_theme);


--
-- Name: serie serie_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.serie
    ADD CONSTRAINT serie_pkey PRIMARY KEY (id_serie);


--
-- Name: theme theme_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.theme
    ADD CONSTRAINT theme_pkey PRIMARY KEY (id_theme);


--
-- Name: type_responsabilite type_responsabilite_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.type_responsabilite
    ADD CONSTRAINT type_responsabilite_pkey PRIMARY KEY (id_type);


--
-- Name: categorie_soumission uq_categorie_libelle; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.categorie_soumission
    ADD CONSTRAINT uq_categorie_libelle UNIQUE (libelle);


--
-- Name: editeur uq_editeur_nom; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.editeur
    ADD CONSTRAINT uq_editeur_nom UNIQUE (nom_editeur);


--
-- Name: pays uq_pays_nom; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.pays
    ADD CONSTRAINT uq_pays_nom UNIQUE (nom_pays);


--
-- Name: personne uq_personne_email; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.personne
    ADD CONSTRAINT uq_personne_email UNIQUE (email);


--
-- Name: serie uq_serie_sigle; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.serie
    ADD CONSTRAINT uq_serie_sigle UNIQUE (sigle);


--
-- Name: theme uq_theme_libelle; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.theme
    ADD CONSTRAINT uq_theme_libelle UNIQUE (libelle);


--
-- Name: type_responsabilite uq_type_resp_libelle; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.type_responsabilite
    ADD CONSTRAINT uq_type_resp_libelle UNIQUE (libelle);


--
-- Name: utilisateur uq_utilisateur_login; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.utilisateur
    ADD CONSTRAINT uq_utilisateur_login UNIQUE (login);


--
-- Name: ville uq_ville_nom_pays; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.ville
    ADD CONSTRAINT uq_ville_nom_pays UNIQUE (nom_ville, id_pays);


--
-- Name: utilisateur utilisateur_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.utilisateur
    ADD CONSTRAINT utilisateur_pkey PRIMARY KEY (id_personne);


--
-- Name: ville ville_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.ville
    ADD CONSTRAINT ville_pkey PRIMARY KEY (id_ville);


--
-- Name: workshop workshop_pkey; Type: CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.workshop
    ADD CONSTRAINT workshop_pkey PRIMARY KEY (id_conf);


--
-- Name: idx_conference_date_debut; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_conference_date_debut ON conferences.conference USING btree (date_debut);


--
-- Name: idx_conference_editeur; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_conference_editeur ON conferences.conference USING btree (id_editeur);


--
-- Name: idx_conference_intitule_trgm; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_conference_intitule_trgm ON conferences.conference USING gin (intitule public.gin_trgm_ops);


--
-- Name: idx_conference_organisme; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_conference_organisme ON conferences.conference USING btree (id_organisme);


--
-- Name: idx_conference_serie; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_conference_serie ON conferences.conference USING btree (id_serie);


--
-- Name: idx_conference_ville; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_conference_ville ON conferences.conference USING btree (id_ville);


--
-- Name: idx_evalue_session; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_evalue_session ON conferences.evalue USING btree (id_conf, num_session);


--
-- Name: idx_membre_pc_conf; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_membre_pc_conf ON conferences.membre_pc USING btree (id_conf);


--
-- Name: idx_personne_nom_lower; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_personne_nom_lower ON conferences.personne USING btree (lower((nom)::text), lower((prenom)::text));


--
-- Name: idx_resp_conf; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_resp_conf ON conferences.responsable_de USING btree (id_conf);


--
-- Name: idx_resp_type; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_resp_type ON conferences.responsable_de USING btree (id_type);


--
-- Name: idx_session_theme_theme; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_session_theme_theme ON conferences.session_theme USING btree (id_theme);


--
-- Name: idx_specification_cat; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_specification_cat ON conferences.specification USING btree (id_categorie);


--
-- Name: idx_theme_libelle_trgm; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_theme_libelle_trgm ON conferences.theme USING gin (libelle public.gin_trgm_ops);


--
-- Name: idx_theme_parent; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_theme_parent ON conferences.theme USING btree (id_theme_parent);


--
-- Name: idx_util_theme_theme; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_util_theme_theme ON conferences.utilisateur_theme USING btree (id_theme);


--
-- Name: idx_ville_pays; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_ville_pays ON conferences.ville USING btree (id_pays);


--
-- Name: idx_workshop_mere; Type: INDEX; Schema: conferences; Owner: -
--

CREATE INDEX idx_workshop_mere ON conferences.workshop USING btree (id_conf_mere);


--
-- Name: evalue trg_evalue_membre_pc; Type: TRIGGER; Schema: conferences; Owner: -
--

CREATE TRIGGER trg_evalue_membre_pc BEFORE INSERT OR UPDATE ON conferences.evalue FOR EACH ROW EXECUTE FUNCTION conferences.fn_check_evaluateur_membre_pc();


--
-- Name: membre_pc trg_membre_pc_retrait; Type: TRIGGER; Schema: conferences; Owner: -
--

CREATE TRIGGER trg_membre_pc_retrait BEFORE DELETE OR UPDATE ON conferences.membre_pc FOR EACH ROW EXECUTE FUNCTION conferences.fn_check_retrait_membre_pc();


--
-- Name: specification trg_specification_dates; Type: TRIGGER; Schema: conferences; Owner: -
--

CREATE TRIGGER trg_specification_dates BEFORE INSERT OR UPDATE ON conferences.specification FOR EACH ROW EXECUTE FUNCTION conferences.fn_check_specification_dates();


--
-- Name: theme trg_theme_cycle; Type: TRIGGER; Schema: conferences; Owner: -
--

CREATE TRIGGER trg_theme_cycle BEFORE INSERT OR UPDATE OF id_theme_parent ON conferences.theme FOR EACH ROW EXECUTE FUNCTION conferences.fn_check_theme_cycle();


--
-- Name: workshop trg_workshop_coherence; Type: TRIGGER; Schema: conferences; Owner: -
--

CREATE TRIGGER trg_workshop_coherence BEFORE INSERT OR UPDATE ON conferences.workshop FOR EACH ROW EXECUTE FUNCTION conferences.fn_check_workshop();


--
-- Name: conference fk_conf_editeur; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.conference
    ADD CONSTRAINT fk_conf_editeur FOREIGN KEY (id_editeur) REFERENCES conferences.editeur(id_editeur) ON DELETE SET NULL;


--
-- Name: conference fk_conf_organisme; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.conference
    ADD CONSTRAINT fk_conf_organisme FOREIGN KEY (id_organisme) REFERENCES conferences.organisme(id_organisme) ON DELETE RESTRICT;


--
-- Name: conference fk_conf_serie; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.conference
    ADD CONSTRAINT fk_conf_serie FOREIGN KEY (id_serie) REFERENCES conferences.serie(id_serie) ON DELETE SET NULL;


--
-- Name: conference fk_conf_ville; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.conference
    ADD CONSTRAINT fk_conf_ville FOREIGN KEY (id_ville) REFERENCES conferences.ville(id_ville) ON DELETE RESTRICT;


--
-- Name: evalue fk_evalue_personne; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.evalue
    ADD CONSTRAINT fk_evalue_personne FOREIGN KEY (id_personne) REFERENCES conferences.personne(id_personne) ON DELETE RESTRICT;


--
-- Name: evalue fk_evalue_session; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.evalue
    ADD CONSTRAINT fk_evalue_session FOREIGN KEY (id_conf, num_session) REFERENCES conferences.session(id_conf, num_session) ON DELETE CASCADE;


--
-- Name: membre_pc fk_pc_conf; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.membre_pc
    ADD CONSTRAINT fk_pc_conf FOREIGN KEY (id_conf) REFERENCES conferences.conference(id_conf) ON DELETE CASCADE;


--
-- Name: membre_pc fk_pc_personne; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.membre_pc
    ADD CONSTRAINT fk_pc_personne FOREIGN KEY (id_personne) REFERENCES conferences.personne(id_personne) ON DELETE RESTRICT;


--
-- Name: responsable_de fk_resp_conf; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.responsable_de
    ADD CONSTRAINT fk_resp_conf FOREIGN KEY (id_conf) REFERENCES conferences.conference(id_conf) ON DELETE CASCADE;


--
-- Name: responsable_de fk_resp_personne; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.responsable_de
    ADD CONSTRAINT fk_resp_personne FOREIGN KEY (id_personne) REFERENCES conferences.personne(id_personne) ON DELETE RESTRICT;


--
-- Name: responsable_de fk_resp_type; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.responsable_de
    ADD CONSTRAINT fk_resp_type FOREIGN KEY (id_type) REFERENCES conferences.type_responsabilite(id_type) ON DELETE RESTRICT;


--
-- Name: session fk_session_conf; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.session
    ADD CONSTRAINT fk_session_conf FOREIGN KEY (id_conf) REFERENCES conferences.conference(id_conf) ON DELETE CASCADE;


--
-- Name: specification fk_spec_categorie; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.specification
    ADD CONSTRAINT fk_spec_categorie FOREIGN KEY (id_categorie) REFERENCES conferences.categorie_soumission(id_categorie) ON DELETE RESTRICT;


--
-- Name: specification fk_spec_conf; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.specification
    ADD CONSTRAINT fk_spec_conf FOREIGN KEY (id_conf) REFERENCES conferences.conference(id_conf) ON DELETE CASCADE;


--
-- Name: session_theme fk_st_session; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.session_theme
    ADD CONSTRAINT fk_st_session FOREIGN KEY (id_conf, num_session) REFERENCES conferences.session(id_conf, num_session) ON DELETE CASCADE;


--
-- Name: session_theme fk_st_theme; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.session_theme
    ADD CONSTRAINT fk_st_theme FOREIGN KEY (id_theme) REFERENCES conferences.theme(id_theme) ON DELETE RESTRICT;


--
-- Name: theme fk_theme_parent; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.theme
    ADD CONSTRAINT fk_theme_parent FOREIGN KEY (id_theme_parent) REFERENCES conferences.theme(id_theme) ON DELETE SET NULL;


--
-- Name: utilisateur_theme fk_ut_theme; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.utilisateur_theme
    ADD CONSTRAINT fk_ut_theme FOREIGN KEY (id_theme) REFERENCES conferences.theme(id_theme) ON DELETE CASCADE;


--
-- Name: utilisateur_theme fk_ut_utilisateur; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.utilisateur_theme
    ADD CONSTRAINT fk_ut_utilisateur FOREIGN KEY (id_personne) REFERENCES conferences.utilisateur(id_personne) ON DELETE CASCADE;


--
-- Name: utilisateur fk_utilisateur_personne; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.utilisateur
    ADD CONSTRAINT fk_utilisateur_personne FOREIGN KEY (id_personne) REFERENCES conferences.personne(id_personne) ON DELETE CASCADE;


--
-- Name: ville fk_ville_pays; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.ville
    ADD CONSTRAINT fk_ville_pays FOREIGN KEY (id_pays) REFERENCES conferences.pays(id_pays) ON DELETE RESTRICT;


--
-- Name: workshop fk_workshop_conf; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.workshop
    ADD CONSTRAINT fk_workshop_conf FOREIGN KEY (id_conf) REFERENCES conferences.conference(id_conf) ON DELETE CASCADE;


--
-- Name: workshop fk_workshop_mere; Type: FK CONSTRAINT; Schema: conferences; Owner: -
--

ALTER TABLE ONLY conferences.workshop
    ADD CONSTRAINT fk_workshop_mere FOREIGN KEY (id_conf_mere) REFERENCES conferences.conference(id_conf) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict TjpiTHYxsoBows22xMMtN2cSak6Yz5FQoDRLhUmqbQpG0bTiwyLCxh7H2rl6Ya4

