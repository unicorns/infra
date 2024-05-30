// This file is used to generate the GitHub provisioning pipeline

local utils = import '../../common/utils.libsonnet';

local common_init_steps(actions_checkout_options={}) = [
  {
    name: 'Checkout repository',
    uses: 'actions/checkout@0ad4b8fadaa221de15dcec353f45205ec38ea70b',  // v4.1.4
    with: actions_checkout_options,
  },
  {
    // This sets up the docker-container driver, which has more features like registry cache export
    name: 'Set up Docker Buildx',
    uses: 'docker/setup-buildx-action@be3701b2116d2f723573ca9e8cdb4ca85d3cdaf0',  // v3
  },
  {
    name: 'Build the provisioner',
    run: 'docker compose build provisioner',
  },
  {
    name: 'Set up environment variables',
    run: |||
      if [ "${{ github.ref_name }}" = "main" ]; then
        echo 'NO_CONFIRM=true' >> .env
        echo 'BACK_UP_STATE=true' >> .env
      else
        echo 'DRY_RUN=true' >> .env
      fi
    |||,
  },
];

local create_pr_steps = [
  {
    name: 'Create PR if there are changes',
    id: 'create_pr',
    uses: 'peter-evans/create-pull-request@6d6857d36972b65feb161a90e484f2984215f83e',  // v6.0.5
    with: {
      // base is the current branch: https://stackoverflow.com/a/71158878
      base: '${{ github.head_ref || github.ref_name }}',
      // branch is the branch that the PR will be created from
      branch: 'auto-update-${{ github.ref_name || github.ref_name }}',
      title: '[Auto] Update from CI',
      body: |||
        This PR was automatically created by the CI pipeline.

        Workflow: `${{ github.workflow }}`
        Workflow run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}/attempts/${{ github.run_attempt }}
        Source: ${{ github.ref }}
      |||,
      'commit-message': '[Auto] Update from CI',
    },
  },
  {
    name: 'Fail if there are changes',
    'if': '${{ steps.create_pr.outputs.pull-request-number }}',
    run: |||
      echo "Changes are required. Please refer to pull request #${{ steps.create_pr.outputs.pull-request-number }}"
      echo "Pull Request URL - ${{ steps.create_pr.outputs.pull-request-url }}"
      exit 1
    |||,
  },
];

// Reference: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-hashicorp-vault#requesting-the-access-token
local vault_setup_steps = [
  {
    name: 'Set up Vault',
    uses: 'hashicorp/vault-action@d1720f055e0635fd932a1d2a48f87a666a57906c',  // v3.0.0
    with: {
      exportToken: true,
      method: 'jwt',
      url: '${{ vars.VAULT_ADDR }}',
      role: "${{ github.ref_name == 'main' && vars.VAULT_ROLE_RW || vars.VAULT_ROLE_RO }}",
    },
  },
];

// Reference: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-hashicorp-vault#revoking-the-access-token
local vault_cleanup_steps = [
  {
    name: 'Revoke Vault token',
    'if': 'always()',
    run: 'curl -X POST -sv -H "X-Vault-Token: ${{ env.VAULT_TOKEN }}" ${{ vars.VAULT_ADDR }}/v1/auth/token/revoke-self',
  },
];

local merge_rw(a, b) = if a == 'write' || b == 'write' then 'write' else 'read';

local merge_perm_helper(acc, perm) =
  if std.objectHas(acc, perm.k) then
    acc { [perm.k]: merge_rw(acc[perm.k], perm.v) }
  else
    acc { [perm.k]: perm.v };

local merge_perms(perms) =
  std.foldl(merge_perm_helper, perms, {});

local make_provision_job(spec) =
  // Ensure that there are no invalid keys in the spec
  local invalid_keys = std.setDiff(std.objectFields(spec), std.set([
    'name',
    'command',
    'dependencies',
    'create_pr_on_change',
    'requires_vault',
  ]));
  assert std.length(invalid_keys) == 0 : 'Invalid keys in provision job spec: ' + std.toString(invalid_keys);

  local name = spec.name;
  local provisioner_command = spec.command;
  local dependencies = std.set(std.get(spec, 'dependencies', []));
  local create_pr_on_change = std.get(spec, 'create_pr_on_change', false);
  local requires_vault = std.get(spec, 'requires_vault', false);

  local perms = merge_perms(
    (if create_pr_on_change then [{ k: 'pull-requests', v: 'write' }] else [])
    + (if requires_vault then [{ k: 'contents', v: 'read' }, { k: 'id-token', v: 'write' }] else [])
  );

  local vault_setup = if requires_vault then vault_setup_steps else [];
  local vault_cleanup = if requires_vault then vault_cleanup_steps else [];


  {
    [utils.slugify(name)]: {
      needs: std.map(utils.slugify, dependencies),
      'runs-on': 'ubuntu-latest',
      [if perms == {} then null else 'permissions']: perms,
      steps: vault_setup + common_init_steps(
        // This is required because normal GITHUB_TOKEN does not have workflow permissions
        // https://github.com/orgs/community/discussions/35410#discussioncomment-7645702
        // https://github.com/peter-evans/create-pull-request/blob/15410bdb79bc0f69a005c1c860378ed08968f998/docs/concepts-guidelines.md?plain=1#L188
        actions_checkout_options=(if create_pr_on_change then { 'ssh-key': '${{ secrets.DEPLOY_KEY }}' } else {}),
      ) + [
        {
          name: name,
          run: provisioner_command,
        },
      ] + (if create_pr_on_change then create_pr_steps else []) + vault_cleanup,
    },
  };

local wrap_jobs(jobs) = jobs {
  'all-good': {
    needs: std.objectFields(jobs),
    'runs-on': 'ubuntu-latest',
    'if': 'always()',
    steps: [
      {
        'if': "${{ !contains(needs.*.result, 'failure') && !contains(needs.*.result, 'cancelled') }}",
        name: 'Print success message if all jobs are successful',
        run: "echo 'All good!'",
      },
      {
        'if': "${{ contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled') }}",
        name: 'Fail the job if one or more jobs failed',
        run: "echo 'One or more jobs failed.' && exit 1",
      },
    ],
  },
};

function(provision_jobs = []) {
  name: 'Provision',
  on: {
    push: {
      branches: [
        'main',
      ],
    },
    pull_request: {
      branches: [
        'main',
      ],
    },
    merge_group: null,
    workflow_dispatch: null,
  },
  concurrency: 'provision_concurrency_group-${{ github.event.pull_request.number || github.ref_name }}',
  jobs:
    wrap_jobs(
      make_provision_job({
        name: 'Update workflow',
        command: |||
          docker compose run provisioner /bin/bash -c './common/workflow_utils.py --output-format raw generate-provision-workflow .github/workflows/provision.jsonnet | yq --prettyPrint > .github/workflows/provision.yml'
        |||,
        create_pr_on_change: true,
      })
      + std.foldl(
        function(acc, job) acc + make_provision_job(job + {
          // Inject mandatory dependencies
          dependencies: std.get(job, 'dependencies', []) + ['Update workflow'],
        }),
        provision_jobs,
        {},
      ),
    ),
}
