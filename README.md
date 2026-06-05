# MsgSrv

> **Outil de messagerie d'urgence sur réseau local** — diffusion de messages ciblés aux postes Windows via un simple partage SMB, sans infrastructure serveur dédiée.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![AutoIt](https://img.shields.io/badge/AutoIt-v3-brightgreen)](https://www.autoitscript.com/)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078d4)](https://www.microsoft.com/)

---

## Présentation

MsgSrv permet à un administrateur ou à un service communication d'envoyer des messages d'alerte, d'information ou d'urgence à l'ensemble des postes d'un réseau local, ou à un sous-ensemble ciblé par service Active Directory.

L'architecture est volontairement simple : le composant serveur écrit un fichier texte sur un partage réseau SMB ; l'agent client le lit périodiquement et affiche une fenêtre de notification si le contenu a changé. **Aucun serveur web, aucune base de données, aucun port ouvert.**

---

## Contenu du dépôt

```
MsgSrv/
├── src/
│   ├── Srv/
│   │   ├── adminmsgAH.au3   ← Source AutoIt de l'interface admin
│   │   ├── admin.ico
│   │   ├── config.ini       ← Modèle de configuration (AD, paramètres)
│   │   ├── users.ini        ← Modèle des comptes (auto-créé au 1er lancement)
│   │   ├── types.ini        ← Définition des types de messages et couleurs
│   │   ├── services.txt     ← Cache des départements AD
│   │   ├── message.txt      ← Modèle de message
│   │   ├── log.txt          ← Journal horodaté (vide à l'init)
│   │   └── img/             ← Images jointes aux messages
│   └── Client/
│       ├── msgAH.au3        ← Source AutoIt de l'agent client
│       ├── icon.ico
│       └── path.ini         ← Modèle de configuration des chemins
│
├── release/
│   ├── MsgSrv-Srv.zip       ← Package serveur prêt à déployer (avec .exe)
│   └── MsgSrv-Client.zip    ← Package client prêt à déployer (avec .exe)
│
├── LICENSE
└── README.md                ← Ce fichier
```

---

## Fonctionnalités

- **3 niveaux de sévérité** : Information, Alerte, Urgence — couleurs et libellés configurables via `types.ini`
- **Ciblage par service AD** — diffusion à tous ou à des départements spécifiques (intégration ADODB/ADSI native, aucune dépendance externe)
- **Gestion multi-utilisateurs avec rôles** — `admin` (accès complet) et `communication` (envoi uniquement)
- **Pièce jointe image** — une image peut accompagner chaque message
- **Mode silencieux** — désactive l'affichage des popups sans arrêter les agents
- **Journal horodaté** — chaque envoi est tracé dans `log.txt`
- **Rétrocompatibilité v1** — les messages sans balise `[services]` sont diffusés à tous

---

## Déploiement rapide

### Prérequis

- Windows 7 / Server 2008 R2 ou supérieur
- Un partage réseau SMB accessible en **lecture** par tous les postes, en **écriture** par les utilisateurs admin/communication
- [AutoIt v3](https://www.autoitscript.com/site/autoit/downloads/) uniquement si vous souhaitez recompiler les sources

### 1. Côté serveur

1. Extraire `release/MsgSrv-Srv.zip` dans un dossier partagé (ex : `\\SRV\MsgSrv\Srv\`).
2. Adapter `config.ini` avec les paramètres de votre domaine Active Directory :
   ```ini
   [ActiveDirectory]
   Server=dc.domaine.local
   BaseDN=OU=Entreprise,DC=domaine,DC=local
   ```
3. Lancer `adminmsgAH.exe` — le fichier `users.ini` est créé avec le compte par défaut **`admin` / `admin`**.
4. **Changer ce mot de passe immédiatement** depuis l'onglet *Utilisateurs*.

### 2. Côté client

1. Extraire `release/MsgSrv-Client.zip` sur chaque poste (ou déployer via GPO/SCCM).
2. Adapter `path.ini` avec les chemins UNC vers le partage :
   ```ini
   [Chemins]
   Message=\\SRV\MsgSrv\Srv\message.txt
   Config=\\SRV\MsgSrv\Srv\config.ini
   Types=\\SRV\MsgSrv\Srv\types.ini
   Intervalle=6000
   ```
3. Ajouter `msgAH.exe` au démarrage via GPO ou tâche planifiée.
4. *(Optionnel)* Si l'AD est inaccessible depuis certains postes, créer un `service.ini` local :
   ```ini
   [User]
   Service=NomDuService
   ```

---

## Compiler les sources

Les fichiers `.au3` dans `src/` sont des scripts [AutoIt v3](https://www.autoitscript.com/). Pour recompiler :

1. Installer AutoIt v3.
2. Clic droit sur le fichier `.au3` → *Compile Script*.
3. L'option **"Require admin"** doit être **décochée**.

---

## Rôles utilisateurs

| Rôle | Composer | Mode silencieux | Gestion utilisateurs | Historique |
|------|:--------:|:---------------:|:--------------------:|:----------:|
| `admin` | ✔ | ✔ | ✔ | ✔ |
| `communication` | ✔ | ✗ | ✗ | ✔ |

---

## Sécurité

- Les mots de passe sont stockés en **SHA-256** via `_Crypt_HashData` (bibliothèque AutoIt intégrée).
- La surface d'attaque se limite aux **ACL du partage SMB** — configurez-les correctement.
- Pour un environnement très sensible, envisager une vérification via l'API Windows `LogonUser` ou un challenge LDAP.

---

## Licence

Ce projet est distribué sous licence **GNU Affero General Public License v3.0 (AGPL-3.0)**. Voir le fichier [LICENSE](LICENSE) pour le texte complet.
