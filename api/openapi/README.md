# OpenAPI specs

Visual, browsable docs for the API routes. Multi-file OpenAPI 3.1, split by the `paths/` and `components/`.

## Layout

```
openapi.yaml              # root: info, servers, tags, security, $refs every path
index.html                # Swagger UI page that loads openapi.yaml
paths/                    # one file per resource; each holds that resource's path items
  identity.yaml           # /me, /profiles/{username}
  guides.yaml             # /guides
  variants.yaml           # /variants
  guide-revisions.yaml    # /guide-revisions
  learning-paths.yaml     # /paths
  learning-path-revisions.yaml  # /path-revisions
  graph.yaml              # /prerequisites, /todos
  subjects.yaml           # /subjects
  reviews.yaml            # /reviews
  media.yaml              # /media
components/
  schemas/                # models, grouped into a subfolder per domain (mirrors paths/)
    common/               # primitives + cross-domain enums (Uuid, Error, NodeStatus, ...)
    identity/  guides/  variants/  guide-revisions/
    learning-paths/  learning-path-revisions/
    subjects/  reviews/  media/
  responses/_shared.yaml  # reusable error responses
```

## View

`index.html` is a Swagger UI page that loads `openapi.yaml`.

```bash
# from api/
pnpm docs:serve        # serves this folder at http://localhost:4000
```

Open [http://localhost:4000](http://localhost:4000) and Swagger UI loads the whole API.

## Adding a schema

Drop a new `.yaml` under the matching `components/schemas/<domain>/` folder (or
`common/` if it's shared), then `$ref` it. Refs are relative to the file they
live in:

- within the same folder: `$ref: './Other.yaml'`
- another domain: `$ref: '../common/Uuid.yaml'`
- from a path file: `$ref: '../components/schemas/<domain>/Name.yaml'`

The spec is plain OpenAPI 3.1, so any validator/editor (Swagger Editor, Spectral,
etc.) can check it if you want one.