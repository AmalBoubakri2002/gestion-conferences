#!/bin/bash
# =====================================================================
#  MOD 11.1 - Projet 4 : restaure la base gestion_conferences à partir
#  du dump (structure + données), sans relancer le notebook.
#  Usage (depuis le dossier projet4) :  ./restore_dump.sh
#  ATTENTION : supprime puis recrée la base.
#              Arrêter l'application Flask avant (Ctrl + C).
# =====================================================================
set -e                                    # s'arrête à la première erreur
cd "$(dirname "$0")"                      # se place dans le dossier du projet
DB=${1:-gestion_conferences}              # nom de la base (facultatif)
DUMP=dump/gestion_conferences.sql

# Vérifier le dump AVANT de supprimer quoi que ce soit
if [ ! -f "$DUMP" ]; then
    echo "Erreur : fichier $DUMP introuvable." >&2
    exit 1
fi

echo ">>> Suppression puis création de la base $DB"
dropdb --if-exists "$DB"
createdb "$DB"

# L'extension pg_trgm (index de recherche par mot-clé) n'est pas dans le dump
psql -d "$DB" -q -c "CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA public;"

echo ">>> Restauration de $DUMP"
psql -d "$DB" -q -v ON_ERROR_STOP=1 -f "$DUMP" > /dev/null

# Les tables du schéma "conferences" sont accessibles sans préfixe
psql -d "$DB" -q -c "ALTER DATABASE $DB SET search_path TO conferences, public;"

# Vérification rapide
psql -d "$DB" -At -c "SELECT '>>> Base $DB restaurée : '
                            || (SELECT count(*) FROM conferences.conference) || ' conférences, '
                            || (SELECT count(*) FROM conferences.utilisateur) || ' utilisateurs.'"
