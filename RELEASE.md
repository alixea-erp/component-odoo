# Releasing the Odoo component

For Alixea's developers. New projects do not get this file (`.alixeaignore`).

A change goes out in one of two ways, depending on the file.

| You changed                                                                     | Release it with  |
| ------------------------------------------------------------------------------- | ---------------- |
| `Dockerfile` or `init.sh`                                                       | A new image      |
| The chart, `alixea.yaml`, `AGENTS.md`, the skills, `README.md`, `.alixeaignore` | The version tags |

If a change needs both, release the image first.

## A new image

**When Odoo publishes a new image, you only approve.** Every night at 05:00 UTC, **Base Image Check** builds the
series whose Odoo image changed. Twice a day, at 06:30 and 18:30 UTC, the Enterprise fork releases Enterprise of the
same date. Then Slack says the series is ready to try. Start at step 2.

After a change to `Dockerfile` or `init.sh`, build by hand: run **Pre-Build Components** on `main`. It builds every
series, or the list you give, such as `["19.0"]`. Each build is a new digest, and approving it restarts the
deployments that update automatically, so do not build more often than needed.

1. Wait for the build. Slack says so when Odoo published the image, and says when a build or a release failed.
2. Open the admin **Settings** page and find **Automatic updates**.
3. When the workflow is done, click **Check now**. **Latest build** then shows the time of your build. Approving
   earlier approves the old build again.
4. Click **Approve** for each image. When Odoo published it, also set the Enterprise version from the Slack message
   as **Latest**, so image and Enterprise move together. Deployments update at 01:00 UTC, or at once with **Push now**.
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

- **Alixea modules, Alixea Finance:** push a tag such as `19.0/1.4.0` on the series branch. The release runs by
  itself.
- **Odoo Enterprise:** released by itself after an image of a new Odoo date is built (above). It takes Enterprise
  at the date of our newest image of each series. By hand: run **Release** in `alixea-erp/odoo-enterprise`, for every
  series or one.
- **OCA:** add the module to `<series>.txt` in `alixea-erp/oca` (`+name` also installs it when the set is turned on),
  then run **Release** with the series. Tick **newest** to move every repository to its newest commit. The run's
  summary names the dependencies it added and the Python packages the image may lack.

Then set the version as **Latest** on the admin **Settings** page. Deployments that update automatically move to it at
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
