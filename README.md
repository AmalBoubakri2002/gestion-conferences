# Gestion des conférences – MOD 11.1 (Projet 4)

Projet du module **MOD 11.1 – Systèmes de gestion de bases de données** (École Centrale de Lyon).

Base de données PostgreSQL permettant à un laboratoire de gérer les appels à communication des conférences : organisateurs, séries, sessions, comités de programme, thèmes de recherche, catégories de soumission, workshops et utilisateurs. Le projet comprend une interface web (Flask) avec deux profils : **utilisateur** et **administrateur**.

---

## Sommaire

1. [Contenu du projet](#1-contenu-du-projet)
2. [Prérequis](#2-prérequis)
3. [Installation](#3-installation)
4. [Créer la base de données](#4-créer-la-base-de-données)
5. [Alimenter la base](#5-alimenter-la-base)
6. [Exécuter les 9 requêtes](#6-exécuter-les-9-requêtes)
7. [Lancer l'interface web](#7-lancer-linterface-web)
8. [Manuel d'utilisation](#8-manuel-dutilisation)
9. [Sauvegarde et restauration (dump)](#9-sauvegarde-et-restauration-dump)
10. [Tests](#10-tests)
11. [Dépannage](#11-dépannage)

---

## 1. Contenu du projet

```
projet4/
├── README.md                    ← ce fichier
├── requirements.txt             ← dépendances Python
├── init_db.sh                   ← crée (ou recrée) toute la base en une commande
│
├── sql/
│   ├── 01_create_tables.sql     ← 19 tables, clés, contraintes CHECK / UNIQUE / FK
│   ├── 02_triggers.sql          ← 5 triggers + fonctions (contraintes multi-tables)
│   ├── 03_index.sql             ← 18 index (dont 2 index GIN pg_trgm)
│   ├── 04_vues.sql              ← 8 vues
│   ├── 05_requetes.sql          ← les 9 requêtes du sujet (paramétrables)
│   └── tests/
│       ├── test_02_triggers.sql ← vérifie que les triggers refusent les données invalides
│       ├── test_03_index.sql    ← mesure le gain des index (EXPLAIN ANALYZE)
│       └── test_04_vues.sql     ← vérifie le contenu des vues
│
├── alimentation/
│   └── alimentation.ipynb       ← notebook qui remplit la base (≈ 9 000 lignes)
│
├── app/
│   ├── app.py                   ← application Flask + modèles ORM SQLAlchemy
│   └── templates/               ← pages HTML (Bootstrap)
│
├── conception/                  ← schéma Entité-Association (DB-MAIN)
├── dump/                        ← sauvegarde de la base (voir section 9)
└── rapport/                     ← rapport du projet
```

| Élément | Nombre |
|---|---|
| Tables | 19 |
| Triggers | 5 |
| Index créés | 18 (en plus des index automatiques des clés primaires et UNIQUE) |
| Vues | 8 |
| Lignes insérées par l'alimentation | environ 9 000 |

---

## 2. Prérequis

| Outil | Version testée |
|---|---|
| PostgreSQL | 16 (avec l'extension `pg_trgm`, fournie par défaut) |
| Python | 3.10 ou plus |
| Navigateur web | n'importe lequel |

### Installer PostgreSQL

**macOS** (au choix) :
- **Postgres.app** : télécharger sur <https://postgresapp.com>, glisser l'application dans *Applications*, l'ouvrir puis cliquer sur **Initialize**. Ajouter ensuite les commandes au Terminal :
  ```bash
  sudo mkdir -p /etc/paths.d && echo /Applications/Postgres.app/Contents/Versions/latest/bin | sudo tee /etc/paths.d/postgresapp
  ```
  Fermer puis rouvrir le Terminal.
- **Homebrew** :
  ```bash
  brew install postgresql@16
  brew services start postgresql@16
  ```

**Windows / Linux** : installer PostgreSQL depuis <https://www.postgresql.org/download/>.

Vérifier l'installation :
```bash
psql --version
```

---

## 3. Installation

Toutes les commandes se lancent **depuis le dossier `projet4`**.

```bash
# 1. Créer un environnement Python isolé
python3 -m venv .venv

# 2. L'activer (à refaire à chaque nouveau Terminal)
source .venv/bin/activate          # macOS / Linux
# .venv\Scripts\activate           # Windows

# 3. Installer les dépendances
pip install -r requirements.txt

# 4. Rendre le script d'initialisation exécutable (une seule fois)
chmod +x init_db.sh
```

---

## 4. Créer la base de données

```bash
./init_db.sh
```

Le script :
1. crée la base `gestion_conferences` si elle n'existe pas ;
2. exécute dans l'ordre `01_create_tables.sql`, `02_triggers.sql`, `03_index.sql` et `04_vues.sql` ;
3. règle le `search_path` pour pouvoir écrire `conference` au lieu de `conferences.conference`.

Résultat attendu :
```
>>> Exécution de sql/01_create_tables.sql
>>> Exécution de sql/02_triggers.sql
>>> Exécution de sql/03_index.sql
>>> Exécution de sql/04_vues.sql
>>> Base gestion_conferences initialisée : 19 tables, 5 triggers, 18 index, 8 vues.
```

> ⚠️ `init_db.sh` **supprime puis recrée** le schéma `conferences` : toutes les données sont effacées. Il faut ensuite relancer l'alimentation (section 5).

Les fichiers peuvent aussi être exécutés un par un :
```bash
psql -d gestion_conferences -v ON_ERROR_STOP=1 -f sql/01_create_tables.sql
```

---

## 5. Alimenter la base

```bash
jupyter notebook alimentation/alimentation.ipynb
```
Dans Jupyter : menu **Run → Run All Cells**. Avec VS Code, ouvrir le fichier, choisir le noyau `.venv`, puis **Run All**.

Le notebook :
- vide les tables puis les remplit (il peut être relancé autant de fois que nécessaire) ;
- est **reproductible** : une graine fixe (`SEED = 42`) donne toujours les mêmes données ;
- fait toutes les insertions dans **une seule transaction** : en cas d'erreur, rien n'est enregistré ;
- respecte toutes les contraintes et tous les triggers de la base.

| Table | Lignes |
|---|---|
| pays / ville / organisme | 15 / 41 / 27 |
| serie / editeur | 9 / 8 |
| theme | 43 (hiérarchie sur 3 niveaux) |
| conference (dont workshops) | 205 (dont 45) |
| personne / utilisateur | 366 / 71 |
| session / session_theme | ≈ 630 / ≈ 1 370 |
| responsable_de / membre_pc / evalue | ≈ 700 / ≈ 2 400 / ≈ 1 900 |
| specification | ≈ 640 |

La dernière section du notebook vérifie que chaque requête a des données à renvoyer.

> Si la connexion échoue, modifier `DB_PARAMS` dans la cellule 1, par exemple :
> `DB_PARAMS = dict(dbname='gestion_conferences', user='mon_login', host='localhost')`

---

## 6. Exécuter les 9 requêtes

```bash
psql -d gestion_conferences -f sql/05_requetes.sql
```

Pour enregistrer les résultats dans un fichier :
```bash
psql -d gestion_conferences -f sql/05_requetes.sql > resultats_requetes.txt
```

Les requêtes sont **paramétrables** sans modifier le fichier :
```bash
psql -d gestion_conferences -v mot_cle=temporal -v login=alice -v sigle=VLDB -f sql/05_requetes.sql
```

| # | Requête | Paramètre (défaut) | Résultat attendu* |
|---|---|---|---|
| 1 | Conférences de l'année courante | — | 48 |
| 2 | Pays et leurs conférences | — | 15 pays |
| 3 | Conférences sur les bases de données spatiales (thème + sous-thèmes) | `mot_cle` (`spatial`) | 55 |
| 4 | Conférences qui intéressent un utilisateur | `login` (`alice`) | 55 |
| 5 | Conférences de la série SDH | `sigle` (`SDH`) | 8 |
| 6 | Workshops d'une conférence | `id_conf` (`1`) | 2 |
| 7 | Conférences publiées par un éditeur | `editeur` (`Springer`) | 22 |
| 8 | Utilisateurs qui ont aussi été responsables | — | 25 |
| 9 | Conférences dont le professeur « X » a été responsable | `nom`, `prenom` (`Dupont`, `Jean`) | 14 |

\* Avec les données du notebook. Le résultat de la requête 1 dépend de l'année d'exécution.

---

## 7. Lancer l'interface web

```bash
source .venv/bin/activate      # si ce n'est pas déjà fait
cd app
python app.py
```

Ouvrir **<http://127.0.0.1:5000>** dans un navigateur.
Pour arrêter le serveur : **Ctrl + C** dans le Terminal.

Par défaut, l'application se connecte à `postgresql+psycopg2:///gestion_conferences` (base locale, utilisateur courant). Pour une autre configuration :
```bash
export DATABASE_URL="postgresql+psycopg2://utilisateur:motdepasse@localhost:5432/gestion_conferences"
python app.py
```

### Comptes de démonstration

| Login | Mot de passe | Profil |
|---|---|---|
| `admin` | `admin123` | administrateur |
| `alice` | `alice123` | utilisateur (intéressée par les bases de données spatiales) |
| autres comptes (voir la table `utilisateur`) | `user123` | utilisateur |

Les mots de passe sont stockés **hashés** dans la base, jamais en clair.

---

## 8. Manuel d'utilisation

### Droits d'accès

| Fonctionnalité | Utilisateur | Administrateur |
|---|:---:|:---:|
| Consulter et rechercher les conférences | ✅ | ✅ |
| Voir la fiche détaillée d'une conférence | ✅ | ✅ |
| Gérer ses thèmes d'intérêt | ✅ | ✅ |
| Exécuter les 9 requêtes | ✅ | ✅ |
| Créer / modifier / supprimer une conférence | ❌ | ✅ |

### Se connecter
Saisir son login et son mot de passe sur la page d'accueil. Le nom d'utilisateur et son profil s'affichent en haut à droite. Le bouton **Déconnexion** ferme la session.

### Conférences
- La page **Conférences** liste toutes les conférences, des plus récentes aux plus anciennes. Les workshops portent un badge bleu.
- Le champ **Rechercher** filtre par intitulé (par exemple `SDH` ou `2026`).
- Un clic sur un intitulé ouvre la **fiche** de la conférence :
  - dates, lieu, organisme, série, éditeur des actes ;
  - **sessions** et leurs thèmes de recherche ;
  - **appel à communication** : pour chaque catégorie, le nombre de pages maximum et les trois échéances (soumission, notification, version finale) ;
  - **responsables** et membres du comité de programme ;
  - **workshops associés**, ou un lien vers la conférence mère s'il s'agit d'un workshop.

### Mon profil
- Cocher les thèmes de recherche qui vous intéressent, puis cliquer sur **Enregistrer mes thèmes**.
- La partie droite affiche les **conférences qui vous intéressent** (requête 4). Les sous-thèmes sont pris en compte : un intérêt pour « Spatial databases » fait aussi apparaître les conférences sur « GIS », « R-tree », etc.

### Les 9 requêtes
- Choisir une requête avec les onglets **R1** à **R9**.
- Pour les requêtes paramétrées, modifier la valeur (mot-clé, login, série, éditeur…) puis cliquer sur **Exécuter**.
- Le résultat s'affiche sous forme de tableau. Les identifiants de conférence sont cliquables.
- **Voir le SQL** affiche la requête exécutée.

### Administration (profil admin uniquement)
- **+ Nouvelle conférence** (dans le menu) : remplir le formulaire puis cliquer sur **Enregistrer**. La série et l'éditeur sont facultatifs.
- **Modifier** (sur la fiche) : même formulaire, prérempli.
- **Supprimer** (sur la fiche) : après confirmation, la conférence est supprimée **avec ses sessions, spécifications, responsabilités et workshops** (suppression en cascade).
- Si une saisie viole une règle de la base, par exemple une date de fin antérieure à la date de début, l'enregistrement est **refusé** et le message de PostgreSQL s'affiche en rouge.

---

## 9. Sauvegarde et restauration (dump)

### Créer le dump
```bash
mkdir -p dump
pg_dump -d gestion_conferences -n conferences --no-owner -f dump/gestion_conferences.sql
```
Le fichier contient la structure (tables, triggers, index, vues) **et** les données.

### Restaurer la base à partir du dump
```bash
createdb gestion_conferences                       # si la base n'existe pas
psql -d gestion_conferences -c "CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA public;"
psql -d gestion_conferences -c "DROP SCHEMA IF EXISTS conferences CASCADE;"
psql -d gestion_conferences -v ON_ERROR_STOP=1 -f dump/gestion_conferences.sql
psql -d gestion_conferences -c "ALTER DATABASE gestion_conferences SET search_path TO conferences, public;"
```
La base est alors directement utilisable, sans relancer le notebook.

---

## 10. Tests

Les scripts de test **ne modifient pas les données** : ils annulent leurs changements (`ROLLBACK`) ou suppriment leurs données de test.

```bash
# Les triggers refusent les données invalides (7 ERROR attendues, toutes volontaires)
psql -d gestion_conferences -f sql/tests/test_02_triggers.sql

# Gain des index : comparer « Seq Scan » et « Index Scan » ainsi que les temps d'exécution
psql -d gestion_conferences -f sql/tests/test_03_index.sql

# Contenu des vues sur un mini jeu de données
psql -d gestion_conferences -f sql/tests/test_04_vues.sql
```

| Contrainte vérifiée par trigger | Règle |
|---|---|
| CI-1 | Un évaluateur de session est membre du comité de programme de la conférence |
| CI-2 | Un workshop n'est rattaché ni à lui-même ni à un autre workshop, et a lieu au plus 7 jours avant ou après sa conférence mère |
| CI-3 | La date limite de version finale précède le début de la conférence |
| CI-4 | La hiérarchie des thèmes ne contient pas de cycle |

---

## 11. Dépannage

| Problème | Solution |
|---|---|
| `psql: command not found` | PostgreSQL n'est pas dans le PATH : voir la section 2, puis rouvrir le Terminal. |
| `connection to server ... failed` | Le serveur PostgreSQL n'est pas démarré : ouvrir Postgres.app, ou `brew services start postgresql@16`. |
| `database "gestion_conferences" does not exist` | Lancer `./init_db.sh`. |
| `relation "conference" does not exist` | Le `search_path` n'est pas réglé : relancer `./init_db.sh`, ou préfixer par `conferences.` |
| `permission denied: ./init_db.sh` | `chmod +x init_db.sh` |
| `ModuleNotFoundError: No module named 'flask'` (ou `faker`, `psycopg2`) | Activer l'environnement : `source .venv/bin/activate`, puis `pip install -r requirements.txt`. |
| `extension "pg_trgm" is not available` | Installer les modules contrib de PostgreSQL (inclus avec Postgres.app et Homebrew). |
| Port 5000 déjà utilisé (macOS : AirPlay) | Lancer sur un autre port : `flask --app app run --port 5001`, puis ouvrir <http://127.0.0.1:5001>. |
| Plus aucune donnée après `init_db.sh` | Normal : le script recrée la base vide. Relancer le notebook (section 5) ou restaurer le dump (section 9). |

---

*Projet réalisé dans le cadre du MOD 11.1 – École Centrale de Lyon, 2026-2027.*
