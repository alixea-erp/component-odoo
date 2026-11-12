<img alt="icon" src=".alixea/icon.svg" width="32">

# Odoo component for Alixea

Runs the official [odoo](https://hub.docker.com/_/odoo) Docker image. The component version is the Odoo series:
`18.0`, `19.0` or `20.0`.

It needs PostgreSQL, which comes as an add-on (`alixea-erp/addon-postgres`).

## Login

Log in as `admin`. The password is `INITIAL_ADMIN_PASSWORD`, shown in the deployment's **Options** tab. It is also
Odoo's master password for the database manager.

## First start

An init container runs `/init.sh` from the image before Odoo starts. On the first start it:

1. Creates the Odoo database role.
2. Writes a default `odoo.conf` to the disk.
3. Creates the database, sets the `admin` password and installs the checked module sets.
4. Copies the running code to the disk. A failed update goes back to this copy.

## Module sets and updates

The **Modules** settings list the module sets: Alixea modules, Alixea Finance, Odoo Enterprise and OCA. Each set is
a private repository. The platform fetches the chosen tag and mounts it at `/mnt/addons/<set>`.

**Update automatically** decides how the deployment follows new versions:

- **On:** every night it moves to the latest module sets and the latest Odoo image.
- **Off:** it stays on what it has.
- **Switched on:** it updates with that save.

An update restarts Odoo. The init container copies the database, upgrades the modules whose files changed and
records the new version. Versions only move forward. A major upgrade such as `18.0` to `19.0` is not automatic.

## When an update fails

The database is put back as it was, and Odoo starts on the previous versions. The deployment turns red with a notice
that names the module:

`Automatic update failed: module sale_custom. Odoo runs the previous versions.`

What to do:

- Fix the module or view that no longer fits the new code, then restart Odoo.
- Or wait. A new version the next night is a new attempt. A restart with nothing changed is not.
- If the notice says the new code could not be copied, the disk is probably full. Free some space or resize the
  disk, then restart Odoo. That restart tries the update again.
- For a problem found days later, restore a restore point from before the update.

The half-upgraded database is kept as `<database>__alixea_failed` until an update works.

The init script never drops the database Odoo uses. It only drops databases it made itself, named
`<database>__alixea_before`, `__alixea_new` or `__alixea_failed`. A database you create is never touched.

A database you restore yourself is upgraded at the next start. If that upgrade fails, Odoo does not start, because
there is no older code to go back to.

## Storage

| Path                | Volume | What it holds                                         |
| ------------------- | ------ | ----------------------------------------------------- |
| `/var/lib/odoo`     | `data` | Filestore, sessions and the copy of the running code. |
| `/etc/odoo`         | `data` | `odoo.conf`. It survives restarts and image updates.  |
| `/mnt/extra-addons` | `code` | Your own modules: this folder of the project.         |
| `/mnt/addons/<set>` | the VM | The checked module sets, read-only.                   |
| `/home/odoo`        | `home` | Home directory of the `odoo` user.                    |

A module repository cloned into a folder of `/mnt/extra-addons`, such as an OCA repository, is found too: the init
container puts every folder that holds modules on `addons_path`, ahead of the module sets. Restart Odoo after cloning
one. Its modules win over a set's modules of the same name.

The init container writes `addons_path` in `odoo.conf` at every start. Odoo's own code is in `/opt/odoo` in the
image.

## Environment variables

| Variable                 | Description                                     |
| ------------------------ | ----------------------------------------------- |
| `INITIAL_ADMIN_PASSWORD` | Password of `admin` and Odoo's master password. |
| `DATABASE`               | Database name. Default `odoo`.                  |
| `USER`                   | PostgreSQL role Odoo uses. Default `odoo`.      |
| `PASSWORD`               | Password of that role.                          |

`HOST`, `PORT`, `POSTGRES_USER` and `POSTGRES_PASSWORD` come from the PostgreSQL add-on.

## Start commands

Odoo runs as user `odoo` (`1000:1000`). Change the start command in `alixea.yaml` with
`containerCommands.developmentStart` or `containerCommands.productionStart`.

## Links

- [Odoo documentation](https://www.odoo.com/documentation/19.0/)
