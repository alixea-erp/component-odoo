---
name: odoo-18
description: >-
  For a deployment that runs Odoo 18.0 (`odoo --version`). The odoo-guidelines,
  odoo-web-guidelines, odoo-security and odoo-review skills describe Odoo
  20.0. Lists where they are wrong for 18.0 (access rights, SQL constraints,
  domains, route types, test tags, Owl 2, ...) and what to write instead, and
  how public pages rendered by a controller load their assets on 18.0. Read it
  before using any of those skills or writing a page template; where they
  disagree, this file wins.
---

# Odoo 18.0 corrections to the 20.0 skills

The `odoo-guidelines`, `odoo-web-guidelines`, `odoo-security` and `odoo-review`
skills are copied unchanged from Odoo's `20.0` branch; Odoo does not publish
them for 18.0. This deployment runs **Odoo 18.0**. Most of their rules hold on
18.0; the ones below do not. **Where a skill and this file disagree, this file
wins.** Everything was checked against the 18.0 source in the image, and the
examples were run on an 18.0 deployment.

When unsure whether an API exists on 18.0, check the source instead of a
remembered API: in the Odoo container it is at `/var/lib/odoo/code/current/odoo`
(`grep -rn` there; the core addons are in its `addons/`).

## Access rights (`odoo-guidelines` security.md, `odoo-security` Access control)

The `ir.access` model, `security/ir.access.csv` and its `operation` column do
not exist on 18.0; the file fails to load. 18.0 has the two older models:

**ACLs**, in `security/ir.model.access.csv`:

```csv
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_library_book_user,library.book user,model_library_book,base.group_user,1,1,1,0
access_library_book_manager,library.book manager,model_library_book,base.group_system,1,1,1,1
```

- `model_id:id` is `model_` + the model name with dots as underscores. The file
  goes in the manifest's `data`, after the XML that defines any groups it uses.
- ACL rows only grant. The user gets an operation if any row for one of their
  groups grants it.
- **A row with an empty `group_id` grants to every user, portal and public
  included.** This is the opposite of 20.0, where a group-less row only
  restricts. Flag group-less rows granting write, create or unlink, and scrutinize
  them even for read.
- Default deny still holds: a model without an ACL row is inaccessible, and
  loading the module logs "have no access rules".
- `base.group_everyone` does not exist on 18.0. Grant internal users with
  `base.group_user`; `base.group_portal` and `base.group_public` get the same
  scrutiny as in the skill.

**Record rules** are `ir.rule` records in `security/<module>_security.xml`:

```xml
<record id="library_book_rule_company" model="ir.rule">
    <field name="name">library.book: multi-company</field>
    <field name="model_id" ref="model_library_book"/>
    <field name="domain_force">[('company_id', 'in', company_ids)]</field>
</record>
```

- A rule applies to the operations whose `perm_read`/`perm_write`/`perm_create`/
  `perm_unlink` are set; all four default to true.
- A rule **with** `groups` is OR-ed with the other group rules of the user's
  groups. A rule **without** `groups` is global: AND-ed onto every user, and
  never grants. The skills' reasoning about restrictions (cover every operation
  that needs restricting, non-overlapping restrictions lock everyone out)
  applies to global rules.
- Multi-company: a global rule on `company_ids`; for an optional company use
  `['|', ('company_id', '=', False), ('company_id', 'in', company_ids)]`.
- ACLs and rules are separate checks: an operation needs an ACL grant first,
  then the records must pass the rules.

## Constraints and indexes (`odoo-guidelines` orm.md, fields.md, python.md)

`models.Constraint`, `models.Index` and `models.UniqueIndex` do not exist on
18.0. `_sql_constraints` is the correct API and is **not** a finding:

```python
_sql_constraints = [
    ('isbn_unique', 'unique(isbn)', "Another book already has this ISBN."),
]
```

For a multi-column or custom index, create it in the model's `init()` with
`odoo.tools.sql.create_index` (or `create_unique_index`). In the model body
order, `_sql_constraints` goes with the other private attributes.

## Domains (`odoo-guidelines` orm.md, `odoo-security` Domain injection)

`odoo.fields.Domain` does not exist on 18.0. Combine domains you hold with
`odoo.osv.expression`:

```python
from odoo.osv import expression

domain = expression.AND([security_domain, user_domain])
```

`AND`/`OR` normalize each domain first, so a user-supplied `'|'` cannot widen
the security part; the rule against concatenating lists stands. Prefix
operators (`'|'`, `'&'`, `'!'`) inside a literal domain, such as a record
rule's `domain_force`, are normal 18.0 syntax.

## Controllers (`odoo-guidelines` controllers.md, `odoo-security` Routes)

- Route `type` is `'http'` or `'json'`. `'jsonrpc'` and `'json2'` do not exist
  on 18.0. What the skills say about `jsonrpc` routes (no CSRF token, protected
  by the JSON content type) applies to `type='json'`.
- `auth='bearer'` exists; `bearer_scope` does not.

## Tests (`odoo-guidelines` tests.md)

- The default tags on 18.0 are `standard` and **`at_install`**, not
  `post_install`. A test that needs the fully loaded registry, and every
  `HttpCase`, must say so: `@tagged('post_install', '-at_install')`.
- `mock_datetime_and_now` does not exist on 18.0. What the skill says about
  the two clocks holds; freeze both by hand, as Odoo's own 18.0 tests do:

  ```python
  from unittest.mock import patch

  from freezegun import freeze_time

  from odoo import fields

  now = fields.Datetime.to_datetime("2024-01-01 10:00:00")
  with freeze_time(now), patch.object(self.env.cr, 'now', lambda: now):
      book = self.env['library.book'].create({'name': "Dune"})
  ```
- Everything else in tests.md holds on 18.0 (`BaseCommon`,
  `allow_inherited_tests_method`, `expectUnloadPage`, `mute_logger`).

## QWeb and JavaScript (`odoo-security` XSS, `odoo-web-guidelines`)

- `t-esc` still works in server QWeb on 18.0 as a deprecated alias of `t-out`,
  and `t-raw` is accepted with a warning and escapes like `t-out`. Replace both
  with `t-out`; neither is a rendering bug here.
- `@web/core/utils/html` on 18.0 exports `htmlEscape`, `isHtmlEmpty` and
  `setElementContent`; `setInnerHtml` and `htmlJoin` do not exist.
  `setElementContent(element, content)` sets `innerHTML` only for a `Markup`
  value and `textContent` otherwise. Owl's tagged-template ``markup`...` ``
  exists (Owl 2.8).
- **18.0 runs Owl 2.8, not Owl 3.** "Use the Owl 3 hooks" does not apply:
  `useState`, `useRef`, `static props` and `useEffect(effect, () => [deps])`
  are the API, and templates read the component's members by name (`state`,
  `props`). `computed`, `signal`, `proxy`, `useProps`, `useOnChange`,
  `providePlugins` and `usePlugin` do not exist.
- "Avoid getters": with no `computed`, use a plain function.
- "Use `window` members directly" does not apply: on 18.0 `browser` from
  `@web/core/browser/browser` is a separate object, the web client's code
  goes through it (`browser.setTimeout`, `browser.localStorage`) and its tests
  patch it (`patchWithCleanup(browser, ...)`). Follow the code around.
- "Give every icon `role="img"`": 18.0 has no `<i class="oi" data-icon="...">`.
  Its icons are Font Awesome (`fa fa-trash`) and Odoo's `oi oi-*` classes. The
  rule holds with those: `<i class="fa fa-lock" role="img" title="Private"
  aria-label="Private"/>`, or `aria-hidden="true"` for a decorative one.

## Public pages

Odoo's skills do not cover pages a controller renders for the browser. On 18.0:

- The page template calls **`web.frontend_layout`**. It loads the
  `web.assets_frontend` bundles (Bootstrap, the frontend JS and every addon's
  frontend assets) and adds a header and footer; `t-set` `title`, `no_header`
  or `no_footer` inside the `t-call` to adjust it. Attributes on the `t-call`
  element itself (`title.f="..."`, the 19.0 and 20.0 form) are ignored on
  18.0. `web.layout` is only the bare HTML shell: a page on it has no CSS and
  no JavaScript. With `portal` installed, `portal.frontend_layout` adds the
  portal navigation; with `website`, `website.layout` adds the site's menu and
  theme.
- The addon's styles, JavaScript and Owl templates go into `web.assets_frontend`
  in the manifest. Never write `<link>` or `<script>` tags pointing at files in
  `static/`: SCSS is only compiled inside a bundle, and `@web/...`/`@odoo/owl`
  imports only resolve there.
- Interactive parts are Owl components registered in the `public_components`
  registry and placed with an `<owl-component>` tag, which the frontend mounts
  on page load; props are passed as JSON.

```python
# controllers/main.py
class LibraryPublic(http.Controller):
    @http.route('/library', type='http', auth='public')
    def library(self):
        return request.render('library.page', {'start': 3})
```

```xml
<!-- views/library_templates.xml, listed in the manifest's data -->
<template id="page" name="Library page">
    <t t-call="web.frontend_layout">
        <t t-set="title">Library</t>
        <div class="o_library container py-5">
            <owl-component name="library.counter" t-att-props="json.dumps({'start': start})"/>
        </div>
    </t>
</template>
```

```python
# __manifest__.py
'assets': {
    'web.assets_frontend': [
        'library/static/src/**/*',  # counter.js, counter.xml, counter.scss
    ],
},
```

```js
// static/src/counter/counter.js
import { Component, useState } from "@odoo/owl";
import { registry } from "@web/core/registry";

export class Counter extends Component {
    static template = "library.Counter";
    static props = { start: Number };

    setup() {
        this.state = useState({ value: this.props.start });
    }

    increment() {
        this.state.value++;
    }
}

registry.category("public_components").add("library.counter", Counter);
```

```xml
<!-- static/src/counter/counter.xml -->
<templates xml:space="preserve">
    <t t-name="library.Counter">
        <button class="o_library_counter btn btn-primary" t-on-click="increment">
            Count: <t t-out="state.value"/>
        </button>
    </t>
</templates>
```

After adding SCSS, run the `odoo-scss-check` script; it compiles
`web.assets_frontend` too.

## Rules that do not apply to this folder

- `odoo-guidelines` stable.md and `odoo-review` "Stable vs master" are about
  patches to Odoo's own released branches. Addons in this folder are not a
  stable branch just because they run on 18.0: adding fields, models and views
  is fine. Review them as new code.
- `populate/` with `populate.blueprint` records (module structure) is a 20.0
  feature. 18.0 has only the older `odoo-bin populate` command, which reads
  `_populate_factories` methods on models; no core module defines any.
- `--unsafe-policy` (`odoo-security`, `eval`) does not exist on 18.0.
- `odoo-review` mentions enterprise sibling branches, runbot and the Odoo
  repository's `ruff.toml`; none exist here.
