# Hosted Sites

A personal hub for hosting static sites — projects, pages, and one-off experiments — all from one repo, served by GitHub Pages.

## How it works

- The root **`index.html`** is the hub: a landing page that links to every site.
- Each site lives in **its own folder** with its own `index.html`.
- **`.nojekyll`** tells GitHub Pages to serve files exactly as they are (no Jekyll processing).

```
.
├── index.html        ← hub / landing page
├── oc-day/
│   └── index.html    ← "Thursday in OC" itinerary
└── README.md
```

## Live URLs

Once GitHub Pages is enabled:

- Hub: `https://thisconnor.github.io/hostedsites/`
- Any site: `https://thisconnor.github.io/hostedsites/<folder>/`

## Adding a new site

1. Create a folder named after the site (e.g. `my-project/`).
2. Put the site's `index.html` (and any assets — images, CSS, JS) inside it.
3. Add a card for it on the hub by copying the template block at the top of the card grid in `index.html`.

Or just hand the HTML file to Claude and say what to call it — it'll drop it in a folder and add it to the hub.

## Enabling GitHub Pages

Settings → Pages → Build and deployment → Source: **Deploy from a branch** → Branch: **`main`** / **`/ (root)`** → Save.
