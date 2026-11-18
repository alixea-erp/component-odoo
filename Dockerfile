# One image per Odoo series (18.0, 19.0, 20.0), used by development, staging and production alike
ARG ODOO_SERIES=19.0
FROM odoo:${ODOO_SERIES} AS odoo

USER root

ARG UID=1000
ARG GID=1000

RUN set -eux; \
    if getent passwd ${UID} >/dev/null; then \
      existing_user="$(getent passwd ${UID} | cut -d: -f1)"; \
      if [ "${existing_user}" != "odoo" ]; then userdel "${existing_user}"; fi; \
    fi; \
    if getent group ${GID} >/dev/null; then \
      existing_group="$(getent group ${GID} | cut -d: -f1)"; \
      if [ "${existing_group}" != "odoo" ]; then groupdel "${existing_group}"; fi; \
    fi; \
    if [ "$(getent group odoo | cut -d: -f3)" != "${GID}" ]; then groupmod -g ${GID} odoo; fi; \
    if [ "$(id -u odoo)" != "${UID}" ] || [ "$(id -g odoo)" != "${GID}" ]; then usermod -u ${UID} -g ${GID} odoo; fi; \
    chown -R ${UID}:${GID} /var/lib/odoo /etc/odoo /mnt/extra-addons

# Odoo's code out of Python's path. After a failed update Odoo runs from a copy of the old code on the deployment's
# disk (init.sh), and `odoo` is a namespace package: with both on the path Python would mix the two versions.
# PYTHONPATH names the one that runs. 19.0 and later also have `addons` beside `odoo`
RUN set -eux; \
    mkdir /opt/odoo; \
    mv /usr/lib/python3/dist-packages/odoo /opt/odoo/odoo; \
    if [ -d /usr/lib/python3/dist-packages/addons ]; then mv /usr/lib/python3/dist-packages/addons /opt/odoo/addons; fi

# Upgrades only the modules whose files changed (click-odoo-update). Within a series packages are only added here,
# never removed, and versions are pinned: after a failed update the old code runs on the new image
RUN pip install --break-system-packages --no-cache-dir click-odoo-contrib==1.24

# What Odoo Enterprise's modules import and Odoo's image lacks: dbfread, google-auth, PyJWT, paramiko and xmlsec.
# From Ubuntu and not pip, where xmlsec, google-auth and paramiko bring a newer lxml and cryptography than Odoo uses
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      python3-dbfread \
      python3-google-auth \
      python3-jwt \
      python3-paramiko \
      python3-xmlsec && \
    rm -rf /var/lib/apt/lists/*

# What modules of the sets need and Odoo's image lacks. Odoo refuses to install a module whose package is missing.
# For OCA (alixea-erp/oca, a release's summary names them): numpy, which stays below 2 for numpy-financial 1.0.0,
# the newest that OCA's account_loan allows, openupgradelib, pandas and plaid-python. For Alixea's own sets: Authlib
# (mcp_server, which asks for 1.6.12 up to 1.7), xmltodict (erpw_apix_invoicing), pycryptodome and python-gnupg
# (erpw_sepa_web_service, which also runs the image's gpg)
# NOTE! pandas brings the pip package tzdata, which is removed again. Its list of zones has old names that Ubuntu's
# own zone files no longer have, and Odoo 20.0 stops at the first one pytz cannot open. pandas uses Ubuntu's files
RUN pip install --break-system-packages --no-cache-dir \
      Authlib==1.6.12 \
      numpy==1.26.4 \
      numpy-financial==1.0.0 \
      openupgradelib==3.13.7 \
      pandas==2.2.3 \
      plaid-python==46.0.0 \
      pycryptodome==4.5.0 \
      python-gnupg==0.5.7 \
      xmltodict==1.0.4 && \
    pip uninstall --break-system-packages --yes tzdata

# Every zone Python lists and pytz knows opens, as Odoo 20.0 needs to start
RUN python3 -c 'import pytz, zoneinfo; [pytz.timezone(name) for name in zoneinfo.available_timezones() if name in pytz.all_timezones_set]'

COPY --chmod=755 init.sh modules.sh /

# One layer: moving Odoo above would otherwise ship its 1.3 GB twice, once in the layer it came in
FROM scratch
COPY --from=odoo / /

ARG ODOO_SERIES=19.0
# NOTE! Not Odoo's en_US.UTF-8: its image does not have that locale, and psql (a Perl script) says so at every call
ENV LANG=C.UTF-8 \
    ODOO_VERSION=${ODOO_SERIES} \
    ODOO_RC=/etc/odoo/odoo.conf \
    PYTHONPATH=/opt/odoo

EXPOSE 8069 8071 8072

USER 1000:1000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]
