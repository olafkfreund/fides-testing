# fides-testing

A minimal demo service that exercises the **full [Fides](https://github.com/olafkfreund/fides)
compliance pipeline** end-to-end against the live server, on every push to `main`.

It builds a container, records provenance + evidence for every control type across
all supported frameworks, runs the compliance/change gates, and produces an
auditor-ready package — proving the Fides features work in a real CI/CD flow.

## The pipeline — `.github/workflows/fides-audit.yml`

Triggers: push to `main`, or manual **workflow_dispatch**. In order:

1. **Install Fides CLI** — `go install …/cmd/cli@latest` (fallback: build from source).
2. **Adopt control frameworks** — imports SOC2, ISO27001, NIST-800-53, PCI-DSS, DORA, PSD2, SOX catalogs (idempotent).
3. **Enforce controls in all environments** — `fides control enforce --all-controls --all-environments`, so the portal's Controls coverage reflects the full set (creates an enabled environment policy per control).
4. **Start Trail Run** — creates a trail; the server returns its UUID, captured into `TRAIL_ID` for later steps.
5. **Build Docker Container** + **Register Artifact** (by image digest).
6. **Attest all control evidence** — one attestation per evidence type (junit, trivy, snyk, sbom-cyclonedx, secret-scan, deployment, sast, iac, plus the SARC continuous-controls set).
7. **Gates** — `verify-chain` (tamper evidence) → `assert` (policy `production-release-rules`) → `change-gate` (evidence + risk; HOLD is expected until a human approves in the portal — segregation of duties) → allowlist the artifact for the environment.
8. **Deploy** to K8s dev/uat/prod *(best-effort — see below)*.
9. **Reports** — per-framework audit reports, controls coverage, deployment frequency, and a downloadable **audit package** artifact.

## Required configuration

**Secrets** (repo → Settings → Secrets → Actions):

| Secret | Required | Purpose |
|--------|----------|---------|
| `FIDES_API_TOKEN` | **Yes** | Bearer token authenticating the CLI to the Fides server. Without it every call returns `401`. |

**Env** (set at the top of the workflow): `FIDES_SERVER_URL`, `ORG_ID`, `FLOW_ID`, `ENV_ID`.

## Enabling the two optional steps

These are intentionally **not** wired up (they need environment-specific secrets):

- **Real Kubernetes deploy** — the *Deploy to K8s* and *Update Runtime State snapshot*
  steps are `continue-on-error: true` because this runner has no cluster access
  (`kubectl` → `localhost:8080`). To actually deploy: add AWS OIDC / kubeconfig
  credentials and remove `continue-on-error` from those two steps.
- **Encrypted attestations** — payload encryption is off. The server decrypts on
  receipt, so a CI key that doesn't match the server's yields
  `400 decryption failure`. To enable: set `FIDES_ENCRYPTION_KEY` to the **server's
  actual** key and restore `--encrypt` on the SBOM attestation.

## Run it

Push to `main`, or:

```bash
gh workflow run fides-audit.yml --repo olafkfreund/fides-testing --ref main
```

Watch coverage light up in the portal → **Controls**, and evidence/attestations
under the trail.
