#!/usr/bin/env python3
"""Configure operator federation and private ingress. Run one bootstrap at a time."""

import argparse
import base64
import copy
from dataclasses import dataclass, field
from ipaddress import ip_address
import json
import os
from pathlib import Path
import stat
import subprocess
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen
from uuid import UUID


OPERATOR_TAG = "tag:unicorns-k8s-operator"
PROXY_TAG = "tag:unicorns-private-ingress"
CI_TAG = "tag:unicorns-private-ci"
SERVICE = "svc:unicorns-private"
DESCRIPTION = "Unicorns AKS operator"
SUBJECT = "system:serviceaccount:tailscale:operator"
SCOPES = ["auth_keys", "devices:core", "services"]
DEFAULT_ACL = {"action": "accept", "src": ["*"], "dst": ["*:*"]}


@dataclass(frozen=True)
class Config:
    api_token: str = field(repr=False)
    tailnet: str
    subscription: str
    timeout_seconds: int = 30


def read_token(path):
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW)) as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError("The API token must be a regular file with mode 0600")
        if info.st_uid != os.getuid():
            raise ValueError("The API token file must belong to the current user")
        token = source.read().removesuffix("\n")
    if not token.startswith("tskey-api-") or token == "tskey-api-" or any(c.isspace() for c in token):
        raise ValueError("The token file must contain one Tailscale API access token")
    return token


def command_json(*arguments):
    result = subprocess.run(arguments, check=True, text=True, capture_output=True)
    return json.loads(result.stdout)


def api(config, method, path, body, etag):
    headers = {
        "Authorization": "Basic " + base64.b64encode((config.api_token + ":").encode()).decode(),
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    if etag is not None:
        headers["If-Match"] = etag
    request = Request(
        "https://api.tailscale.com/api/v2" + path,
        data=None if body is None else json.dumps(body).encode(),
        headers=headers,
        method=method,
    )
    with urlopen(request, timeout=config.timeout_seconds) as response:
        payload = response.read()
        return (json.loads(payload) if payload else None), response.headers.get("ETag")


def string_list(value, name):
    if not isinstance(value, list) or any(not isinstance(x, str) for x in value):
        raise ValueError(f"{name} must be an array of strings")
    if len(value) != len(set(value)):
        raise ValueError(f"{name} contains duplicates")
    return set(value)


def policy_fragment(original):
    if not isinstance(original, dict):
        raise ValueError("Tailscale policy response must be an object")
    policy = copy.deepcopy(original)
    for name in ("tagOwners", "autoApprovers"):
        if name not in policy:
            policy[name] = {}
        if not isinstance(policy[name], dict):
            raise ValueError(f"Policy {name} must be an object")
    owners = {
        OPERATOR_TAG: ["autogroup:admin"],
        PROXY_TAG: ["autogroup:admin", OPERATOR_TAG],
        CI_TAG: ["autogroup:admin"],
    }
    for tag, desired in owners.items():
        if tag in policy["tagOwners"]:
            if string_list(policy["tagOwners"][tag], tag) != set(desired):
                raise ValueError(f"Existing ownership of {tag} conflicts with platform ownership")
        else:
            policy["tagOwners"][tag] = desired
    if "acls" in policy:
        if not isinstance(policy["acls"], list):
            raise ValueError("Policy acls must be an array")
        for rule in policy["acls"]:
            if rule == DEFAULT_ACL:
                rule["src"] = ["autogroup:member", "autogroup:shared"] + sorted(
                    tag for tag in policy["tagOwners"] if tag != CI_TAG
                )
    approvers = policy["autoApprovers"]
    if "services" not in approvers:
        approvers["services"] = {}
    if not isinstance(approvers["services"], dict):
        raise ValueError("Policy autoApprovers.services must be an object")
    if SERVICE in approvers["services"]:
        if string_list(approvers["services"][SERVICE], SERVICE) != {PROXY_TAG}:
            raise ValueError(f"Existing auto-approvers for {SERVICE} conflict with platform ownership")
    else:
        approvers["services"][SERVICE] = [PROXY_TAG]

    if "grants" not in policy:
        policy["grants"] = []
    if not isinstance(policy["grants"], list):
        raise ValueError("Policy grants must be an array")
    grant = {"src": ["autogroup:member", CI_TAG], "dst": [SERVICE], "ip": ["tcp:443"]}
    if not any(rule == grant for rule in policy["grants"]):
        policy["grants"].append(grant)
    return policy


def policy_tests(policy, devices, users):
    if not isinstance(users, dict) or not isinstance(users["users"], list):
        raise ValueError("Tailscale user response must contain a users array")
    owners = {}
    for user in users["users"]:
        if user["type"] not in ("member", "shared") or not isinstance(user["loginName"], str):
            raise ValueError("Tailscale returned an invalid user identity")
        if user["loginName"] in owners:
            raise ValueError("Tailscale returned duplicate user identities")
        owners[user["loginName"]] = user["type"]
    sources, addresses = set(), set()
    for device in devices:
        tags = string_list(device["tags"] if "tags" in device else [], "Device tags")
        if not tags.issubset(policy["tagOwners"]):
            raise ValueError("A current device has undeclared tags")
        if CI_TAG in tags:
            if tags != {CI_TAG}:
                raise ValueError("A CI device has additional tags that could grant broader access")
        elif tags:
            sources.update(tags)
        else:
            if device["user"] not in owners:
                raise ValueError("A current untagged device is not owned by a member or shared user")
            sources.add(device["user"])
        for address in string_list(device["addresses"], "Device addresses"):
            parsed = ip_address(address)
            addresses.add(f"[{parsed}]" if parsed.version == 6 else str(parsed))
    if not sources or not addresses:
        raise ValueError("No current device sources or addresses are available for policy tests")
    accepts = [f"{address}:{port}" for address in sorted(addresses) for port in (22, 443)]
    denies = [f"{address}:{port}" for address in sorted(addresses) for port in (22, 80, 443)]
    tests = [{"src": source, "proto": "tcp", "accept": accepts} for source in sorted(sources)]
    tests.append({"src": CI_TAG, "deny": denies})
    return tests


def desired_identity(issuer):
    return {
        "keyType": "federated",
        "description": DESCRIPTION,
        "scopes": list(SCOPES),
        "tags": [OPERATOR_TAG],
        "issuer": issuer,
        "subject": SUBJECT,
        "customClaimRules": {},
    }


def validate_identity(identity, desired):
    if not isinstance(identity, dict):
        raise ValueError("Operator identity response must be an object")
    for name in ("keyType", "description", "issuer", "subject"):
        if identity[name] != desired[name]:
            raise ValueError(f"Existing operator identity has a mismatched {name}")
    if identity.get("invalid") is True or identity.get("revoked"):
        raise ValueError("Operator identity is revoked or expired")
    if "customClaimRules" in identity and identity["customClaimRules"] not in (None, {}):
        raise ValueError("Operator identity has unexpected custom claim rules")
    for name in ("scopes", "tags"):
        if string_list(identity[name], name) != set(desired[name]):
            raise ValueError(f"Operator identity has mismatched {name}")
    if not isinstance(identity["id"], str) or not identity["id"]:
        raise ValueError("Operator identity has no client ID")
    if identity["audience"] != "api.tailscale.com/" + identity["id"]:
        raise ValueError("Operator identity has an unexpected audience")


def operator_identities(config, base, desired):
    listing, _ = api(config, "GET", base + "/keys?all=true", None, None)
    if not isinstance(listing, dict) or "keys" not in listing:
        raise ValueError("Tailscale key listing must contain a keys field")
    keys = listing["keys"]
    if keys is None:
        keys = []
    if not isinstance(keys, list):
        raise ValueError("Tailscale keys must be an array or null")
    matches = []
    for key in keys:
        if key["keyType"] != "federated":
            continue
        identity, _ = api(config, "GET", base + "/keys/" + quote(key["id"], safe=""), None, None)
        if identity["keyType"] != "federated" or identity["id"] != key["id"]:
            raise ValueError("Tailscale key listing and detail disagree")
        if (identity["description"] == DESCRIPTION or OPERATOR_TAG in identity["tags"]
                or (identity["issuer"] == desired["issuer"] and identity["subject"] == SUBJECT)):
            matches.append(identity)
    if len(matches) > 1:
        raise ValueError("Multiple federated identities match the AKS operator")
    if matches:
        validate_identity(matches[0], desired)
    return matches


def reconcile(config):
    subscription = str(UUID(config.subscription))
    local = command_json("tailscale", "status", "--json")
    if local["BackendState"] != "Running" or local["Self"]["Online"] is not True:
        raise ValueError("Local Tailscale must be connected")
    if config.tailnet == "-" or local["CurrentTailnet"]["Name"] != config.tailnet:
        raise ValueError("Target tailnet does not match the connected local Tailscale tailnet")
    base = "/tailnet/" + quote(config.tailnet, safe="")
    devices, _ = api(config, "GET", base + "/devices", None, None)
    if not isinstance(devices, dict) or not isinstance(devices["devices"], list):
        raise ValueError("Tailscale device response must contain a devices array")
    matches = [x for x in devices["devices"] if x["nodeId"] == local["Self"]["ID"]]
    if len(matches) != 1 or matches[0]["name"] != local["Self"]["DNSName"].removesuffix("."):
        raise ValueError("The API target tailnet does not contain the connected local Tailscale device")
    cluster = command_json(
        "az", "aks", "show", "--resource-group", "unicorns-aks-rg",
        "--name", "unicorns-aks", "--subscription", subscription, "--output", "json",
    )
    expected_id = (f"/subscriptions/{subscription}/resourceGroups/unicorns-aks-rg"
                   "/providers/Microsoft.ContainerService/managedClusters/unicorns-aks")
    if cluster["id"].lower() != expected_id.lower() or cluster["name"] != "unicorns-aks":
        raise ValueError("AKS returned a cluster outside the requested subscription and resource group")
    if cluster["oidcIssuerProfile"]["enabled"] is not True:
        raise ValueError("unicorns-aks must have its OIDC issuer enabled")
    issuer = cluster["oidcIssuerProfile"]["issuerUrl"]
    url = urlparse(issuer)
    if url.scheme != "https" or not url.hostname or url.query or url.fragment:
        raise ValueError("AKS returned an invalid HTTPS OIDC issuer")
    desired = desired_identity(issuer)
    original, etag = api(config, "GET", base + "/acl", None, None)
    if not isinstance(etag, str) or not etag:
        raise ValueError("Tailscale policy response is missing its ETag")
    policy = policy_fragment(original)
    users, _ = api(config, "GET", base + "/users?type=all", None, None)
    tests = policy_tests(policy, devices["devices"], users)
    matches = operator_identities(config, base, desired)
    validation_policy = copy.deepcopy(policy)
    if "tests" not in validation_policy:
        validation_policy["tests"] = []
    if not isinstance(validation_policy["tests"], list):
        raise ValueError("Policy tests must be an array")
    validation_policy["tests"].extend(tests)
    validation, _ = api(config, "POST", base + "/acl/validate", validation_policy, None)
    if validation not in (None, {}):
        raise ValueError("Tailscale policy validation returned errors or warnings")
    if policy != original:
        applied, _ = api(config, "POST", base + "/acl", policy, etag)
        if applied != policy:
            raise ValueError("Tailscale did not return the requested policy")
        verified, _ = api(config, "GET", base + "/acl", None, None)
        if verified != policy:
            raise ValueError("Tailscale policy verification failed")
    if matches:
        identity = matches[0]
    else:
        identity, _ = api(config, "POST", base + "/keys", desired, None)
        validate_identity(identity, desired)
    verified = operator_identities(config, base, desired)
    if len(verified) != 1 or verified[0]["id"] != identity["id"]:
        raise ValueError("Operator identity changed during bootstrap")
    identity = verified[0]
    return {"TAILSCALE_CLIENT_ID": identity["id"], "TAILSCALE_AUDIENCE": identity["audience"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-token-file", required=True, type=Path)
    parser.add_argument("--tailnet", required=True)
    parser.add_argument("--subscription", required=True)
    args = parser.parse_args()
    config = Config(read_token(args.api_token_file), args.tailnet, args.subscription)
    print(json.dumps(reconcile(config)))


if __name__ == "__main__":
    main()
