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

COPY --chmod=755 init.sh /init.sh

# One layer: moving Odoo above would otherwise ship its 1.3 GB twice, once in the layer it came in
FROM scratch
COPY --from=odoo / /

ARG ODOO_SERIES=19.0
ENV LANG=en_US.UTF-8 \
    ODOO_VERSION=${ODOO_SERIES} \
    ODOO_RC=/etc/odoo/odoo.conf \
    PYTHONPATH=/opt/odoo

EXPOSE 8069 8071 8072

USER 1000:1000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]
