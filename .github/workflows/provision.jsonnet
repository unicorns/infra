// This file is used to generate the GitHub provisioning pipeline

local utils = import '../../common/utils.libsonnet';

local common_init_steps = [
  {
    name: 'Checkout repository',
    uses: 'actions/checkout@0ad4b8fadaa221de15dcec353f45205ec38ea70b',
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
    name: 'Test provisioners',
    run: 'docker compose run --rm provisioner python3 -m unittest discover -s tests -v',
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

local make_provision_job(spec) =
  // Ensure that there are no invalid keys in the spec
  local invalid_keys = std.setDiff(std.objectFields(spec), std.set([
    'name',
    'command',
    'dependencies',
    'env',
  ]));
  assert std.length(invalid_keys) == 0 : 'Invalid keys in provision job spec: ' + std.toString(invalid_keys);

  local name = spec.name;
  local provisioner_command = spec.command;
  local dependencies = std.set(std.get(spec, 'dependencies', []));
  local env = std.get(spec, 'env', {});

  {
    [utils.slugify(name)]: {
      needs: std.map(utils.slugify, dependencies),
      'runs-on': 'ubuntu-latest',
      [if env == {} then null else 'env']: env,
      steps: common_init_steps + [
        {
          name: name,
          run: provisioner_command,
        },
      ],
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
  permissions: { contents: 'read' },
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
          git diff --exit-code -- .github/workflows/provision.generated.yml
        |||,
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
