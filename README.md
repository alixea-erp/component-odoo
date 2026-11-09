<img alt="icon" src=".alixea/icon.svg" width="32">

# Odoo component for Alixea

Uses the official [odoo](https://hub.docker.com/_/odoo) Docker image (Odoo 18).

Requires **PostgreSQL**, which is included as an add-on (`alixea-erp/addon-postgres`).

## Operation

### Login

Log in to Odoo with user `admin`. An initial password is generated for every project (`INITIAL_ADMIN_PASSWORD`). Find it in the deployment's **Options** tab.

The same value is also used as Odoo's master password (`admin_passwd`) for the database manager.

### Initialization

On first start, an init container running the Odoo image:

1. Waits for PostgreSQL, then creates the Odoo database role and database if they do not exist.
2. Writes a default `odoo.conf` into persistent storage if one is not already present.
3. Initializes the Odoo database (`odoo --init=base --stop-after-init`) if it has not been initialized yet.
4. Sets the `admin` user password to `INITIAL_ADMIN_PASSWORD`.

Initialization is recorded in a `diploi_parameters` table, so later restarts skip the first-time setup.

The init script lives in the component helm files (`.alixea/helm/app-init-configmap.yaml`), so it is updated with the component rather than being frozen in the user project.

### Storage

| Path                | Volume              | Description                                                                                             |
| ------------------- | ------------------- | ------------------------------------------------------------------------------------------------------- |
| `/var/lib/odoo`     | `data`              | Odoo filestore and sessions. Persisted in all stages.                                                   |
| `/etc/odoo`         | `data` (`etc-odoo`) | Persistent `odoo.conf`. Mounted from the data volume so config survives pod restarts and image updates. |
| `/mnt/extra-addons` | `code`              | Custom Odoo modules. The component folder of the project repository.                                    |
| `/home/odoo`        | `home`              | Home directory for the `odoo` user.                                                                     |

The default config sets `addons_path = /mnt/extra-addons`, `data_dir = /var/lib/odoo`, `proxy_mode = True`, and the PostgreSQL connection settings.

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

- [Odoo documentation](https://www.odoo.com/documentation/18.0/)
