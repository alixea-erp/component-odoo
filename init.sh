#!/bin/bash
# Prepares the database and the code before Odoo starts. Runs in the init container of the pod, from the image.
#
# The rule everything here keeps: the database never records a version without a complete copy of that version's
# code on the deployment's disk. Odoo runs from the image when the image and the module sets are the version the
# database records. An update clones the database, upgrades it with the new code, and either records the new version
# or puts the clone back and runs the old code from its copy. Nothing outside this script takes part.
#
# What it may drop: never the database under the live name, that one is only renamed. Only a database it named
# itself (<name>__alixea_before, __alixea_new, __alixea_failed) that also carries the comment it wrote.
set -euo pipefail

DB=$ODOO_DB
DATA=${ALIXEA_DATA:-/var/lib/odoo}
SETS=${ALIXEA_SETS:-/mnt/addons}
EXTRA_ADDONS=${ALIXEA_EXTRA_ADDONS:-/mnt/extra-addons}
IMAGE_CODE=/opt/odoo
CONF=$DATA/etc-odoo/odoo.conf
CODE=$DATA/code
LOG=$DATA/update.log
BEFORE=${DB}__alixea_before
NEW=${DB}__alixea_new
FAILED=${DB}__alixea_failed
MARK='made by the init.sh of the Odoo component'

log() { echo "🟩 $(date -u +"%Y-%m-%dT%H:%M:%SZ") $1"; }

# The names go into SQL as they are
case "$DB$ODOO_USER" in *[!A-Za-z0-9_-]*) log "ERROR: the database and user names may only hold letters, digits, - and _"; exit 1 ;; esac

# Odoo 19+ reads these and they override odoo.conf, so they must name the odoo role
export PGUSER="$ODOO_USER" PGPASSWORD="$ODOO_PASSWORD" PGDATABASE="$DB"
export PGOPTIONS='--client-min-messages=warning'

admin_psql() { PGUSER="$POSTGRES_USER" PGPASSWORD="$POSTGRES_PASSWORD" psql -d postgres -v ON_ERROR_STOP=1 -qtA "$@"; }
db_exists() { [ "$(admin_psql -c "SELECT 1 FROM pg_database WHERE datname = '$1'")" = 1 ]; }
db_is_ours() { [ "$(admin_psql -c "SELECT shobj_description(oid, 'pg_database') FROM pg_database WHERE datname = '$1'")" = "$MARK" ]; }
db_mark() { admin_psql -c "COMMENT ON DATABASE \"$1\" IS '$MARK'"; }
db_allow() { ! db_exists "$1" || admin_psql -c "ALTER DATABASE \"$1\" ALLOW_CONNECTIONS true"; }

# Postgres refuses to clone or rename a database somebody is connected to, and a consultant's psql may be
db_end_sessions() {
  admin_psql -c "ALTER DATABASE \"$1\" ALLOW_CONNECTIONS false" \
    -c "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE datname = '$1' AND pid <> pg_backend_pid()" >/dev/null
}

# A step that lost its connection is tried again. An ended session takes a moment to be gone
retry() {
  local attempt
  for attempt in 1 2 3 4 5; do
    "$@" && return 0
    sleep 2
  done
  return 1
}

db_rename() { # <from> <to>
  db_end_sessions "$1" || true
  if retry admin_psql -c "ALTER DATABASE \"$1\" RENAME TO \"$2\""; then
    db_allow "$2"
  else
    db_allow "$1"
    return 1
  fi
}

# Drops a database only when it is one of ours by its name and by its comment
db_drop_ours() {
  db_exists "$1" || return 0
  case "$1" in "$BEFORE" | "$NEW" | "$FAILED"*) ;; *) return 1 ;; esac
  if ! db_is_ours "$1"; then
    log "A database $1 exists that this script did not make. It is left alone"
    return 1
  fi
  db_end_sessions "$1" || true
  retry admin_psql -c "DROP DATABASE \"$1\""
}

# The live database is never dropped: a half-upgraded one is renamed and kept for whoever looks into the failure,
# until an update works. Should somebody else's database have that name, it gets another
db_set_live_aside() {
  local target=$FAILED
  db_drop_ours "$FAILED" || target=${FAILED}_$(date +%s)
  db_rename "$DB" "$target"
  db_mark "$target"
}

db_drop_failed() {
  local name
  for name in $(admin_psql -c "SELECT datname FROM pg_database WHERE datname LIKE '$FAILED%'"); do db_drop_ours "$name" || true; done
}

db_clone() { # <from> <to>: copy-on-write on Btrfs, a full copy where the disk cannot
  db_end_sessions "$1" || true
  local status=0
  retry admin_psql -c "SET file_copy_method = clone" -c "CREATE DATABASE \"$2\" TEMPLATE \"$1\" STRATEGY = FILE_COPY OWNER \"$ODOO_USER\"" ||
    retry admin_psql -c "SET file_copy_method = copy" -c "CREATE DATABASE \"$2\" TEMPLATE \"$1\" STRATEGY = FILE_COPY OWNER \"$ODOO_USER\"" ||
    status=1
  db_allow "$1"
  [ $status = 0 ] && db_mark "$2"
}

get_parameter() { psql -d "${2:-$DB}" -qtAc "SELECT value FROM diploi_parameters WHERE key = '$1'" 2>/dev/null || true; }
set_parameter() { # <key> <value> [database]
  psql -d "${3:-$DB}" -v ON_ERROR_STOP=1 -q \
    -c "CREATE TABLE IF NOT EXISTS diploi_parameters (key TEXT PRIMARY KEY, value TEXT)" \
    -c "INSERT INTO diploi_parameters (key, value) VALUES ('$1', '$2') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value"
}

#
# The module sets the core mounted: DIPLOI_MODULE_SETS is "<set>=<checked> ...", DIPLOI_MODULE_SET_REFS
# "<set>=<version> ..." (the folder the core fetched the tag into)
#

set_ref() { echo " ${DIPLOI_MODULE_SET_REFS:-} " | sed -n "s/.* $1=\([^ ]*\) .*/\1/p"; }
manifest_value() { # <set folder> <installModules|modules>
  python3 - "$1/manifest.json" "$2" <<'PYEOF'
import json, os, sys
manifest = json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else {}
print(",".join(manifest.get(sys.argv[2], [])))
PYEOF
}

enabled_sets=""
for entry in ${DIPLOI_MODULE_SETS:-}; do
  if [ "${entry#*=}" = true ] && [ -d "$SETS/${entry%%=*}" ]; then enabled_sets="$enabled_sets ${entry%%=*}"; fi
done

# What this pod is: the image and the versions of the checked sets
parts="core=${ODOO_IMAGE:-unknown}"
for set_name in $enabled_sets; do parts="$parts"$'\n'"set:$set_name=$(set_ref "$set_name")"; done
WANTED=$(printf '%s' "$parts" | sha256sum | cut -c1-16)

#
# The copy of the code, $CODE/<id>: core/ is what PYTHONPATH names (the image's /opt/odoo), sets/<set> the sets,
# parts the versions it holds. Made under another name and renamed when it is whole
#

copy_tree() { # <from> <to>
  mkdir -p "$2"
  # Without what Odoo does not need to run, a third of the files: Python compiles again, and no module imports its tests
  tar -C "$1" --no-wildcards-match-slash --exclude=__pycache__ --exclude='addons/*/tests' -cf - . | tar -C "$2" -xf -
}

copy_code() { # <id> [id of the copy to take unchanged parts from]
  local target=$CODE/.making-$1 from=${2:+$CODE/$2} name source
  rm -rf "$target"
  mkdir -p "$target/sets"
  printf '%s\n' "$parts" >"$target/parts"

  while IFS= read -r part; do
    name=${part%%=*}
    if [ "$name" = core ]; then source=$IMAGE_CODE name=core; else source=$SETS/${name#set:} name=sets/${name#set:}; fi
    if [ -n "$from" ] && grep -qxF "$part" "$from/parts" 2>/dev/null && [ -d "$from/$name" ]; then
      cp -a --reflink=auto "$from/$name" "$target/$name"
    else
      copy_tree "$source" "$target/$name"
    fi
  done <<<"$parts"

  rm -rf "${CODE:?}/$1"
  mv "$target" "$CODE/$1"
}

set_addons_path() { sed -i "s#^addons_path = .*#addons_path = $1#" "$CONF"; }

# This folder, then each module repository cloned into it: a folder that is not a module but holds modules. They come
# before the sets, so the source of a set wins over its built modules while it is checked out
own_addons() {
  local folder name
  printf '%s' "$EXTRA_ADDONS"
  for folder in "$EXTRA_ADDONS"/*/; do
    name=$(basename "$folder")
    # NOTE! Other names are skipped: the path goes through sed and Odoo splits it on commas
    case "$name" in *[!A-Za-z0-9._-]*) continue ;; esac
    [ ! -f "$folder/__manifest__.py" ] && compgen -G "$folder*/__manifest__.py" >/dev/null && printf ',%s' "${folder%/}"
  done
  return 0
}

# Which code Odoo runs: the image and the mounts, or a copy
use_code() { # image | <id>
  local core sets_root addons_path set_name
  addons_path=$(own_addons)
  if [ "$1" = image ]; then core=$IMAGE_CODE sets_root=$SETS; else core=$CODE/$1/core sets_root=$CODE/$1/sets; fi
  for set_name in $( [ "$1" = image ] && echo "$enabled_sets" || ls "$sets_root" 2>/dev/null); do addons_path="$addons_path,$sets_root/$set_name"; done
  set_addons_path "$addons_path"
  ln -sfn "$core" "$CODE/current"
  export PYTHONPATH=$core
}

notice() { # shown on the deployment page: an init container that exits 0 with a message
  log "$1"
  echo "$1" >/dev/termination-log 2>/dev/null || true
}

addons_hash() { find "$EXTRA_ADDONS" -type f -printf '%P %s %T@\n' 2>/dev/null | sort | sha256sum | cut -c1-16; }

#
# Odoo's own steps
#

set_admin_password() { # <database>
  ODOO_TARGET_DB=$1 python3 <<'PYEOF'
import os

import psycopg2
from passlib.context import CryptContext

connection = psycopg2.connect(
    dbname=os.environ["ODOO_TARGET_DB"],
    user=os.environ["ODOO_USER"],
    password=os.environ["ODOO_PASSWORD"],
    host=os.environ["PGHOST"],
    port=os.environ["PGPORT"],
)
cursor = connection.cursor()
password_hash = CryptContext(["pbkdf2_sha512"]).hash(os.environ["INITIAL_ADMIN_PASSWORD"])
cursor.execute("UPDATE res_users SET password = %s WHERE login = 'admin'", (password_hash,))
connection.commit()
connection.close()
PYEOF
}

# Installs the modules of newly checked sets, removes those of unchecked ones, then upgrades what changed.
# Runs with the image's code and the mounted sets, and a set that goes still has its code in the old copy.
# click-odoo-update reads addons_path from the config only, so the path is set there
update_database() { # <database> <id of the old copy or ''> <upgrade | hashes>
  local database=$1 old_sets=${2:+$CODE/$2/sets} set_name modules key addons_path
  addons_path=$(own_addons)
  for set_name in $enabled_sets; do addons_path="$addons_path,$SETS/$set_name"; done
  set_addons_path "$addons_path"

  # Unchecked sets first: a set can conflict with another, and swapping them in one change must work
  for key in $(psql -d "$database" -qtAc "SELECT key FROM diploi_parameters WHERE key LIKE 'module_set:%'" 2>/dev/null || true); do
    set_name=${key#module_set:}
    case " $enabled_sets " in *" $set_name "*) continue ;; esac
    if [ -n "$old_sets" ] && [ -d "$old_sets/$set_name" ]; then
      modules=$(manifest_value "$old_sets/$set_name" modules)
      log "Module set $set_name: removing its modules and the modules depending on them"
      set_addons_path "$addons_path,$old_sets/$set_name"
      MODULES=$modules odoo shell --config="$CONF" -d "$database" --no-http <<'PYEOF'
import os
names = [name for name in os.environ["MODULES"].split(",") if name]
Module = env["ir.module.module"]
Module.search([("name", "in", names), ("state", "=", "to install")]).state = "uninstalled"
Module.search([("name", "in", names), ("state", "in", ["to upgrade", "to remove"])]).state = "installed"
installed = Module.search([("name", "in", names), ("state", "=", "installed")])
if installed:
    installed.button_immediate_uninstall()
env["ir.module.module"].search([("name", "in", names), ("state", "in", ["uninstalled", "uninstallable"])]).unlink()
env.cr.commit()
PYEOF
      set_addons_path "$addons_path"
    fi
    psql -d "$database" -v ON_ERROR_STOP=1 -q -c "DELETE FROM diploi_parameters WHERE key = '$key'"
  done

  for set_name in $enabled_sets; do
    modules=$(manifest_value "$SETS/$set_name" installModules)
    if [ -z "$(get_parameter "module_set:$set_name" "$database")" ] && [ -n "$modules" ]; then
      log "Module set $set_name: installing $modules"
      odoo --config="$CONF" -d "$database" --init="$modules" --stop-after-init
    fi
    set_parameter "module_set:$set_name" "$(set_ref "$set_name")" "$database"
  done

  if [ "$3" = hashes ]; then
    # A database made a moment ago: everything is current, only the hashes are missing
    click-odoo-update -c "$CONF" -d "$database" --only-compute-hashes
  else
    # Upgrades the installed modules whose files changed, by the hashes it keeps in the database
    click-odoo-update -c "$CONF" -d "$database"
  fi
  # New modules of the sets appear under Apps without being installed
  odoo shell --config="$CONF" -d "$database" --no-http <<'PYEOF'
env["ir.module.module"].update_list()
env.cr.commit()
PYEOF
}

failed_module() { grep -o 'Loading module [a-z0-9_]* ' "$LOG" 2>/dev/null | tail -1 | cut -d' ' -f3; }

#
# The start
#

log "Waiting for PostgreSQL"
until pg_isready -d postgres >/dev/null 2>&1; do sleep 2; done

admin_psql -v odoo_user="$ODOO_USER" -v odoo_password="$ODOO_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN CREATEDB NOSUPERUSER PASSWORD %L', :'odoo_user', :'odoo_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'odoo_user')
\gexec
SELECT format('ALTER ROLE %I WITH LOGIN CREATEDB NOSUPERUSER PASSWORD %L', :'odoo_user', :'odoo_password')
\gexec
SQL

mkdir -p "$DATA/etc-odoo" "$CODE"
if [ ! -f "$CONF" ]; then
  log "Creating default odoo.conf in persistent storage"
  cat >"$CONF" <<EOF
[options]
addons_path = $EXTRA_ADDONS
data_dir = $DATA
proxy_mode = True
admin_passwd = $INITIAL_ADMIN_PASSWORD
db_host = $PGHOST
db_port = $PGPORT
db_user = $ODOO_USER
db_password = $ODOO_PASSWORD
db_name = $DB
EOF
fi
# Odoo 20 listens on localhost only unless told otherwise, where the probe and the proxy do not reach it
grep -q '^http_interface' "$CONF" || sed -i '/^\[options\]/a http_interface = 0.0.0.0' "$CONF"

# A run that lost its connection in the middle may have left the live database closed
db_allow "$DB"

# What an interrupted run left
db_drop_ours "$NEW" || true
rm -rf "$DATA/filestore/$NEW" "$CODE"/.making-*
if db_exists "$BEFORE" && db_is_ours "$BEFORE"; then
  if db_exists "$DB" && [ "$(get_parameter code)" = "$WANTED" ]; then
    log "The last update had finished, removing its clone"
    db_drop_ours "$BEFORE"
  else
    log "The last update did not finish, putting the database back as it was before it"
    ! db_exists "$DB" || db_set_live_aside
    db_rename "$BEFORE" "$DB"
    admin_psql -c "COMMENT ON DATABASE \"$DB\" IS NULL"
  fi
fi

RECORDED=$(db_exists "$DB" && get_parameter code || true)
# NOTE! No trailing slash: "current" is a link, and rm -rf on a link with a slash empties what it points at
for copy in "$CODE"/*; do
  [ -d "$copy" ] && [ ! -L "$copy" ] || continue
  [ "$(basename "$copy")" = "$RECORDED" ] || rm -rf "$copy"
done

#
# No database: the first start. The database is made beside the copy of the code, and named when both are whole
#

if ! db_exists "$DB"; then
  if db_exists "$NEW"; then
    log "ERROR: a database named $NEW exists that this script did not make, and the new database is built under that name"
    exit 1
  fi
  log "Creating the database (this can take a few minutes)"
  copy_code "$WANTED" &
  copy_pid=$!

  admin_psql -c "CREATE DATABASE \"$NEW\" OWNER \"$ODOO_USER\""
  db_mark "$NEW"
  use_code image
  odoo --config="$CONF" -d "$NEW" --init=base --stop-after-init
  set_admin_password "$NEW"
  set_parameter initialization done "$NEW"
  update_database "$NEW" "" hashes

  if ! wait $copy_pid; then
    log "ERROR: the code could not be copied to the deployment's disk, which a later update needs. Is the disk full?"
    exit 1
  fi
  set_parameter code "$WANTED" "$NEW"
  # The files before the name: a start that finds the new name treats it as an ordinary one. A filestore of the live
  # name may be there from a database somebody dropped. It is kept and added to, files are named by their content
  if [ -d "$DATA/filestore/$NEW" ]; then
    mkdir -p "$DATA/filestore/$DB"
    cp -a -n "$DATA/filestore/$NEW/." "$DATA/filestore/$DB/"
    rm -rf "$DATA/filestore/$NEW"
  fi
  db_rename "$NEW" "$DB"
  admin_psql -c "COMMENT ON DATABASE \"$DB\" IS NULL"
  log "Odoo init complete: a new database"
  exit 0
fi

#
# The recorded version is this pod's: an ordinary start
#

if [ -n "$RECORDED" ] && [ "$RECORDED" = "$WANTED" ] && [ -d "$CODE/$RECORDED" ]; then
  use_code image
  rm -f "$CODE/failed"
  log "Odoo init complete: nothing to update"
  exit 0
fi

#
# Another version: an update. Or a database with no copy of its code on this disk, which was not made here
# (an import, a dump of another deployment or an older one) and has no old code to go back to
#

HAS_OLD_CODE=false
if [ -n "$RECORDED" ] && [ -d "$CODE/$RECORDED" ]; then HAS_OLD_CODE=true; fi
attempt="$WANTED $(addons_hash)"

fail() { # <message>: Odoo runs the old code, or the start stops when there is none
  if [ $HAS_OLD_CODE = true ]; then
    use_code "$RECORDED"
    notice "Automatic update failed: $1. Odoo runs the previous versions."
    exit 0
  fi
  notice "The database could not be brought to this version: $1. It was left as it was."
  exit 1
}

# The same attempt failed before and nothing changed since: a restart does not cost an upgrade
if [ "$(cat "$CODE/failed" 2>/dev/null | head -1)" = "$attempt" ]; then
  fail "$(sed -n 2p "$CODE/failed")"
fi

log "Updating: cloning the database"
if ! db_drop_ours "$BEFORE"; then
  fail "a database named $BEFORE is in the way of the clone"
fi
if ! db_clone "$DB" "$BEFORE"; then
  fail "the database could not be cloned"
fi

log "Updating: upgrading the database and copying the new code"
if [ $HAS_OLD_CODE = true ]; then copy_code "$WANTED" "$RECORDED" & else copy_code "$WANTED" & fi
copy_pid=$!

use_code image
# NOTE! Not "update_database ... || status=$?": inside an || list bash ignores set -e in the whole function, and a
# failed upgrade followed by a step that works would count as done
set +e
(
  set -e
  update_database "$DB" "$([ $HAS_OLD_CODE = true ] && echo "$RECORDED")" upgrade
) >"$LOG" 2>&1
update_status=$?
wait $copy_pid
copy_status=$?
set -e

if [ $update_status = 0 ] && [ $copy_status = 0 ]; then
  set_parameter code "$WANTED"
  db_drop_ours "$BEFORE" || true
  db_drop_failed
  [ "$RECORDED" = "$WANTED" ] || [ -z "$RECORDED" ] || rm -rf "${CODE:?}/$RECORDED"
  rm -f "$CODE/failed"
  log "Odoo init complete: updated"
  exit 0
fi

tail -n 30 "$LOG" || true
rm -rf "${CODE:?}/$WANTED"
db_set_live_aside
db_rename "$BEFORE" "$DB"
admin_psql -c "COMMENT ON DATABASE \"$DB\" IS NULL"

module=$(failed_module)
reason=$([ $update_status != 0 ] && echo "${module:+module $module}" || echo "the new code could not be copied to the disk")
reason=${reason:-the upgrade stopped, see $LOG}
# A copy that failed is tried again at the next start: the disk may have room by then
[ $update_status = 0 ] || printf '%s\n%s\n' "$attempt" "$reason" >"$CODE/failed"
fail "$reason"
