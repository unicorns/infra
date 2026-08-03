// This file is used to generate the GitHub provisioning pipeline

local utils = import '../../common/utils.libsonnet';

local common_init_steps(actions_checkout_options={}) = [
  {
    name: 'Checkout repository',
    uses: 'actions/checkout@0ad4b8fadaa221de15dcec353f45205ec38ea70b',
    with: actions_checkout_options,
  },
  {
    // This sets up the docker-container driver, which has more features like registry cache export
    name: 'Set up Docker Buildx',
    uses: 'docker/setup-buildx-action@be3701b2116d2f723573ca9e8cdb4ca85d3cdaf0',
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
    uses: 'peter-evans/create-pull-request@6d6857d36972b65feb161a90e484f2984215f83e',
    with: {
      // base is the current branch: https://stackoverflow.com/a/71158878
      base: '${{ github.head_ref || github.ref_name }}',
      // branch is the branch that the PR will be created from
      branch: 'auto-update-${{ github.head_ref || github.ref_name }}',
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

local make_provision_job(spec) =
  // Ensure that there are no invalid keys in the spec
  local invalid_keys = std.setDiff(std.objectFields(spec), std.set([
    'name',
    'command',
    'dependencies',
    'create_pr_on_change',
    'env',
  ]));
  assert std.length(invalid_keys) == 0 : 'Invalid keys in provision job spec: ' + std.toString(invalid_keys);

  local name = spec.name;
  local provisioner_command = spec.command;
  local dependencies = std.set(std.get(spec, 'dependencies', []));
  local create_pr_on_change = std.get(spec, 'create_pr_on_change', false);
  local env = std.get(spec, 'env', {});
  local perms = if create_pr_on_change then { 'pull-requests': 'write' } else {};

  {
    [utils.slugify(name)]: {
      needs: std.map(utils.slugify, dependencies),
      'runs-on': 'ubuntu-latest',
      [if env == {} then null else 'env']: env,
      [if perms == {} then null else 'permissions']: perms,
      steps: common_init_steps(
        // This is required because normal GITHUB_TOKEN does not have workflow permissions
        // https://github.com/orgs/community/discussions/35410#discussioncomment-7645702
        // https://github.com/peter-evans/create-pull-request/blob/15410bdb79bc0f69a005c1c860378ed08968f998/docs/concepts-guidelines.md?plain=1#L188
        actions_checkout_options=(if create_pr_on_change then { 'ssh-key': '${{ secrets.DEPLOY_KEY }}' } else {}),
      ) + [
        {
          name: name,
          run: provisioner_command,
        },
      ] + (if create_pr_on_change then create_pr_steps else []),
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
          docker compose run --rm provisioner /bin/bash -c 'set -o pipefail; ./common/workflow_utils.py generate-provision-workflow .github/workflows/provision.jsonnet | yq --prettyPrint > /tmp/provision.generated.yml && mv /tmp/provision.generated.yml .github/workflows/provision.generated.yml'
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
