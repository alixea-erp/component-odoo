---
name: odoo-20
description: >-
  For a deployment that runs Odoo 20.0 (`odoo --version`). The odoo-guidelines,
  odoo-web-guidelines, odoo-security and odoo-review skills are Odoo's own for
  20.0 and hold; this file adds what they do not cover for addons in this
  folder: public pages rendered by a controller with Owl 3 components, values
  passed to a layout template, the few names they get wrong, and the rules
  meant only for Odoo's own repository. Read it before writing a page template.
---

# Odoo 20.0 additions to the 20.0 skills

The `odoo-guidelines`, `odoo-web-guidelines`, `odoo-security` and `odoo-review`
skills are copied unchanged from Odoo's `20.0` branch, and this deployment runs
**Odoo 20.0**: their rules hold, including `security/ir.access.csv`,
`models.Constraint`, `odoo.fields.Domain`, `post_install` by default,
`mock_datetime_and_now` and the Owl 3 hooks. The points below add to them.
**Where a skill and this file disagree, this file wins.** Everything was checked
against the 20.0 source in the image, and the examples were run on a 20.0
deployment.

When unsure whether an API exists on 20.0, check the source instead of a
remembered API: in the Odoo container it is at `/var/lib/odoo/code/current/odoo`
(`grep -rn` there; the core addons are in its `addons/`). Odoo 20 is newer than
most of what a model has seen, so check more often than for 18.0 or 19.0.

## JavaScript (`odoo-security` XSS)

`@web/core/utils/html` has no `setInnerHtml`. Use `setElementContent(element,
content)`, which sets `innerHTML` only for markup and `textContent` otherwise,
or `htmlJoin`, `htmlSprintf` and the other helpers it exports.

## Public pages

Odoo's skills do not cover pages a controller renders for the browser. On 20.0:

- The page template calls **`web.frontend_layout`**. It loads the
  `web.assets_frontend` bundles (Bootstrap, the frontend JS and every addon's
  frontend assets) and adds a header and footer. **Values for the called
  template are attributes of the `t-call`**: `title.f="Library"` for a string,
  `no_header="True"` or `no_footer="True"` for an expression. A `t-set` inside
  the `t-call` no longer reaches the called template on 20.0: the page renders
  with the default title, and nothing says why. `web.layout` is only the bare
  HTML shell: a page on it has no CSS and no JavaScript. With `portal`
  installed, `portal.frontend_layout` adds the portal navigation; with
  `website`, `website.layout` adds the site's menu and theme.
- The addon's styles, JavaScript and Owl templates go into `web.assets_frontend`
  in the manifest. Never write `<link>` or `<script>` tags pointing at files in
  `static/`: SCSS is only compiled inside a bundle, and `@web/...`/`@odoo/owl`
  imports only resolve there.
- Interactive parts are Owl 3 components registered in the `public_components`
  registry and placed with an `<owl-component>` tag, which the frontend mounts
  on page load; props are passed as JSON. Behaviour on server-rendered markup
  without a component is an `Interaction` (`@web/public/interaction`)
  registered in `public.interactions`.
- Owl 3 components declare their props with `props = useProps({...})` and the
  types of `t`, keep state in a `proxy` (or a `signal`), and their templates
  name everything through `this.`, as Odoo's own 20.0 templates do.
  `useState`, `useRef` and `static props` are gone and fail at once.

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
    <t t-call="web.frontend_layout" title.f="Library">
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
import { Component, proxy, t, useProps } from "@odoo/owl";
import { registry } from "@web/core/registry";

export class Counter extends Component {
    static template = "library.Counter";

    props = useProps({ start: t.number() });

    setup() {
        this.state = proxy({ value: this.props.start });
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
        <button class="o_library_counter btn btn-primary" t-on-click="() => this.increment()">
            Count: <t t-out="this.state.value"/>
        </button>
    </t>
</templates>
```

After adding SCSS, run the `odoo-scss-check` script; it compiles
`web.assets_frontend` too.

## Rules that do not apply to this folder

- `odoo-guidelines` stable.md and `odoo-review` "Stable vs master" are about
  patches to Odoo's own released branches. Addons in this folder are not a
  stable branch just because they run on 20.0: adding fields, models and views
  is fine. Review them as new code.
- `odoo-review` mentions enterprise sibling branches, runbot and the Odoo
  repository's `ruff.toml`; none exist here.
