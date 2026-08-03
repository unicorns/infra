# Pigeon platform registration

This stack owns Pigeon's shared-platform registration:

- Azure deployment and workload identities, federated credentials, AKS access,
  the dedicated Key Vault, and Key Vault role assignments;
- the Kubernetes namespace, Pod Security labels, deployment Role, and
  RoleBinding;
- the GitHub `production` environment, deployment branch policies, and
  non-secret environment variables; and
- the `pigeon.benzhang.dev` Cloudflare record.

The import blocks adopt the registration resources created during the initial
bootstrap. Every adopted resource has `prevent_destroy`; a mismatched import
must fail rather than replace a live resource.

The Azure root stack owns the HCP Terraform workspace used for this state and
sets its execution mode to `local`. The Pigeon provisioner verifies that
contract before initialization because its Kubernetes provider requires the
runner-local kubeconfig. Review plans enable refresh so live drift cannot be
deferred to the main-branch auto-apply.

Before CI can plan this stack, add these secrets to `unicorns/infra`:

- `PIGEON_GITHUB_ADMIN_TOKEN`: a fine-grained token restricted to
  `ben-z/pigeon`, with repository **Administration: write**,
  **Environments: write**, and **Actions: read**;
- `CLOUDFLARE_API_TOKEN`: a token restricted to the `benzhang.dev` zone, with
  **Zone: read** and **DNS: edit**.

The GitHub policy validation requires the production environment to contain
exactly `branch:main` and `branch:rollback/*`. Any additional branch or tag
policy fails the apply before the DNS record can be created.

DNS starts behind `pigeon_dns_enabled = false` so importing registration state
cannot cut over traffic. Activate it in a separate reviewed change only after
the Pigeon Deployment, Service, and Ingress are ready.

This stack intentionally does not manage Key Vault secret values or the
`ghcr-pigeon` image pull Secret. Terraform would persist those credentials in
state. A platform operator owns their out-of-band creation and rotation. Before
production acceptance, replace the bootstrap credential with a dedicated GitHub
Packages token carrying only `read:packages`, then prove that a Pigeon image can
be pulled with the rotated Secret.

Pigeon owns its ServiceAccount, SecretProviderClass, PVC, Deployment, Service,
Ingress, image, deployment workflow, rollout verification, and rollback logic.
