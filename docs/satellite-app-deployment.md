# Deploy a satellite application

Each application owns its image, Kubernetes manifests, and deployment workflow.
After one-time registration, releases require changes only in the application
repository. Use
[`ben-z/gate-controller`](https://github.com/ben-z/gate-controller/tree/master/deploy)
as the working reference.

## 1. Register the application once

A platform operator creates:

- a dedicated Kubernetes namespace labeled `unicorns.dev/satellite=true`;
- a deployment managed identity federated to
  `repo:<owner>/<repo>:environment:production`;
- the **Azure Kubernetes Service Cluster User Role** for that identity, plus a
  namespace Role and RoleBinding containing only the resources the app deploys;
- a GitHub `production` environment restricted to the default branch, with
  the Azure and app variables used by the workflow; the public reference app
  additionally permits `rollback/*` for its source-based rollback procedure;
- for a public application, a DNS record pointing its hostname at the public
  shared ingress IP;
- for a private application's CI, a Tailscale federated identity bound to its
  exact production environment and immutable repository and owner IDs; and
- for runtime secrets, a dedicated Key Vault and a separate AKS workload
  identity with only **Key Vault Secrets User** access.

The operator needs these permissions while registering the app:

| System | One-time permission |
| --- | --- |
| Azure | Owner, or Contributor plus User Access Administrator, on the AKS resource group |
| AKS | Cluster administrator, used only to create the namespace and its RBAC |
| GitHub | Repository administrator, to configure the environment, branch policy, and variables |
| DNS | Permission to create a public application record |
| Tailscale | Permission to register a private application's federated CI identity |
| Key Vault | Key Vault Secrets Officer when populating or rotating runtime secrets |

The application workflow itself receives only `contents: read` and
`id-token: write` for deployment. Image jobs additionally receive
`packages: write`. Azure login uses OIDC; do not create an Azure client secret.

For a private image, the platform operator must also grant the namespace
read-only registry access, such as an out-of-band `imagePullSecret`. Do not grant
the deployment workflow permission to write Kubernetes Secrets. Public GHCR
images need no pull credential.

Adapt the reference app's `deploy/bootstrap/` directory, update its repository,
namespace, hostname, and secret names, then run it once:

```sh
az bicep install
./deploy/bootstrap/bootstrap.sh
```

The bootstrap must apply the satellite label with its cluster administrator
credential before handing the namespace to the deployment identity:

```sh
kubectl label namespace <namespace> unicorns.dev/satellite=true --overwrite
```

The shared admission policy requires namespace-local ClusterIP Services and
explicit `public` or `tailnet` Ingress rules for `<namespace>.benzhang.dev`.
Applications use platform TLS and cannot set a default backend, resource
backend, external Service address, or arbitrary ingress annotations.

Public applications use `ingressClassName: public` and a proxied Cloudflare DNS
record pointing to the shared public ingress IP. Cloudflare provides public
HTTPS, and the shared Traefik gateway owns request timeouts. App manifests need
no gateway-specific annotations.

Private applications use `ingressClassName: tailnet`. The shared DNS-only
`*.benzhang.dev` record resolves to the private gateway, and Traefik provides a
trusted wildcard certificate. No application DNS record, certificate Secret,
or DNS publication annotation is needed. An existing exact DNS record overrides
the wildcard; remove it only after private TLS and application checks pass.

Private CI uses the shared `tag:unicorns-private-ci` with an `auth_keys` scope.
Each repository keeps its own exact production federated identity, so it can
be revoked independently. Its deployment job joins Tailscale to verify the
application over the private gateway. The platform owns the shared tag and
gateway policy; application bootstrap does not edit tailnet policy.
The explicit CI grant covers TCP 443 on that gateway. Effective network access
also includes other tailnet rules, which platform bootstrap preserves.

Populate the dedicated Key Vault out of band before the first deployment. The
bootstrap should set only non-secret GitHub environment variables. Remove the
reference bootstrap's source-vault migration block for a new application; it
exists only to hand off the gate controller's legacy secrets.

## 2. Add the deployment contract to the app repository

- Copy and adapt the reference deploy workflow, bootstrap, namespace manifests,
  and deploy script. Change all app names, image paths, hostnames, resource
  requirements, and secret declarations.
- Build an immutable image for the source commit and deploy its digest, not a
  mutable tag.
- Embed the full commit SHA in the image and expose it from an uncached version
  endpoint such as `GET /api/version` returning `{"version":"<sha>"}`.
- Keep the namespace manifests and deploy script in the app repository. Apply
  them with the namespace-scoped identity, wait for rollout, verify the exact
  image digest, then require the version endpoint to equal the source SHA.
- Mount runtime secrets from Key Vault through the workload identity; never
  copy secret values into GitHub variables, workflow logs, or manifests.
- Run checks on pull requests and default-branch pushes. Trigger deployment only
  after the default-branch checks succeed, with `workflow_dispatch` enabled for
  rollback.
- Use the restricted Pod Security settings: non-root user, RuntimeDefault
  seccomp, no privilege escalation, and all Linux capabilities dropped.
- Set `nodeSelector: {unicorns.dev/workload: applications}` on Deployments
  and Jobs. The platform assigns this label only to User application pools,
  allowing the autoscaler to provision them from zero while keeping system
  nodes ineligible. Prefer Spot with node affinity and tolerate
  `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`.

Required non-secret `production` environment variables normally include the
Azure tenant, subscription, resource group, cluster, deployment identity client
ID, app URL, Key Vault name, and workload identity client ID. The workflow's
deploy job must declare `environment: production` so its OIDC subject matches
the federated credential.

## 3. Release and roll back

Normal release: merge to the default branch. Checks pass, the image is
published, and the app deploys and verifies its exact commit automatically.

Private application rollback selects a previously approved image digest through
the protected default-branch workflow and retains the `tailnet` ingress.

For the public reference app, create a temporary `rollback/*` branch at a
previously successful commit, then run the deployment workflow and select that
branch under **Use workflow from**. Delete the branch after deployment succeeds.

```sh
git push origin <full-sha>:refs/heads/rollback/<name>
git push origin --delete rollback/<name>
```

The public reference app's selected commit supplies both the application and
its deployment strategy.
