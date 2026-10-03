import base64
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError


spec = importlib.util.spec_from_file_location(
    "bootstrap_private_ingress",
    Path(__file__).resolve().parents[1] / "kubernetes-shared/bootstrap-private-ingress.py",
)
bootstrap = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = bootstrap
spec.loader.exec_module(bootstrap)


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.config = bootstrap.Config("tskey-api-private-test-token", "unicorns.org.github",
                                       "da091416-7245-487a-a165-deb1cb35397e")
        self.local = {
            "BackendState": "Running",
            "CurrentTailnet": {"Name": self.config.tailnet},
            "Self": {"ID": "local-node", "DNSName": "laptop.test.ts.net.", "Online": True},
        }
        self.cluster = {
            "name": "unicorns-aks",
            "id": f"/subscriptions/{self.config.subscription}/resourceGroups/unicorns-aks-rg/providers/Microsoft.ContainerService/managedClusters/unicorns-aks",
            "oidcIssuerProfile": {"enabled": True, "issuerUrl": "https://westus3.oic.prod-aks.azure.com/tenant/cluster/"},
        }
        self.original = {
            "groups": {"group:team": ["ben-z@github"]},
            "acls": [copy.deepcopy(bootstrap.DEFAULT_ACL),
                     {"action":"accept", "src":["ben-z@github"], "dst":["*:*"]}],
            "grants": [{"src":["tag:other"], "dst":["tag:database"], "ip":["tcp:5432"]}],
            "tagOwners": {"tag:other": ["ben-z@github"]},
            "autoApprovers": {"routes":{"10.0.0.0/24":["tag:other"]}, "services":{"svc:other":["tag:other"]}},
            "ssh": [{"action":"accept", "src":["autogroup:member"], "dst":["autogroup:self"], "users":["autogroup:nonroot"]}],
            "nodeAttrs": [{"target":["tag:other"], "attr":["funnel"]}],
        }
        self.policy = copy.deepcopy(self.original)
        self.etag = '"policy-version"'
        self.keys = {}
        self.writes = []
        self.validation = {}
        self.validated_policies = []
        self.devices = [
            {"nodeId":"local-node", "name":"laptop.test.ts.net", "user":"ben-z@github",
             "addresses":["100.64.0.1", "fd7a:115c:a1e0::1"]},
            {"nodeId":"machine-node", "name":"machine.test.ts.net", "user":"ben-z@github",
             "tags":["tag:other"], "addresses":["100.64.0.2"]},
        ]
        self.users = {"users":[{"loginName":"ben-z@github", "type":"member"}]}
        self.identity = {
            **bootstrap.desired_identity(self.cluster["oidcIssuerProfile"]["issuerUrl"]),
            "id": "operator-client", "audience": "api.tailscale.com/operator-client",
        }
        for mock in (
            patch.object(bootstrap, "command_json", side_effect=self.command),
            patch.object(bootstrap, "api", side_effect=self.api),
        ):
            mock.start()
            self.addCleanup(mock.stop)

    def command(self, *arguments):
        if arguments == ("tailscale", "status", "--json"):
            return copy.deepcopy(self.local)
        self.assertEqual(arguments, ("az", "aks", "show", "--resource-group", "unicorns-aks-rg",
                                     "--name", "unicorns-aks", "--subscription", self.config.subscription,
                                     "--output", "json"))
        return copy.deepcopy(self.cluster)

    def api(self, config, method, path, body, etag):
        self.assertEqual(config, self.config)
        self.assertTrue(path.startswith("/tailnet/unicorns.org.github/"))
        if method == "GET" and path.endswith("/devices"):
            return {"devices":copy.deepcopy(self.devices)}, None
        if method == "GET" and path.endswith("/users?type=all"):
            return copy.deepcopy(self.users), None
        if method == "GET" and path.endswith("/acl"):
            return copy.deepcopy(self.policy), self.etag
        if method == "GET" and path.endswith("/keys?all=true"):
            return {"keys":[{"id":key,"keyType":value["keyType"]} for key,value in self.keys.items()]}, None
        if method == "GET" and "/keys/" in path:
            return copy.deepcopy(self.keys[path.rsplit("/",1)[1]]), None
        if method == "POST" and path.endswith("/acl/validate"):
            self.validated_policies.append(copy.deepcopy(body))
            return self.validation, None
        self.writes.append((method,path,copy.deepcopy(body),etag))
        if path.endswith("/acl"):
            self.assertEqual(etag,self.etag)
            self.policy = copy.deepcopy(body)
            return copy.deepcopy(self.policy), self.etag
        self.assertEqual((method,path.rsplit("/",1)[1]),("POST","keys"))
        self.keys[self.identity["id"]] = copy.deepcopy(self.identity)
        return copy.deepcopy(self.identity), None

    def test_creates_exact_operator_and_preserves_unrelated_policy(self):
        result = bootstrap.reconcile(self.config)
        self.assertEqual(result,{"TAILSCALE_CLIENT_ID":"operator-client","TAILSCALE_AUDIENCE":"api.tailscale.com/operator-client"})
        self.assertEqual(len(self.writes),2)
        self.assertEqual(self.writes[0][1],"/tailnet/unicorns.org.github/acl")
        self.assertEqual(self.writes[0][3],self.etag)
        identity = self.writes[1][2]
        self.assertEqual(identity["subject"],bootstrap.SUBJECT)
        self.assertEqual(identity["issuer"],self.cluster["oidcIssuerProfile"]["issuerUrl"])
        self.assertEqual(identity["scopes"],["auth_keys","devices:core","services"])
        self.assertEqual(identity["tags"],[bootstrap.OPERATOR_TAG])
        self.assertNotIn("audience",identity)
        for name in ("groups","ssh","nodeAttrs"):
            self.assertEqual(self.policy[name],self.original[name])
        self.assertEqual(self.policy["acls"][1:],self.original["acls"][1:])
        self.assertEqual(self.policy["acls"][0],{
            "action":"accept", "dst":["*:*"],
            "src":["autogroup:member","autogroup:shared", "tag:other",
                   bootstrap.OPERATOR_TAG, bootstrap.PROXY_TAG],
        })
        self.assertEqual(self.policy["grants"][0],self.original["grants"][0])
        self.assertEqual(self.policy["autoApprovers"]["routes"],self.original["autoApprovers"]["routes"])
        self.assertEqual(self.policy["autoApprovers"]["services"]["svc:other"],["tag:other"])
        self.assertEqual(self.policy["autoApprovers"]["services"][bootstrap.SERVICE],[bootstrap.PROXY_TAG])
        self.assertEqual(self.policy["tagOwners"][bootstrap.CI_TAG],["autogroup:admin"])
        self.assertEqual(self.policy["tagOwners"][bootstrap.PROXY_TAG],["autogroup:admin",bootstrap.OPERATOR_TAG])
        self.assertNotIn(self.config.api_token,repr(self.config))
        self.assertNotIn(self.config.api_token,json.dumps(result))

    def test_second_run_is_idempotent(self):
        bootstrap.reconcile(self.config)
        self.writes.clear()
        bootstrap.reconcile(self.config)
        self.assertEqual(self.writes,[])

    def test_conflicting_owners_and_auto_approvers_fail_without_writes(self):
        for update in (lambda: self.policy["tagOwners"].update({bootstrap.CI_TAG:["autogroup:member"]}),
                       lambda: self.policy["autoApprovers"]["services"].update({bootstrap.SERVICE:["tag:other"]})):
            with self.subTest(update=update):
                self.policy = copy.deepcopy(self.original)
                update()
                with self.assertRaisesRegex(ValueError,"conflict"):
                    bootstrap.reconcile(self.config)
                self.assertEqual(self.writes,[])

    def test_changes_only_exact_default_rule_and_adds_a_scoped_grant(self):
        self.policy["acls"].append({**bootstrap.DEFAULT_ACL,"proto":"udp"})
        before = copy.deepcopy(self.policy)
        bootstrap.reconcile(self.config)
        self.assertEqual(self.policy["acls"][1:],before["acls"][1:])
        self.assertNotIn(bootstrap.CI_TAG,self.policy["acls"][0]["src"])
        self.assertEqual(self.policy["grants"][:-1],before["grants"])
        self.assertEqual(self.policy["grants"][-1],{
            "src":["autogroup:member",bootstrap.CI_TAG],"dst":[bootstrap.SERVICE],"ip":["tcp:443"],
        })

    def test_api_tests_cover_current_members_tags_and_both_address_families(self):
        existing_test = {"src":"ben-z@github","accept":["tag:other:22"]}
        self.policy["tests"] = [existing_test]
        bootstrap.reconcile(self.config)
        checks = self.validated_policies[0]["tests"]
        self.assertEqual(checks[0],existing_test)
        self.assertEqual({check["src"] for check in checks[1:]},
                         {"ben-z@github","tag:other",bootstrap.CI_TAG})
        for check in checks[1:-1]:
            self.assertEqual(check["proto"],"tcp")
            self.assertEqual(set(check["accept"]),{
                "100.64.0.1:22","100.64.0.1:443","100.64.0.2:22","100.64.0.2:443",
                "[fd7a:115c:a1e0::1]:22","[fd7a:115c:a1e0::1]:443",
            })
        self.assertEqual(checks[-1]["src"],bootstrap.CI_TAG)
        self.assertNotIn("proto",checks[-1])
        self.assertEqual(set(checks[-1]["deny"]),{
            f"{address}:{port}" for address in ("100.64.0.1","100.64.0.2","[fd7a:115c:a1e0::1]")
            for port in (22,80,443)
        })
        self.assertEqual(self.policy["tests"],[existing_test])

    def test_unknown_device_owners_tags_and_mixed_ci_tags_prevent_writes(self):
        original = copy.deepcopy(self.devices)
        for update in ({"user":"outsider@example.com"}, {"tags":["tag:undeclared"]},
                       {"tags":[bootstrap.CI_TAG,"tag:other"]}, {"addresses":["not-an-ip"]}):
            with self.subTest(update=update):
                self.devices = copy.deepcopy(original)
                self.devices[0].update(update)
                with self.assertRaises(ValueError):
                    bootstrap.reconcile(self.config)
                self.assertEqual(self.writes,[])

    def test_shared_owner_is_covered_and_ci_devices_do_not_receive_broad_access(self):
        self.devices[0]["user"] = "guest@example.com"
        self.users["users"].append({"loginName":"guest@example.com","type":"shared"})
        self.devices.append({"nodeId":"ci-node","name":"ci.test.ts.net", "user":"ben-z@github",
                             "tags":[bootstrap.CI_TAG],"addresses":["100.64.0.3"]})
        bootstrap.reconcile(self.config)
        checks = self.validated_policies[0]["tests"]
        self.assertIn("guest@example.com",{check["src"] for check in checks})
        self.assertEqual([check["src"] for check in checks if "accept" in check],
                         ["guest@example.com","tag:other"])
        self.assertIn("100.64.0.3:443",checks[-1]["deny"])

    def test_duplicate_or_mismatched_operator_identity_fails_before_policy_write(self):
        for name,value in (("issuer","https://other.example"),("subject","system:serviceaccount:tailscale:*"),
                           ("scopes",["all"]),("tags",["tag:other"]),("audience","shared-audience"),
                           ("customClaimRules",{"other":"claim"}),("invalid",True)):
            with self.subTest(name=name):
                self.keys = {"operator-client":{**self.identity,name:value}}
                with self.assertRaises(ValueError):
                    bootstrap.reconcile(self.config)
                self.assertEqual(self.writes,[])
        self.keys = {"operator-client":copy.deepcopy(self.identity),"duplicate":{**self.identity,"id":"duplicate","audience":"api.tailscale.com/duplicate"}}
        with self.assertRaisesRegex(ValueError,"Multiple"):
            bootstrap.reconcile(self.config)
        self.assertEqual(self.writes,[])

    def test_wrong_local_tailnet_or_api_device_prevents_writes(self):
        self.local["CurrentTailnet"]["Name"] = "other.example"
        with self.assertRaisesRegex(ValueError,"Target tailnet"):
            bootstrap.reconcile(self.config)
        self.assertEqual(self.writes,[])
        self.local["CurrentTailnet"]["Name"] = self.config.tailnet
        self.local["Self"]["ID"] = "different-node"
        with self.assertRaisesRegex(ValueError,"API target tailnet"):
            bootstrap.reconcile(self.config)
        self.assertEqual(self.writes,[])

    def test_missing_etag_and_validation_errors_fail_before_writes(self):
        self.etag = None
        with self.assertRaisesRegex(ValueError,"ETag"):
            bootstrap.reconcile(self.config)
        self.etag = '"policy-version"'
        self.validation = {"message":"test(s) failed","data":[{"errors":["denied"]}]}
        with self.assertRaisesRegex(ValueError,"validation"):
            bootstrap.reconcile(self.config)
        self.assertEqual(self.writes,[])

    def test_http_failures_are_not_retried_or_hidden(self):
        for status in (403,412):
            with self.subTest(status=status), patch.object(bootstrap,"api",side_effect=HTTPError("https://api.tailscale.com/api/v2/tailnet/unicorns.org.github/acl",status,"Rejected",{},None)) as api:
                with self.assertRaises(HTTPError) as error:
                    bootstrap.reconcile(self.config)
                self.assertEqual(error.exception.code,status)
                self.assertEqual(api.call_count,1)
        self.assertEqual(self.writes,[])

    def test_midflight_policy_change_stops_before_identity_creation(self):
        original = self.api
        attempts = []
        def conflict(config,method,path,body,etag):
            if method == "POST" and path.endswith("/acl"):
                attempts.append((path,etag))
                raise HTTPError("https://api.tailscale.com/api/v2"+path,412,"Policy changed",{},None)
            return original(config,method,path,body,etag)
        with patch.object(bootstrap,"api",side_effect=conflict):
            with self.assertRaises(HTTPError) as error:
                bootstrap.reconcile(self.config)
        self.assertEqual(error.exception.code,412)
        self.assertEqual(attempts,[("/tailnet/unicorns.org.github/acl",self.etag)])
        self.assertEqual(self.writes,[])
        self.assertEqual(self.keys,{})

    def test_concurrent_duplicate_identity_is_detected_before_success(self):
        original = self.api
        def concurrent(config,method,path,body,etag):
            result = original(config,method,path,body,etag)
            if method == "POST" and path.endswith("/keys"):
                self.keys["concurrent-client"] = {
                    **self.identity,"id":"concurrent-client","audience":"api.tailscale.com/concurrent-client",
                }
            return result
        with patch.object(bootstrap,"api",side_effect=concurrent):
            with self.assertRaisesRegex(ValueError,"Multiple"):
                bootstrap.reconcile(self.config)
        self.assertEqual(len(self.writes),2)

    def test_wrong_subscription_cluster_is_rejected(self):
        self.cluster["id"] = self.cluster["id"].replace(self.config.subscription,
                                                       "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        with self.assertRaisesRegex(ValueError,"subscription"):
            bootstrap.reconcile(self.config)
        self.assertEqual(self.writes,[])

    def test_malformed_key_listing_fails_before_writes(self):
        original = self.api
        for listing in ({},{"keys":{}},{"keys":[{"id":"missing-type"}]}):
            def malformed(config,method,path,body,etag):
                if path.endswith("/keys?all=true"):
                    return listing,None
                return original(config,method,path,body,etag)
            with self.subTest(listing=listing),patch.object(bootstrap,"api",side_effect=malformed):
                with self.assertRaises((ValueError,KeyError)):
                    bootstrap.reconcile(self.config)
                self.assertEqual(self.writes,[])


class TransportTests(unittest.TestCase):
    def test_private_token_file_is_required(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"token"
            path.write_text("tskey-api-test-token\n")
            path.chmod(0o600)
            self.assertEqual(bootstrap.read_token(path),"tskey-api-test-token")
            path.chmod(0o644)
            with self.assertRaisesRegex(ValueError,"0600"):
                bootstrap.read_token(path)
            path.chmod(0o600)
            path.write_text("tskey-client-not-an-api-token")
            with self.assertRaisesRegex(ValueError,"API access token"):
                bootstrap.read_token(path)
            link = Path(directory)/"link"
            link.symlink_to(path)
            with self.assertRaises(OSError):
                bootstrap.read_token(link)

    def test_basic_auth_json_accept_and_if_match(self):
        response = io.BytesIO(b'{"grants":[]}')
        response.headers = {"ETag":'"new-version"'}
        config = bootstrap.Config("tskey-api-test-token","unicorns.org.github",
                                  "da091416-7245-487a-a165-deb1cb35397e")
        with patch.object(bootstrap,"urlopen",return_value=response) as send:
            result,etag = bootstrap.api(config,"POST","/tailnet/unicorns.org.github/acl",{"grants":[]},'"old-version"')
        request = send.call_args.args[0]
        self.assertEqual(request.get_header("Accept"),"application/json")
        self.assertEqual(request.get_header("If-match"),'"old-version"')
        self.assertEqual(base64.b64decode(request.get_header("Authorization").removeprefix("Basic ")).decode(),config.api_token+":")
        self.assertEqual(json.loads(request.data),{"grants":[]})
        self.assertEqual(result,{"grants":[]})
        self.assertEqual(etag,'"new-version"')


if __name__ == "__main__":
    unittest.main()
