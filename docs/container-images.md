# Container image naming and tagging convention

This document is the source of truth for the **identity** of the container
images published from `LibreCodeCoop/nextcloud-docker`:

* how published image names are formed;
* how tags express channel, version and runtime variant;
* which tags are moving and which are immutable;
* what metadata every published image must expose so it can be traced back to
  its sources.

It defines a **convention**, not the current state of the registry. Tags that
were published before this convention existed are historical implementation
details and do not become part of it (see
[Relationship to current tags](#relationship-to-current-tags)). Changes to
Dockerfiles, workflows or publishing behaviour to adopt this convention are
tracked in separate issues.

Build internals (Dockerfiles, scanning, smoke tests) and deployment recipes are
documented elsewhere. Reference this document as `docs/container-images.md`
from `AGENTS.md`, workflows and consuming repositories.

## Anatomy of an image identity

An image reference is `<image name>:<tag>`:

| Part | Answers | Defined in |
| --- | --- | --- |
| image name | Which component does this image contain? | [Image names](#image-names) |
| tag | Which channel, which version or upstream revision, which runtime variant? | [Channels and versions](#channels-and-versions), [Runtime variants](#runtime-variants), [Tag grammar](#tag-grammar) |

**Rule:** everything that changes between builds or over time — channel,
version, upstream revision, runtime variant — is expressed in the tag and
**never** in the image name. A component keeps one name for its whole
lifetime.

## Image names

Images are published to the GitHub Container Registry as:

```
ghcr.io/librecodecoop/nextcloud-docker-<component>
```

all lowercase. This repository publishes two components:

| Component | Image name | Contains |
| --- | --- | --- |
| `app` | `ghcr.io/librecodecoop/nextcloud-docker-app` | the Nextcloud application runtime (PHP) |
| `web` | `ghcr.io/librecodecoop/nextcloud-docker-web` | the web server front-end that serves the Nextcloud volume |

Rules:

1. `<image name> := <registry>/<repository>-<component>`, all lowercase. The
   repository part is this repository's name; the component is a short,
   lowercase noun.
2. The component says **what the image contains** (`app`, `web`) and nothing
   else. Version, channel and runtime words do not belong in the name; they
   belong in the tag.
3. A new component is added only when this repository really starts publishing
   a new kind of image. Components are never invented for documentation
   purposes.
4. Consuming environments that need extra tooling **extend** the image
   (`FROM ...`) or mount their own configuration. They do not fork the name.

## Channels and versions

### Channels

| Channel | Follows | Typical use |
| --- | --- | --- |
| `stable` | released Nextcloud versions | production, testing |
| `master` | the current upstream Nextcloud Server `master` | development of software that follows the Nextcloud public APIs without waiting for an alpha, beta or release candidate |

The development channel is named `master`. Its identity is "whatever upstream
`master` is right now" — it is **not** identified by a Nextcloud major version.
When upstream `master` moves to the next major, no image name and no tag
meaning changes.

### Version (revision) segments

The revision segment identifies what a given image was built from:

| Channel | Revision segment | Example | Meaning |
| --- | --- | --- | --- |
| `stable` | the released Nextcloud version, exactly as upstream publishes it | `34.0.6` | built from Nextcloud `34.0.6` |
| `master` | the snapshot date `YYYYMMDD` of the upstream development build | `20261002` | built from the upstream `master` snapshot of that day (for example the daily tarball) |

A Nextcloud **major** (`34`) is not a revision segment. It appears only in an
optional moving alias for the stable channel (see
[Tag grammar](#tag-grammar)) and never identifies a development image.

## Runtime variants

The runtime variant says **how** a component runs — for the application image,
which PHP runtime it embeds. It is the last segment of the tag and is
independent from the channel and the version: adding a variant adds tags, it
never changes the meaning of the other segments.

Variants are defined per component:

| Component | Variants published today | Notes |
| --- | --- | --- |
| `app` | `fpm` | built on the upstream Nextcloud FPM image |
| `web` | — (one runtime only) | no variant segment while that stays true |

* `apache` is a typical variant name for an application image, but **this
  repository does not publish it today**; it appears below only as an example
  of how the variant segment works. A variant is documented as supported only
  after it exists.
* When a component publishes exactly one runtime, the variant segment is
  omitted. As soon as a component publishes more than one variant, the variant
  segment becomes mandatory for that component.
* The variant is never merged into the revision segment: `34.0.6-fpm` is a
  revision plus a variant, not a revision.

## Tag grammar

```
<tag>       ::= <moving> | <immutable>

<moving>    ::= <channel> [ "-" <major> ] [ "-" <variant> ]
<immutable> ::= <channel> "-" <revision> [ "-" <variant> ] [ "-r" <build> ]

<channel>   ::= "stable" | "master"
<major>     ::= <Nextcloud major>              # stable channel only, e.g. 34
<revision>  ::= <Nextcloud version>            # stable channel, e.g. 34.0.6
              | <snapshot date>                # master channel, e.g. 20261002
<variant>   ::= "fpm" | ...                    # per component (see above)
<build>     ::= "2" | "3" | ...                # rebuild serial (see below)
```

Disambiguation: a bare number (`34`) is a major and occurs only in moving tags;
a dotted version (`34.0.6`) or an eight-digit date (`20261002`) is a revision
and occurs only in immutable tags.

A tag identifies an image, not an architecture: where a build produces several
architectures, the tag refers to the multi-architecture image and the container
runtime picks the matching one. Per-architecture images are an implementation
detail and are not part of this convention.

### Moving tags

A **moving tag** may point to a newer image over time.

| Tag | Points at | Example |
| --- | --- | --- |
| `stable[-<variant>]` | the current image of the stable channel | `stable-fpm` |
| `stable-<major>[-<variant>]` | the current stable image of one Nextcloud major | `stable-34-fpm` |
| `master[-<variant>]` | the current image of the master channel | `master-fpm` |

Use moving tags for development environments, for tracking "always current",
and for anything that is meant to follow a channel. Do not use them where
reproducibility matters: the image behind them changes without warning, and
rollback is only possible to whatever was published before.

### Immutable tags

An **immutable tag** must always identify the same published image. Once
published, it is never overwritten or moved.

```
stable-34.0.6-fpm         # Nextcloud 34.0.6, FPM runtime
master-20261002-fpm       # upstream master snapshot of 2026-10-02, FPM runtime
stable-34.0.6             # web component built for the same release
stable-34.0.6-fpm-r2      # second (rebuilt) image for the same identity
```

* The tag carries the upstream revision — the released Nextcloud version on
  `stable`, the upstream snapshot date on `master` — so the exact build or
  upstream revision it identifies is readable from the tag itself.
* **Publish once:** an immutable tag is pushed at most once. If a rebuild of the
  same channel, revision and variant produces a different image — for example
  a scheduled rebuild that refreshes OS packages — the rebuild is published
  with a rebuild serial `-r<N>` (`-r2`, `-r3`, …). The first build of an
  identity has no serial.
* Use immutable tags for production environments, release notes, bug reports
  and every reference that must keep meaning over time. Pair the application
  and web images of one build by taking the same revision (`app:stable-34.0.6-fpm`
  with `web:stable-34.0.6`).

### Tag patterns to avoid

These patterns are ambiguous and are **not** part of the convention:

* bare `latest`, bare `dev`, or any tag without a channel;
* a development image identified only by a Nextcloud major version (for example
  `35`): the major is not the identity of the development channel, and the same
  tag would silently change meaning when upstream moves on;
* a tag without a variant for a component that publishes more than one variant;
* version, channel or runtime words inside the image name;
* re-pushing different content under an already published immutable tag.

## Examples

Illustrative references for the components this repository publishes. Version
numbers and dates are examples only; they do not depend on any particular
Nextcloud release or development cycle.

| Case | Reference |
| --- | --- |
| stable image (moving) | `ghcr.io/librecodecoop/nextcloud-docker-app:stable-fpm` |
| stable immutable image | `ghcr.io/librecodecoop/nextcloud-docker-app:stable-34.0.6-fpm` |
| stable immutable web front-end for the same release | `ghcr.io/librecodecoop/nextcloud-docker-web:stable-34.0.6` |
| stable image tracking one major (moving) | `ghcr.io/librecodecoop/nextcloud-docker-app:stable-34-fpm` |
| development image following upstream `master` (moving) | `ghcr.io/librecodecoop/nextcloud-docker-app:master-fpm` |
| immutable development image | `ghcr.io/librecodecoop/nextcloud-docker-app:master-20261002-fpm` |
| immutable rebuild of an already published identity | `ghcr.io/librecodecoop/nextcloud-docker-app:stable-34.0.6-fpm-r2` |
| another runtime variant (illustrative — `apache` is not published today) | `ghcr.io/librecodecoop/nextcloud-docker-app:stable-34.0.6-apache` |

## Traceability

Every published image must expose enough metadata to be traced back to its
sources, no matter which tag was used to pull it. Metadata is set at build time
and is identical for every tag that points at the same image.

### Standard OCI labels

Use the standard `org.opencontainers.image.*` annotations wherever a standard
label exists:

| Label | Value |
| --- | --- |
| `org.opencontainers.image.source` | source repository: `https://github.com/LibreCodeCoop/nextcloud-docker` |
| `org.opencontainers.image.revision` | source revision: the full git commit of this repository that produced the image |
| `org.opencontainers.image.created` | build date and time (RFC 3339, UTC) |
| `org.opencontainers.image.version` | the Nextcloud version or upstream revision the image was built from: the released version on `stable` (e.g. `34.0.6`), the upstream snapshot identity on `master` (e.g. `master-20261002`) |
| `org.opencontainers.image.base.name` | (recommended) the upstream base image reference |
| `org.opencontainers.image.base.digest` | (recommended) the digest of the upstream base image |

### Project-specific labels

Metadata that has no standard equivalent is recorded under an
`org.librecode.nextcloud.*` prefix, clearly separated from the standard labels:

| Label | Value |
| --- | --- |
| `org.librecode.nextcloud.channel` | `stable` or `master` |
| `org.librecode.nextcloud.php-version` | PHP runtime version embedded in the image (e.g. `8.3`) — for images that embed PHP |
| `org.librecode.nextcloud.variant` | runtime variant of the image (e.g. `fpm`) — for components that have variants |

Labels that do not apply to a component are omitted — for example the web
front-end has no PHP runtime and no variant. Required means: required when the
corresponding fact exists for that image.

Inspect the labels of any published image with:

```bash
docker inspect --format '{{ json .Config.Labels }}' \
  ghcr.io/librecodecoop/nextcloud-docker-app:stable-34.0.6-fpm | jq
```

## Using this convention from consuming environments

* Production and other reproducible environments pin **immutable** tags
  (`app:stable-34.0.6-fpm`, `web:stable-34.0.6`).
* Environments that deliberately want updates use **moving** tags
  (`stable-fpm`, `stable-34-fpm`, `master-fpm`) and accept that the image
  changes without a version bump.
* Development environments that follow Nextcloud Server `master` use the
  `master` channel; they pin `master-<YYYYMMDD>-<variant>` when a dev
  environment must be reproducible, and `master-<variant>` when it should keep
  tracking `master`.
* Environments that need more than the generic runtime extend the image with a
  thin `FROM`, pinned to an immutable tag.

## Relationship to current tags

The registry contains tags published before this convention was written:

| Current tag | What it is today | Status |
| --- | --- | --- |
| `latest` | last stable build published by the current workflow | historical; ambiguous, not part of the convention |
| `sha-<commit>`, `sha-<commit>-<arch>` | per-commit build tags of the current workflow | historical; superseded by immutable revision tags plus image labels |
| `main`, `main-<commit>`, `pr-<n>` | branch/PR build tags from older workflows | historical; not part of the convention |
| `35` | the current version-specific development image | historical; exactly the "development image identified only by a major" pattern this convention forbids |

These tags keep working for existing consumers until a separate migration issue
replaces them; this document does not change, add or remove any published tag.
Inventory of current consumers is tracked separately. Historical tags are
**not** a reason to extend the convention: if an existing image or consumer does
not fit it, record the case and discuss it instead of bending the rules here.
