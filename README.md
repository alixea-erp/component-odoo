<img alt="icon" src=".alixea/icon.svg" width="32">

# Odoo component for Alixea

Uses the official [odoo](https://hub.docker.com/_/odoo) Docker image. The component version is the Odoo series: `18.0`, `19.0` or `20.0`.

Requires **PostgreSQL**, which is included as an add-on (`alixea-erp/addon-postgres`).

## Operation

### Login

Log in to Odoo with user `admin`. An initial password is generated for every project (`INITIAL_ADMIN_PASSWORD`). Find it in the deployment's **Options** tab.

The same value is also used as Odoo's master password (`admin_passwd`) for the database manager.

### Initialization

Before Odoo starts, an init container runs `/init.sh` of the image. On the first start it:

1. Waits for PostgreSQL, then creates the Odoo database role.
2. Writes a default `odoo.conf` into persistent storage if one is not already present.
3. Creates the Odoo database (`odoo --init=base`), sets the `admin` password to `INITIAL_ADMIN_PASSWORD` and installs
   the checked module sets.
4. Copies the code it runs to the deployment's disk (`/var/lib/odoo/code/<id>`), beside the database creation.

The database records which version of the code it was made or upgraded for (`diploi_parameters`, key `code`). The
script is in the image and not in the chart, so a fix to it reaches every deployment with the next image.

### Module sets and updates

The **Modules** settings hold the module sets (Alixea modules, Alixea Finance, Odoo Enterprise, OCA) and one switch,
**Update automatically**. Each set is a private repository whose tags the platform fetches and mounts at
`/mnt/addons/<set>`.

- With the switch on, the deployment moves to the latest released version of the sets and of the Odoo image at
  night. With it off, it stays on what it has. Switching it on updates with that save.
- An update restarts Odoo. The init container clones the database, upgrades the modules whose files changed
  (`click-odoo-update`) and records the new version. Versions only move forward.
- A major upgrade (`18.0` to `19.0`) is not automatic.

### When an update fails

The database is put back as it was before the update, and Odoo starts on the previous versions, from the copy of the
old code on the disk. The deployment shows red with a notice naming the module that failed, for example
`Automatic update failed: module sale_custom. Odoo runs the previous versions.`

- Usually a module of your own, or a customised view, no longer fits the new code. Fix it and restart Odoo, or wait:
  a new version the next night is a new attempt. A restart with nothing changed does not try again.
- The half-upgraded database is kept as `<database>__alixea_failed` for looking into the failure, until an update
  works.
- For a problem found days later, restore a restore point from before the update. It brings the old versions back.

The init script never drops the database Odoo uses, it only renames it. It drops only databases it made itself:
`<database>__alixea_before`, `__alixea_new` and `__alixea_failed`, and only when they carry its own comment. A
database you create yourself is not touched, whatever its name. A database you restore under the live name is
upgraded to the image's code at the next start; when that fails it is put back and Odoo does not start, as there is
no older code to run it with.

### Storage

| Path                | Volume              | Description                                                                                             |
| ------------------- | ------------------- | ------------------------------------------------------------------------------------------------------- |
| `/var/lib/odoo`     | `data`              | Odoo filestore and sessions, and `code/`: the copy of the running code. Persisted in all stages.        |
| `/etc/odoo`         | `data` (`etc-odoo`) | Persistent `odoo.conf`. Mounted from the data volume so config survives pod restarts and image updates. |
| `/mnt/extra-addons` | `code`              | Custom Odoo modules. The component folder of the project repository.                                    |
| `/mnt/addons/<set>` | (the VM)            | The checked module sets, read-only.                                                                     |
| `/home/odoo`        | `home`              | Home directory for the `odoo` user.                                                                     |

The default config sets `data_dir = /var/lib/odoo`, `proxy_mode = True` and the PostgreSQL connection settings. `addons_path` is written by the init container at every start: `/mnt/extra-addons` and the module sets.

Odoo's own code is in `/opt/odoo` in the image, not on Python's default path. `PYTHONPATH` points at `/var/lib/odoo/code/current`, a link to `/opt/odoo` or, after a failed update, to the copy of the old code.

### Environment variables

| Variable                 | Description                                                                     |
| ------------------------ | ------------------------------------------------------------------------------- |
| `INITIAL_ADMIN_PASSWORD` | Initial `admin` login password and Odoo master password. Generated per project. |
| `DATABASE`               | PostgreSQL database name. Default `odoo`.                                       |
| `USER`                   | PostgreSQL role used by Odoo. Default `odoo`.                                   |
| `PASSWORD`               | Password for the Odoo PostgreSQL role. Generated per project.                   |

PostgreSQL connection details (`HOST`, `PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`) come from the PostgreSQL add-on.

### Development

The development container runs as user `odoo` (`1000:1000`). Custom modules can be added under `/mnt/extra-addons`.

The start command can be changed with the `containerCommands.developmentStart` field in `alixea.yaml`.

### Production

Builds a production-ready image from the official Odoo image. When the container starts, it uses the persistent `odoo.conf` created during initialization.

The start command can be changed with the `containerCommands.productionStart` field in `alixea.yaml`.

## Links

- [Odoo documentation](https://www.odoo.com/documentation/19.0/)
