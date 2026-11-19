# Releasing the Odoo component

For Alixea's developers. New projects do not get this file (`.alixeaignore`).

A change goes out in one of two ways, depending on the file.

| You changed                                                                     | Release it with  |
| ------------------------------------------------------------------------------- | ---------------- |
| `Dockerfile`, `init.sh` or `modules.sh`                                         | A new image      |
| The chart, `alixea.yaml`, `AGENTS.md`, the skills, `README.md`, `.alixeaignore` | The version tags |

If a change needs both, release the image first.

## A new image

**When Odoo publishes a new image, you only approve.** Every Monday at 05:00 UTC, **Base Image Check** builds the
series whose Odoo image changed: 20.0 every week, 18.0 and 19.0 on the first Monday of the month. For a fix that
cannot wait, run **Base Image Check** by hand, which checks all three. Twice a day, at 06:30 and 18:30 UTC, the
Enterprise fork releases Enterprise of the same date. Slack says when the image is built, and again when Enterprise
is released. Start at step 2.

After a change to `Dockerfile`, `init.sh` or `modules.sh`, build by hand: run **Pre-Build Components** on `main`. It builds every
series, or the list you give, such as `["19.0"]`. Each build is a new digest, and approving it restarts the
deployments that update automatically, so do not build more often than needed. A build by hand says nothing in
Slack. Untick **Skip Slack** when the others should hear of it.

1. Wait for the build. Slack says so when Odoo published the image, and says when such a build or a release failed.
2. Open the admin **Updates** page.
3. When the workflow is done, click **Check images**. **Latest** then shows the time of your build. Approving
   earlier approves the old build again.
4. Click **Approve** for each image. When Odoo published it, also click **Approve** for the Enterprise version from
   the Slack message, so image and Enterprise move together. Deployments update at 01:00 UTC, or at once with **Push now**.
5. Check one deployment of each series. Odoo answers and there is no notice.

Approval is per environment. Repeat steps 2 to 5 in every environment that should get the build.

A push to `main` only builds the tag `main`, which no deployment uses.

## The version tags

The versions `18.0`, `19.0` and `20.0` are git tags of this repository. All three point at the same commit. Move
them after a change to any file in the second row of the table above:

```sh
git fetch origin
for tag in 18.0 19.0 20.0; do git tag -f $tag origin/main; done
git push -f origin 18.0 19.0 20.0
```

After the move:

- New projects get the new files.
- Running deployments show **Pending Changes**. They take the new chart when someone applies it.
- Older projects keep the `AGENTS.md` and skills they were made with.

## A module set version

The cores download the module sets from a bucket, not from GitHub. Each version is released there once by the
**Release** workflow of the set's repository. A released version is final: a fix is a new version.

- **Alixea Generic, Alixea Finance:** push to the series branch, such as `19.0`, of `alixea-erp/alixea-generic` or
  `alixea-erp/alixea-finance`. The push is tagged `19.0/<date>` and released by itself. A Python package a module
  needs and the image lacks goes into the `Dockerfile` here, pinned.
- **Odoo Enterprise:** released by itself after an image of a new Odoo date is built (above). It takes Enterprise
  at the date of our newest image of each series. By hand: run **Release** in `alixea-erp/odoo-enterprise`, for every
  series or one.
- **OCA:** released by itself after an image of a new Odoo date is built, at OCA's newest commits. To change what
  is offered, edit `<series>.txt` in `alixea-erp/oca` (its README has the format), then run **Release**. It does
  every series whose list changed. The run's summary names the Python packages the
  modules need. One that the image lacks goes into the `Dockerfile` here, pinned, before the modules are offered.

Before it uploads, every release installs each of the set's modules once on a throwaway database. A module that
fails stops the release: the version does not show on the **Updates** page, and Slack says which module failed and
why. Fix it and release again. To release all the same, run **Release** by hand and tick **Skip check**.
The Alixea sets are released as bytecode for the image's Python, not as source: a new image on another Python
needs new releases of both.

Then click **Approve** for the version on the admin **Updates** page. Deployments that update automatically move to it at
01:00 UTC, or at once with **Push now**.

The release itself is the action `alixea-erp/action-module-set`. Its README says how to set up a new set
repository.

## A new Odoo series

1. Add the series to both workflows.
2. Add it to the catalog with a migration in the platform.
3. Tag it here.
4. Give every module set a branch and tags for it.
5. Write `.agents/skills/odoo-<series>/`.
6. Start a test deployment before you release. Odoo 20 needed two fixes that 18 and 19 did not.
