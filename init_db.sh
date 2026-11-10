#!/bin/bash
# =====================================================================
#  MOD 11.1 - Projet 4 : (ré)initialise la base gestion_conferences
#  Usage (depuis le dossier projet4) :  ./init_db.sh
#  ATTENTION : supprime et recrée tout le schéma "conferences".
# =====================================================================
set -e                                    # s'arrête à la première erreur
DB=gestion_conferences

# Crée la base si elle n'existe pas encore
psql -lqt | cut -d '|' -f 1 | grep -qw "$DB" || createdb "$DB"

for f in sql/01_create_tables.sql sql/02_triggers.sql sql/03_index.sql sql/04_vues.sql; do
    echo ">>> Exécution de $f"
    psql -d "$DB" -q -v ON_ERROR_STOP=1 -f "$f"
done

# Les tables du schéma "conferences" sont accessibles sans préfixe
psql -d "$DB" -q -c "ALTER DATABASE $DB SET search_path TO conferences, public;"

echo ">>> Base $DB initialisée : 19 tables, 5 triggers, 18 index, 8 vues."