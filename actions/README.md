# Shared CI building blocks

Org-wide implementation of `IMAGE-TAGGING-AND-PROMOTION-STANDARD.md`
(in `devops-knpdts-argocd-manifests`). One copy here instead of nine
copy-pasted ones in the product repos.

> This repository is **public**. Nothing here may contain secrets, internal
> hostnames or credentials. Callers pass credentials in as inputs/secrets.

## Composite actions

| Action | What it does |
|---|---|
| `actions/next-calver` | Next `YYYY.M.D[.N][-rc.N]` for a train from its git tags. Tags are generated, never typed. |
| `actions/build-image` | Build and push one image with the standard OCI labels, SBOM and SLSA provenance (`mode=min`). Refuses `latest` / `*-latest`. |
| `actions/copy-image` | Registry-to-registry copy **by digest** with a mandatory digest-equality check. Refuses to move an existing tag. |

## Reusable workflows

| Workflow | What it does |
|---|---|
| `.github/workflows/cut-release.yml` | Tag the images CI built for one commit with the train's next CalVer (same digest), create `<train>/v<version>` and a GitHub Release with generated notes and digests. |
| `.github/workflows/promote-to-prod.yml` | Copy a cut release into the client registry by digest, verify, and emit `trains/<train>/release.yaml` + a kustomize `images:` block (tag **and** digest). |
| `.github/workflows/digest-parity.yml` | Scheduled check that every version in the client registry is byte-identical to ours. |

All three read the caller's `.github/release-train.json`:

```json
{
  "train": "momo",
  "tag_prefix": "momo/v",
  "legacy_prefixes": "",
  "ci_tag": "{branch}-{sha8}",
  "images": [
    {
      "name": "knpdts-core-api",
      "source": "ghcr.io/ronford-digital/backend-knpdts-momo-service/knpdts-core-api"
    }
  ]
}
```

- `name` is the image name in the client registry (`<prod-registry>/<name>`).
- `ci_tag` is how CI tags a commit's images; `{branch}` and `{sha8}` are substituted.

## The flow

```
push to develop ──► CI: build ONCE (build-image) ──► ghcr.io/ronford-digital/<svc>:<ci-tag>  ──► UAT
                                                        │  tests, Sonar, Trivy, SBOM, provenance
Cut release (pick the commit running in UAT) ──────────►│  retag same digest: <svc>:2026.10.23
                                                        │  git tag momo/v2026.10.23 + GitHub Release
          ≥ 24h soak, `production` environment approval  │
Promote to prod ───────────────────────────────────────►  ghcr.io/knpdt-sacco/e-ziada-artifacts/<svc>:2026.10.23
                                                           digest verified identical; release.yaml generated
```

## Versioning these actions

Callers pin `@v1`. After a change is merged, move the major tag:

```bash
git tag -f v1 && git push -f origin v1
```

Breaking changes go to `v2`.

## Design notes

- **`provenance: mode=min`.** `mode=max` writes build-arg values into the
  attestation, and the product Dockerfiles receive the NuGet feed credentials as
  build args. That attestation is pushed to the registry and later copied to the
  client registry. Move those credentials to BuildKit `secrets:` mounts before
  raising it to max.
- **skopeo, not crane, for copies.** Both registries are on `ghcr.io` but need
  different credentials. crane keeps one credential per host; skopeo takes one
  auth file per side.
- **`com.ronford.promoted.from` is in `release.yaml`, not an image label.**
  Adding a label to the prod image changes its digest, which would defeat the
  digest-equality proof. The proof is that the two digests are equal. The record
  says where the image came from.
- **The release version is a tag, not the `org.opencontainers.image.version`
  label.** The release is cut after the build, by retagging the same digest.
  The label carries the CI build version, and `release.json` / `release.yaml`
  map the release version to the digest.
- **Cosign signing and Kyverno verification (Phase 5) are not here yet.**
  Keyless signing from a private repo writes the image and repo names to the
  public Rekor transparency log. Decide on keyless vs a KMS key first.
