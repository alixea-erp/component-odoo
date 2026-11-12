## Skills

**First find out which Odoo runs: `odoo --version` in the Odoo container** (18.0,
19.0 or 20.0, the component version of the deployment). Odoo's skills below
describe Odoo 20.0, and parts of them are wrong for 18.0 and 19.0, e.g.
`security/ir.access.csv` (18.0 and 19.0 use `ir.model.access.csv` and
`ir.rule`), the default test tags and the Owl 3 hooks (18.0 and 19.0 run Owl 2).
Read the skill of that series, `.agents/skills/odoo-18/SKILL.md`, `odoo-19` or
`odoo-20`, before using them; where they disagree, it wins. Check any API you
are unsure of against the source in the Odoo container,
`/var/lib/odoo/code/current/odoo` (the code that runs).

The skills live in `.agents/skills/`. Agents that scan that directory (Codex,
OpenCode, Cursor, Copilot) list them when started in this folder. If yours does
not list them, read the matching `SKILL.md` before changing any addon file:

| Skill                                         | Read before touching                                                                                                             |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `.agents/skills/odoo-<series>/SKILL.md`       | any addon file, together with the skill below that covers it: `odoo-18`, `odoo-19` or `odoo-20`, by `odoo --version`             |
| `.agents/skills/odoo-guidelines/SKILL.md`     | anything in an addon outside `static/`: manifest, models, fields, controllers, XML views and data, reports, access rights, tests |
| `.agents/skills/odoo-web-guidelines/SKILL.md` | anything under an addon's `static/`: JavaScript, Owl templates, SCSS                                                             |
| `.agents/skills/odoo-security/SKILL.md`       | `sudo()`, raw SQL, `eval`, controllers, public or RPC-callable methods, access rights                                            |
| `.agents/skills/odoo-review/SKILL.md`         | reviewing a diff, PR or module                                                                                                   |
| `.agents/skills/odoo-scss-check/SKILL.md`     | any `.scss` file, or a stylesheet in a manifest's `assets`                                                                       |

**After changing SCSS, run
`python3 /mnt/extra-addons/.agents/skills/odoo-scss-check/check_scss.py` in the
Odoo container** (this folder is mounted there at `/mnt/extra-addons`). Odoo
compiles SCSS with libsass, which rejects parts of modern Sass and CSS syntax;
the error shows only in the browser, and it breaks the styling of the whole
bundle. The skill lists the constructs that fail.

`odoo-18`, `odoo-19`, `odoo-20` and `odoo-scss-check` are maintained with this
component. The other four are Odoo's own, copied unchanged from `skills/` on the
`20.0` branch of Odoo's repository; never edit them, put corrections in the
skill of the series. To update them, copy the four folders again from that
branch and check each series' skill against what changed. Odoo's skills
describe addons as living in `addons/*`; in this component the addons are the
top-level directories of this folder (see below).

## Alixea

This component is built and hosted on Alixea. In a development environment, `/etc/diploi/AGENTS.md`
(also the instructions of the `diploi` MCP server) explains how the platform works. Do not
speculate about platform behavior it does not describe.

- `alixea.yaml` lists the stack and maps each component/addon to its folder. Read it before
  assuming project layout. Application code lives under `/app`.
- How a change takes effect depends on the component — for Odoo, see below.
- Env vars imported from other components are live in the container — list them with `printenv`
  instead of guessing, and never print secret values. New ones are added under **Environment** in the console.
- `diploi logs <identifier> --follow` streams logs; `diploi exec <identifier> -- <command>` runs
  a command in another component's container.

### This component

- Odoo from the official `odoo` image (`FROM` in `Dockerfile`). Serves on
  port **8069**, Odoo's default, in every stage; `hosts[].port` in `alixea.yaml` must stay 8069
  unless `http_port` is set in `odoo.conf`. Per-stage ports are not supported — the Service has
  no `targetPort`.
- **This folder is Odoo's `addons_path`.** Each custom addon is a top-level directory here with
  an `__manifest__.py`; Odoo ignores everything else in the folder (`.agents/`,
  Dockerfiles). In development the folder is mounted into the Odoo container at
  `/mnt/extra-addons`, so Odoo sees edits at once. Staging and production build `Dockerfile`.
- Database: PostgreSQL from the `postgres` add-on. The Odoo role's connection settings are in
  the env (`HOST`, `PORT`, `USER`, `PASSWORD`, `DATABASE`); `psql` is in the
  image, but prefer `odoo shell` for ORM-level work. Do not re-initialize the database: the init
  container records first-time setup in the `diploi_parameters` table and skips it afterwards.
- Login is `admin` with `INITIAL_ADMIN_PASSWORD`, which is also the master password of the
  database manager. It is a secret: point the user to the deployment's **Environment** tab, never
  print it.
- The container runs as `odoo` (uid/gid 1000). `/var/lib/odoo` (filestore, sessions) and
  `/home/odoo` are persistent volumes, not part of the repository.
- `README.md` has the full storage and environment variable tables.

## The image and the chart

- `init.sh` is in the image and holds the whole update: it clones the database, upgrades it and puts it back when
  the upgrade fails (README, "When an update fails"). Read its header before changing it. It never drops the
  database under the live name.
- **What the chart hands to `init.sh` is only added to, never renamed or removed**: environment names and mount
  paths. A new image runs with every older chart still deployed.
- **In the Dockerfile, packages are only added within a series, and versions are pinned.** After a failed update the
  old code runs on the new image.
