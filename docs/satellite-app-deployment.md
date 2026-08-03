# Deploy a satellite application

Each application owns its image, Kubernetes manifests, and deployment workflow.
After one-time registration, releases require changes only in the application
repository. Use
[`ben-z/gate-controller`](https://github.com/ben-z/gate-controller/tree/master/deploy)
as the working reference.

## 1. Register the application once

A platform operator creates:

- a dedicated Kubernetes namespace;
- a deployment managed identity federated to
  `repo:<owner>/<repo>:environment:production`;
- the **Azure Kubernetes Service Cluster User Role** for that identity, plus a
  namespace Role and RoleBinding containing only the resources the app deploys;
- a GitHub `production` environment restricted to the default branch and
  `rollback/*`, with the Azure and app variables used by the workflow;
- a DNS record pointing the app hostname at the shared ingress IP; and
- for runtime secrets, a dedicated Key Vault and a separate AKS workload
  identity with only **Key Vault Secrets User** access.

The operator needs these permissions while registering the app:

| System | One-time permission |
| --- | --- |
| Azure | Owner, or Contributor plus User Access Administrator, on the AKS resource group |
| AKS | Cluster administrator, used only to create the namespace and its RBAC |
| GitHub | Repository administrator, to configure the environment, branch policy, and variables |
| DNS | Permission to create the application record |
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

Required non-secret `production` environment variables normally include the
Azure tenant, subscription, resource group, cluster, deployment identity client
ID, app URL, Key Vault name, and workload identity client ID. The workflow's
deploy job must declare `environment: production` so its OIDC subject matches
the federated credential.

## 3. Release and roll back

Normal release: merge to the default branch. Checks pass, the image is
published, and the app deploys and verifies its exact commit automatically.

Rollback: create a temporary `rollback/*` branch at a previously successful
commit, then run the deployment workflow and select that branch under **Use
workflow from**. Delete the branch after the deployment succeeds.

```sh
git push origin <full-sha>:refs/heads/rollback/<name>
git push origin --delete rollback/<name>
```

The selected commit supplies both the application and its deployment strategy.
