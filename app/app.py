"""
MOD 11.1 - Projet 4 : Gestion des conférences
Interface web : Flask + SQLAlchemy (ORM)

Lancement (depuis le dossier projet4/app) :
    python app.py        puis ouvrir http://127.0.0.1:5000

Deux profils :
  - utilisateur : consulter les conférences, gérer ses thèmes d'intérêt, lancer les 9 requêtes
  - admin       : en plus, créer / modifier / supprimer des conférences (CRUD)
"""
import os
from functools import wraps

from flask import Flask, render_template, request, redirect, url_for, session, flash
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from werkzeug.security import check_password_hash

# ---------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------
app = Flask(__name__)
app.config['SECRET_KEY'] = 'mod-11-1-projet-4'          # signe le cookie de session
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get(
    'DATABASE_URL', 'postgresql+psycopg2:///gestion_conferences')
# toutes les tables sont dans le schéma "conferences"
app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {
    'connect_args': {'options': '-csearch_path=conferences,public'}}
db = SQLAlchemy(app)


# ---------------------------------------------------------------------
# Modèles ORM : une classe Python = une table
# (seulement les tables manipulées par l'application)
# ---------------------------------------------------------------------
utilisateur_theme = db.Table(
    'utilisateur_theme',
    db.Column('id_personne', db.Integer, db.ForeignKey('utilisateur.id_personne'), primary_key=True),
    db.Column('id_theme', db.Integer, db.ForeignKey('theme.id_theme'), primary_key=True))


class Ville(db.Model):
    __tablename__ = 'ville'
    id_ville = db.Column(db.Integer, primary_key=True)
    nom_ville = db.Column(db.String)


class Organisme(db.Model):
    __tablename__ = 'organisme'
    id_organisme = db.Column(db.Integer, primary_key=True)
    nom = db.Column(db.String)


class Serie(db.Model):
    __tablename__ = 'serie'
    id_serie = db.Column(db.Integer, primary_key=True)
    sigle = db.Column(db.String)


class Editeur(db.Model):
    __tablename__ = 'editeur'
    id_editeur = db.Column(db.Integer, primary_key=True)
    nom_editeur = db.Column(db.String)


class Theme(db.Model):
    __tablename__ = 'theme'
    id_theme = db.Column(db.Integer, primary_key=True)
    libelle = db.Column(db.String)
    id_theme_parent = db.Column(db.Integer, db.ForeignKey('theme.id_theme'))


class Conference(db.Model):
    __tablename__ = 'conference'
    id_conf = db.Column(db.Integer, primary_key=True)
    intitule = db.Column(db.String, nullable=False)
    date_debut = db.Column(db.Date, nullable=False)
    date_fin = db.Column(db.Date, nullable=False)
    texte_introductif = db.Column(db.Text, nullable=False)
    id_ville = db.Column(db.Integer, db.ForeignKey('ville.id_ville'), nullable=False)
    id_organisme = db.Column(db.Integer, db.ForeignKey('organisme.id_organisme'), nullable=False)
    id_serie = db.Column(db.Integer, db.ForeignKey('serie.id_serie'))
    id_editeur = db.Column(db.Integer, db.ForeignKey('editeur.id_editeur'))


class Personne(db.Model):
    __tablename__ = 'personne'
    id_personne = db.Column(db.Integer, primary_key=True)
    nom = db.Column(db.String)
    prenom = db.Column(db.String)
    email = db.Column(db.String)


class Utilisateur(db.Model):
    __tablename__ = 'utilisateur'
    id_personne = db.Column(db.Integer, db.ForeignKey('personne.id_personne'), primary_key=True)
    login = db.Column(db.String, unique=True)
    mot_de_passe = db.Column(db.String)
    role = db.Column(db.String)
    personne = db.relationship('Personne')                    # héritage : l'utilisateur EST une personne
    themes = db.relationship('Theme', secondary=utilisateur_theme)  # son profil (N-N)


# ---------------------------------------------------------------------
# Gestion des droits d'accès
# ---------------------------------------------------------------------
def connexion_requise(vue):
    @wraps(vue)
    def wrapper(*args, **kwargs):
        if 'id_personne' not in session:
            return redirect(url_for('login'))
        return vue(*args, **kwargs)
    return wrapper


def admin_requis(vue):
    @wraps(vue)
    def wrapper(*args, **kwargs):
        if session.get('role') != 'admin':
            flash("Accès réservé à l'administrateur.", 'danger')
            return redirect(url_for('conferences'))
        return vue(*args, **kwargs)
    return connexion_requise(wrapper)


def sql(requete, **params):
    """Exécute une requête SQL paramétrée (protégée contre l'injection SQL)."""
    return db.session.execute(text(requete), params).mappings().all()


# ---------------------------------------------------------------------
# Connexion / déconnexion
# ---------------------------------------------------------------------
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        u = Utilisateur.query.filter_by(login=request.form['login']).first()
        if u and check_password_hash(u.mot_de_passe, request.form['mot_de_passe']):
            session.update(id_personne=u.id_personne, login=u.login, role=u.role)
            return redirect(url_for('conferences'))
        flash('Login ou mot de passe incorrect.', 'danger')
    return render_template('login.html')


@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))


# ---------------------------------------------------------------------
# READ : liste et détail des conférences
# ---------------------------------------------------------------------
@app.route('/')
@connexion_requise
def conferences():
    recherche = request.args.get('q', '')
    lignes = sql("""
        SELECT * FROM v_conference_complete
        WHERE intitule ILIKE :motif
        ORDER BY date_debut DESC""", motif=f'%{recherche}%')
    return render_template('conferences.html', conferences=lignes, q=recherche)


@app.route('/conference/<int:id_conf>')
@connexion_requise
def conference(id_conf):
    infos = sql("SELECT * FROM v_conference_complete WHERE id_conf = :id", id=id_conf)
    if not infos:
        flash('Conférence introuvable.', 'danger')
        return redirect(url_for('conferences'))
    return render_template(
        'conference.html', c=infos[0],
        sessions=sql("""
            SELECT s.num_session, s.intitule_session, STRING_AGG(t.libelle, ', ') AS themes
            FROM session s
            LEFT JOIN session_theme st USING (id_conf, num_session)
            LEFT JOIN theme t USING (id_theme)
            WHERE s.id_conf = :id
            GROUP BY s.num_session, s.intitule_session ORDER BY s.num_session""", id=id_conf),
        responsables=sql("""
            SELECT prenom, nom, STRING_AGG(role, ', ') AS roles
            FROM v_personnes_responsables WHERE id_conf = :id
            GROUP BY prenom, nom ORDER BY nom""", id=id_conf),
        specifications=sql("SELECT * FROM v_specifications WHERE id_conf = :id ORDER BY categorie", id=id_conf),
        workshops=sql("SELECT * FROM v_workshops WHERE id_conf_mere = :id", id=id_conf))


# ---------------------------------------------------------------------
# CREATE / UPDATE / DELETE : conférences (administrateur, via l'ORM)
# ---------------------------------------------------------------------
def listes_formulaire():
    return dict(villes=Ville.query.order_by(Ville.nom_ville).all(),
                organismes=Organisme.query.order_by(Organisme.nom).all(),
                series=Serie.query.order_by(Serie.sigle).all(),
                editeurs=Editeur.query.order_by(Editeur.nom_editeur).all())


def remplir(conf, form):
    conf.intitule = form['intitule']
    conf.date_debut = form['date_debut']
    conf.date_fin = form['date_fin']
    conf.texte_introductif = form['texte_introductif']
    conf.id_ville = int(form['id_ville'])
    conf.id_organisme = int(form['id_organisme'])
    conf.id_serie = int(form['id_serie']) if form['id_serie'] else None
    conf.id_editeur = int(form['id_editeur']) if form['id_editeur'] else None


def enregistrer(message):
    """COMMIT ; si la base refuse (CHECK, FK, trigger), on affiche son message."""
    try:
        db.session.commit()
        flash(message, 'success')
        return True
    except DBAPIError as e:
        db.session.rollback()
        flash('Refusé par la base : ' + str(e.orig).split('\n')[0], 'danger')
        return False


@app.route('/admin/conference/nouvelle', methods=['GET', 'POST'])
@admin_requis
def conference_creer():
    conf = Conference()
    if request.method == 'POST':
        remplir(conf, request.form)
        db.session.add(conf)                                   # INSERT
        if enregistrer('Conférence créée.'):
            return redirect(url_for('conference', id_conf=conf.id_conf))
    return render_template('conference_form.html', conf=conf, **listes_formulaire())


@app.route('/admin/conference/<int:id_conf>/modifier', methods=['GET', 'POST'])
@admin_requis
def conference_modifier(id_conf):
    conf = db.get_or_404(Conference, id_conf)
    if request.method == 'POST':
        remplir(conf, request.form)                            # UPDATE
        if enregistrer('Conférence modifiée.'):
            return redirect(url_for('conference', id_conf=id_conf))
    return render_template('conference_form.html', conf=conf, **listes_formulaire())


@app.route('/admin/conference/<int:id_conf>/supprimer', methods=['POST'])
@admin_requis
def conference_supprimer(id_conf):
    db.session.delete(db.get_or_404(Conference, id_conf))     # DELETE (sessions... en CASCADE)
    enregistrer('Conférence supprimée.')
    return redirect(url_for('conferences'))


# ---------------------------------------------------------------------
# Profil de l'utilisateur : ses thèmes d'intérêt + requête 4
# ---------------------------------------------------------------------
@app.route('/profil', methods=['GET', 'POST'])
@connexion_requise
def profil():
    moi = db.session.get(Utilisateur, session['id_personne'])
    if request.method == 'POST':
        ids = [int(i) for i in request.form.getlist('themes')]
        moi.themes = Theme.query.filter(Theme.id_theme.in_(ids)).all()   # l'ORM gère la table N-N
        enregistrer('Profil mis à jour.')
        return redirect(url_for('profil'))
    return render_template(
        'profil.html', moi=moi,
        themes=Theme.query.order_by(Theme.libelle).all(),
        mes_ids={t.id_theme for t in moi.themes},
        conferences=sql(REQUETES[4]['sql'], login=moi.login))


# ---------------------------------------------------------------------
# Les 9 requêtes du sujet
# ---------------------------------------------------------------------
REQUETES = {
    1: dict(titre="Conférences de l'année courante", params={}, sql="""
        SELECT id_conf, intitule, date_debut, nom_ville, nom_pays,
               CASE WHEN est_workshop THEN 'Workshop' ELSE 'Conférence' END AS type
        FROM v_conference_complete
        WHERE date_debut >= date_trunc('year', CURRENT_DATE)
          AND date_debut <  date_trunc('year', CURRENT_DATE) + INTERVAL '1 year'
        ORDER BY date_debut"""),
    2: dict(titre="Pays et conférences qui y ont été organisées", params={}, sql="""
        SELECT p.nom_pays, COUNT(c.id_conf) AS nb,
               STRING_AGG(c.intitule, ' ; ' ORDER BY c.date_debut) AS conferences
        FROM pays p
        LEFT JOIN ville v ON v.id_pays = p.id_pays
        LEFT JOIN conference c ON c.id_ville = v.id_ville
             AND NOT EXISTS (SELECT 1 FROM workshop w WHERE w.id_conf = c.id_conf)
        GROUP BY p.nom_pays ORDER BY nb DESC"""),
    3: dict(titre="Conférences sur un domaine (thème et sous-thèmes)",
            params={'mot_cle': 'spatial'}, sql="""
        SELECT id_conf, intitule, date_debut, STRING_AGG(DISTINCT theme, ', ') AS themes
        FROM v_conference_themes
        WHERE id_theme IN (SELECT id_theme FROM fn_themes_descendants(:mot_cle))
        GROUP BY id_conf, intitule, date_debut ORDER BY date_debut DESC"""),
    4: dict(titre="Conférences qui intéressent un utilisateur",
            params={'login': 'alice'}, sql="""
        SELECT id_conf, intitule, date_debut,
               CASE WHEN date_debut >= CURRENT_DATE THEN 'à venir' ELSE 'passée' END AS statut,
               STRING_AGG(DISTINCT theme_conference, ', ') AS themes
        FROM v_utilisateur_conferences WHERE login = :login
        GROUP BY id_conf, intitule, date_debut ORDER BY date_debut DESC"""),
    5: dict(titre="Conférences d'une série", params={'sigle': 'SDH'}, sql="""
        SELECT id_conf, intitule, date_debut, nom_ville, nom_pays, nom_editeur
        FROM v_conference_complete WHERE serie_sigle = :sigle ORDER BY date_debut"""),
    6: dict(titre="Workshops d'une conférence (n°)", params={'id_conf': '1'}, sql="""
        SELECT id_workshop AS id_conf, workshop, workshop_debut, conference_mere
        FROM v_workshops WHERE id_conf_mere = CAST(:id_conf AS INTEGER) ORDER BY workshop_debut"""),
    7: dict(titre="Conférences publiées par un éditeur", params={'editeur': 'Springer'}, sql="""
        SELECT id_conf, intitule, date_debut, serie_sigle
        FROM v_conference_complete WHERE nom_editeur = :editeur ORDER BY date_debut DESC"""),
    8: dict(titre="Utilisateurs qui ont aussi été responsables", params={}, sql="""
        SELECT login, prenom || ' ' || nom AS utilisateur, nb_conferences, roles
        FROM v_utilisateurs_responsables ORDER BY nb_conferences DESC"""),
    9: dict(titre="Conférences dont une personne a été responsable",
            params={'nom': 'Dupont', 'prenom': 'Jean'}, sql="""
        SELECT pr.id_conf, pr.intitule, pr.date_debut, STRING_AGG(pr.role, ', ') AS roles
        FROM v_personnes_responsables pr JOIN personne pe USING (id_personne)
        WHERE lower(pe.nom) = lower(:nom) AND lower(pe.prenom) = lower(:prenom)
        GROUP BY pr.id_conf, pr.intitule, pr.date_debut ORDER BY pr.date_debut DESC"""),
}


@app.route('/requetes')
@app.route('/requetes/<int:num>')
@connexion_requise
def requetes(num=1):
    req = REQUETES.get(num) or REQUETES[1]
    valeurs = {p: request.args.get(p, defaut) for p, defaut in req['params'].items()}
    try:
        resultat = sql(req['sql'], **valeurs)
    except DBAPIError as e:
        db.session.rollback()
        flash('Erreur : ' + str(e.orig).split('\n')[0], 'danger')
        resultat = []
    return render_template('requetes.html', requetes=REQUETES, num=num, req=req,
                           valeurs=valeurs, resultat=resultat)


if __name__ == '__main__':
    app.run(debug=True)
