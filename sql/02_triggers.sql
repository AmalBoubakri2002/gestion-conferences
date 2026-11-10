-- =====================================================================
--  MOD 11.1 - Projet 4 : Gestion des conférences
--  Fichier 02_triggers.sql : fonctions et triggers
--  But : imposer les contraintes d'intégrité qui portent sur PLUSIEURS
--        tables et ne peuvent donc pas s'écrire avec un simple CHECK.
--  Prérequis : 01_create_tables.sql exécuté.
-- =====================================================================

SET search_path TO conferences;

-- =====================================================================
-- CI-1 : Un évaluateur de session doit être membre du comité de
--        programme (PC) de la conférence à laquelle appartient la session.
-- =====================================================================

-- 1.a  Contrôle à l'insertion / modification dans EVALUE
CREATE OR REPLACE FUNCTION fn_check_evaluateur_membre_pc()
RETURNS TRIGGER
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

CREATE TRIGGER trg_evalue_membre_pc
BEFORE INSERT OR UPDATE ON evalue
FOR EACH ROW
EXECUTE FUNCTION fn_check_evaluateur_membre_pc();

-- 1.b  Empêcher de retirer du PC une personne qui évalue encore une session
--      de cette conférence (sinon CI-1 serait violée après coup).
CREATE OR REPLACE FUNCTION fn_check_retrait_membre_pc()
RETURNS TRIGGER
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

CREATE TRIGGER trg_membre_pc_retrait
BEFORE DELETE OR UPDATE ON membre_pc
FOR EACH ROW
EXECUTE FUNCTION fn_check_retrait_membre_pc();


-- =====================================================================
-- CI-2 : Cohérence des workshops
--   a) la conférence mère n'est pas elle-même un workshop ;
--   b) une conférence qui a déjà des workshops ne peut pas devenir workshop ;
--   c) le workshop a lieu "juste avant ou juste après" la conférence mère :
--      on tolère un écart de 7 jours au maximum.
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_check_workshop()
RETURNS TRIGGER
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

CREATE TRIGGER trg_workshop_coherence
BEFORE INSERT OR UPDATE ON workshop
FOR EACH ROW
EXECUTE FUNCTION fn_check_workshop();


-- =====================================================================
-- CI-3 : Les échéances d'une spécification de soumission précèdent la
--        conférence : la version corrigée doit être envoyée avant le
--        premier jour de la conférence.
--        (L'ordre soumission < notification < version finale est déjà
--         garanti par le CHECK ck_spec_dates.)
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_check_specification_dates()
RETURNS TRIGGER
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

CREATE TRIGGER trg_specification_dates
BEFORE INSERT OR UPDATE ON specification
FOR EACH ROW
EXECUTE FUNCTION fn_check_specification_dates();


-- =====================================================================
-- CI-4 : La hiérarchie des thèmes ne contient pas de cycle
--        (ex : A sous-thème de B et B sous-thème de A).
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_check_theme_cycle()
RETURNS TRIGGER
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

CREATE TRIGGER trg_theme_cycle
BEFORE INSERT OR UPDATE OF id_theme_parent ON theme
FOR EACH ROW
EXECUTE FUNCTION fn_check_theme_cycle();


-- =====================================================================
-- Fonction utilitaire (sera utilisée par la requête 3) :
-- renvoie un thème et TOUS ses sous-thèmes (descendants), à partir
-- d'un mot-clé. Ex : fn_themes_descendants('spatial') renvoie
-- "Spatial databases", "GIS", "R-tree", "Spatial indexing"...
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_themes_descendants(p_mot_cle TEXT)
RETURNS TABLE (id_theme INTEGER, libelle VARCHAR)
LANGUAGE sql
STABLE
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