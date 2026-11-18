#!/bin/bash
# Says which modules of each module set are installed, as JSON: {"<set>": ["<module>", ...]}. The platform runs it in
# the running Odoo container before a set is turned off (assetUsage in alixea.yaml), where the database's variables
# have the names Odoo's image reads.
# NOTE! Its own file and not "init.sh modules": an image from before this has no such file, and its init.sh would run
# the whole start for an argument it does not know
set -eu
# A database that does not answer is given up on before the platform stops waiting
ODOO_DB=$DATABASE ODOO_USER=$USER ODOO_PASSWORD=$PASSWORD PGHOST=$HOST PGPORT=$PORT PGCONNECT_TIMEOUT=5 exec /bin/bash /init.sh modules
