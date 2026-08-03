import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from azure import provision as azure_provision
from cloudflare import provision as cloudflare_provision
from common.provisioner_utils import (
    ProvisionerTools,
    get_terraform_output,
    run_terragrunt,
)


class AzureProvisionerTests(unittest.TestCase):
    def test_requires_all_azure_credentials(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(
                RuntimeError,
                "ARM_SUBSCRIPTION_ID/AZURE_SUBSCRIPTION_ID",
            ):
                azure_provision.get_tf_vars()

    def test_reads_credentials_and_admin_ids(self):
        environment = {
            "ARM_SUBSCRIPTION_ID": "subscription",
            "ARM_CLIENT_ID": "client",
            "ARM_TENANT_ID": "tenant",
            "ARM_CLIENT_SECRET": "secret",
            "AZURE_AKS_ADMIN_GROUP_OBJECT_IDS": "aks-first, aks-second",
            "AZURE_KEY_VAULT_ADMIN_OBJECT_IDS": "first, second",
        }

        with mock.patch.dict(os.environ, environment, clear=True):
            self.assertEqual(
                azure_provision.get_tf_vars(),
                {
                    "subscription_id": "subscription",
                    "app_client_id": "client",
                    "app_tenant_id": "tenant",
                    "app_client_secret": "secret",
                    "aks_admin_group_object_ids": ["aks-first", "aks-second"],
                    "key_vault_admin_object_ids": ["first", "second"],
                },
            )

    def test_rejects_empty_admin_group_list(self):
        environment = {
            "ARM_SUBSCRIPTION_ID": "subscription",
            "ARM_CLIENT_ID": "client",
            "ARM_TENANT_ID": "tenant",
            "ARM_CLIENT_SECRET": "secret",
            "AZURE_AKS_ADMIN_GROUP_OBJECT_IDS": " , ",
        }

        with mock.patch.dict(os.environ, environment, clear=True):
            with self.assertRaisesRegex(
                RuntimeError,
                "AZURE_AKS_ADMIN_GROUP_OBJECT_IDS",
            ):
                azure_provision.get_tf_vars()

    def test_writes_downstream_outputs(self):
        outputs = {
            "aks_cluster_name": {"value": "cluster"},
            "key_vault_name": {"value": "key-vault"},
            "key_vault_tenant_id": {"value": "tenant"},
            "aks_key_vault_secret_provider_client_id": {"value": "identity"},
            "ingress_static_ip": {"value": "192.0.2.1"},
            "aks_kube_config": {"value": "kubeconfig"},
        }

        with tempfile.TemporaryDirectory() as directory:
            output_directory = Path(directory)
            kubeconfig_path = output_directory / "kubeconfig"
            env_path = output_directory / "azure.env"
            with (
                mock.patch.object(
                    azure_provision,
                    "OUTPUTS_DIR",
                    output_directory,
                ),
                mock.patch.object(
                    azure_provision,
                    "KUBECONFIG_PATH",
                    kubeconfig_path,
                ),
                mock.patch.object(azure_provision, "ENV_PATH", env_path),
            ):
                with mock.patch.object(azure_provision.subprocess, "run") as run:
                    azure_provision.write_stack_outputs(outputs)

                run.assert_called_once_with(
                    [
                        "kubelogin",
                        "convert-kubeconfig",
                        "--kubeconfig",
                        str(kubeconfig_path),
                        "--login",
                        "spn",
                        "--use-azurerm-env-vars",
                    ],
                    check=True,
                )

            self.assertEqual(kubeconfig_path.read_text(), "kubeconfig")
            self.assertEqual(
                stat.S_IMODE(kubeconfig_path.stat().st_mode),
                0o600,
            )
            self.assertEqual(
                (kubeconfig_path.stat().st_uid, kubeconfig_path.stat().st_gid),
                (output_directory.stat().st_uid, output_directory.stat().st_gid),
            )
            self.assertEqual(
                env_path.read_text().splitlines(),
                [
                    "AKS_CLUSTER_NAME=cluster",
                    "INGRESS_EXTERNAL_IP=192.0.2.1",
                    "KUBE_CONFIG_PATH=./outputs/unicorns-aks-kubeconfig",
                ],
            )


class KubernetesProvisionerTests(unittest.TestCase):
    @mock.patch("common.provisioner_utils.run_terragrunt_generic_with_project")
    def test_terragrunt_init_keeps_lock_files_read_only(self, run_command):
        tools = ProvisionerTools(env=mock.sentinel.environment)

        with mock.patch.dict(os.environ, {"DRY_RUN": "1"}, clear=True):
            run_terragrunt(tools, "system")

        self.assertEqual(
            run_command.call_args_list[0].args,
            (
                mock.sentinel.environment,
                "system",
                "init",
                ["-lockfile=readonly"],
            ),
        )


class CloudflareProvisionerTests(unittest.TestCase):
    def test_requires_token_for_state_handoff(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "CLOUDFLARE_API_TOKEN"):
                cloudflare_provision.get_tf_vars()

    def test_reads_token_for_state_handoff(self):
        with mock.patch.dict(
            os.environ,
            {"CLOUDFLARE_API_TOKEN": "token"},
            clear=True,
        ):
            self.assertEqual(
                cloudflare_provision.get_tf_vars(),
                {"cloudflare_api_token": "token"},
            )


class TerraformOutputTests(unittest.TestCase):
    @mock.patch("common.provisioner_utils.run_terraform_generic")
    def test_accepts_one_json_object_after_diagnostics(self, run_command):
        run_command.return_value.stdout = 'diagnostic\n{"value": 1}\n'

        self.assertEqual(
            get_terraform_output(mock.sentinel.environment),
            {"value": 1},
        )

    @mock.patch("common.provisioner_utils.run_terraform_generic")
    def test_rejects_ambiguous_json_objects(self, run_command):
        run_command.return_value.stdout = '{"first": 1}\n{"second": 2}'

        with self.assertRaisesRegex(RuntimeError, "exactly one JSON object"):
            get_terraform_output(mock.sentinel.environment)


if __name__ == "__main__":
    unittest.main()
