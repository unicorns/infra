// This file is used to generate the GitHub provisioning pipeline

local utils = import '../../common/utils.libsonnet';

local common_init_steps = [
  {
    name: 'Checkout repository',
    uses: 'actions/checkout@0ad4b8fadaa221de15dcec353f45205ec38ea70b',  // v4.1.4
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

local make_provision_job(name, provisioner_command, dependencies=[], create_pr_on_change=false) = {
  [utils.slugify(name)]: {
    needs: std.map(utils.slugify, dependencies),
    'runs-on': 'ubuntu-latest',
    steps: common_init_steps + [
      {
        name: name,
        run: provisioner_command,
      },
    ] + (if create_pr_on_change then create_pr_steps else []),
  },
};

{
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
    make_provision_job(
      'Update workflow',
      |||
        docker compose run provisioner /bin/bash -c 'jrsonnet --exp-preserve-order .github/workflows/provision.jsonnet | yq --prettyPrint > .github/workflows/provision.yml'
      |||,
      create_pr_on_change=true
    )
    + make_provision_job(
      'Dummy test',
      |||
        docker compose run provisioner echo "Dummy test"
      |||,
      dependencies=['Update workflow']
    ),
}
