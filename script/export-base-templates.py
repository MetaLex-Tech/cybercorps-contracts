"""Export every event-discovered template in the canonical Base registry.

Read-only. Python standard library + cast. Run from the repository root. Reads
only RPC_URL_BASE/ALCHEMY_API_KEY from environment or .env; never a signing key.
The output is a pinned, exact-byte input for sync-base-templates.s.sol.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed

REGISTRY = "0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134"
EVENT = "TemplateCreated(bytes32,string,string,string[],string[])"


class RpcError(RuntimeError):
    def __init__(self, code, message="", data=None):
        self.code = code
        self.data = data
        super().__init__("configured Base RPC error " + str(code) + ": " + message)


def cast(*args, stdin=None):
    result = subprocess.run(["cast", *args], input=stdin, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError("cast failed: " + args[0])
    return result.stdout.strip()


def settings():
    allowed = {"RPC_URL_BASE", "BASE_LOGS_RPC_URL", "ALCHEMY_API_KEY", "ETHERSCAN_API_KEY"}
    settings = {k: os.environ[k] for k in allowed if os.environ.get(k)}
    if Path(".env").exists():
        for line in Path(".env").read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                if k.strip() in allowed:
                    settings.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    return settings


def endpoint(config):
    if config.get("RPC_URL_BASE"):
        return config["RPC_URL_BASE"]
    if config.get("ALCHEMY_API_KEY"):
        return "https://base-mainnet.g.alchemy.com/v2/" + config["ALCHEMY_API_KEY"]
    return "https://base-rpc.publicnode.com"


class Client:
    def __init__(self, url):
        self.url = url
        self.request_count = 0

    def read(self, method, params):
        assert method in {"eth_chainId", "eth_blockNumber", "eth_getBlockByNumber", "eth_getCode", "eth_getLogs", "eth_call"}
        payload = json.dumps([{"jsonrpc": "2.0", "id": 1, "method": method, "params": params}]).encode()
        for attempt in range(4):
            req = urllib.request.Request(self.url, payload, {"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"})
            self.request_count += 1
            try:
                with urllib.request.urlopen(req, timeout=45) as response:
                    data = json.load(response)
            except urllib.error.HTTPError as exc:
                if exc.code in {429, 502, 503, 504} and attempt < 3:
                    time.sleep(1 + attempt * 2)
                    continue
                raise RuntimeError("HTTP " + str(exc.code) + " during configured Base RPC read") from None
            except Exception as exc:
                raise RuntimeError(type(exc).__name__ + " during configured Base RPC read") from None
            item = data[0] if isinstance(data, list) and len(data) == 1 else data
            if "error" in item:
                message = str(item["error"].get("message", ""))
                for secret in [self.url, self.url.rsplit("/", 1)[-1]]:
                    if secret:
                        message = message.replace(secret, "<configured RPC>")
                raise RpcError(item["error"]["code"], message[:300], item["error"].get("data"))
            return item["result"]
        raise RuntimeError("configured Base RPC retries exhausted")


def discover(client, first, last, topic):
    """Bisect range-limit failures; never skip a failed interval."""
    try:
        logs = client.read("eth_getLogs", [{"address": REGISTRY, "fromBlock": hex(first), "toBlock": hex(last), "topics": [topic]}])
        if not isinstance(logs, list):
            raise RuntimeError("invalid logs response")
        # Split a potentially capped response instead of accepting truncation.
        if len(logs) < 10_000:
            return logs
    except RpcError as exc:
        # Providers use these codes for response/range limits. A single-block
        # failure is fatal, as are auth/method/rate errors; no partial export.
        if exc.code not in {-32005, -32000, -32011, -32602}:
            raise
    if first == last:
        raise RuntimeError("unable to enumerate complete template logs at block " + str(first))
    middle = (first + last) // 2
    return discover(client, first, middle, topic) + discover(client, middle + 1, last, topic)


def first_deployment_block(client, last):
    # The canonical ERC1967 proxy remains deployed (no selfdestruct/redeployment
    # in this registry's history). Locate its first code, then scan all its logs.
    low, high = 0, last
    while low < high:
        middle = (low + high) // 2
        if client.read("eth_getCode", [REGISTRY, hex(middle)]) == "0x":
            low = middle + 1
        else:
            high = middle
    if low > 0 and client.read("eth_getCode", [REGISTRY, hex(low - 1)]) != "0x":
        raise RuntimeError("unable to establish registry deployment boundary")
    if client.read("eth_getCode", [REGISTRY, hex(low)]) == "0x":
        raise RuntimeError("registry absent at discovered deployment block")
    return low


def chunked_logs(client, first_block, last, topic, block_hash, window):
    # Public RPCs reject unbounded eth_getLogs calls. Each interval is exhaustive
    # and cached under its pinned source block hash for resumable exports.
    cache = Path("out/base-template-export") / block_hash[2:]
    cache.mkdir(parents=True, exist_ok=True)
    intervals = [(first, min(first + window - 1, last)) for first in range(first_block, last + 1, window)]

    def read_interval(interval):
        first, final = interval
        path = cache / (str(first) + "-" + str(final) + ".json")
        if path.exists():
            return json.loads(path.read_text())
        logs = discover(client, first, final, topic)
        path.write_text(json.dumps(logs), encoding="utf-8")
        return logs

    logs = []
    pool = ThreadPoolExecutor(max_workers=4)
    try:
        futures = [pool.submit(read_interval, interval) for interval in intervals]
        for index, future in enumerate(as_completed(futures), 1):
            logs.extend(future.result())
            if index % 100 == 0 or index == len(intervals):
                print("Scanned", index, "/", len(intervals), "log intervals; events:", len(logs), flush=True)
    finally:
        pool.shutdown(wait=True, cancel_futures=True)
    return logs


def explorer_logs(key, last, topic):
    """Etherscan V2 indexed discovery, always pinned and paginated.

    Definitions still come from RPC getters, not explorer-decoded event text.
    Endpoint: https://docs.etherscan.io/api-reference/endpoint/getlogs-address-topics
    """
    logs = []
    page = 1
    while True:
        params = {"chainid": 8453, "module": "logs", "action": "getLogs", "fromBlock": 0,
                  "toBlock": last, "address": REGISTRY, "topic0": topic, "page": page,
                  "offset": 1000, "apikey": key}
        url = "https://api.etherscan.io/v2/api?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        try:
            with urllib.request.urlopen(req, timeout=45) as response:
                result = json.load(response)
        except Exception as error:
            raise RuntimeError(type(error).__name__ + " during configured Etherscan log read") from None
        if result.get("status") == "0" and result.get("message") == "No records found":
            return logs
        if result.get("status") != "1" or not isinstance(result.get("result"), list):
            message = str(result.get("result", "unknown response")).replace(key, "<API key>")
            raise RuntimeError("Etherscan log query failed: " + message[:200])
        chunk = result["result"]
        logs.extend(chunk)
        if len(chunk) < 1000:
            return logs
        page += 1
        time.sleep(0.5)


def decode_details(encoded):
    # cast prints one JSON-compatible value per line for this ABI, preserving
    # string escaping, case and array order without requiring a Python ABI SDK.
    values = cast("abi-decode", "f()(string,string,string[],string[])", encoded).splitlines()
    if len(values) != 4:
        raise RuntimeError("unexpected template ABI decode")
    uri, title, global_fields, party_fields = [json.loads(v) for v in values]
    if not uri or not title or not all(isinstance(x, str) for x in global_fields + party_fields):
        raise RuntimeError("invalid/empty template definition")
    return {"title": title, "legalContractUri": uri, "globalFields": global_fields, "partyFields": party_fields}


def export(block, output, event_source, log_window, event_inventory=None):
    config = settings()
    client = Client(endpoint(config))
    inventory = json.loads(event_inventory.read_text()) if event_inventory else None
    if inventory:
        if inventory.get("sourceChainId") != 8453 or inventory.get("sourceRegistry", "").lower() != REGISTRY.lower():
            raise RuntimeError("invalid source event inventory")
        if block is not None and block != inventory["sourceBlock"]:
            raise RuntimeError("event inventory and requested block differ")
        block = inventory["sourceBlock"]
        event_source = inventory["eventSource"]
    if int(client.read("eth_chainId", []), 16) != 8453:
        raise RuntimeError("source must be Base mainnet (8453)")
    if block is None:
        block = max(0, int(client.read("eth_blockNumber", []), 16) - 12)
    header = client.read("eth_getBlockByNumber", [hex(block), False])
    if not header or client.read("eth_getCode", [REGISTRY, hex(block)]) == "0x":
        raise RuntimeError("source registry absent at requested block")
    topic = cast("keccak", stdin=EVENT)
    first = first_deployment_block(client, block) if event_source == "rpc" else 0
    print("Enumerating Base registry TemplateCreated events from deployment", first, "through", block, flush=True)
    if inventory:
        ids = inventory["templateIds"]
        if len(ids) != len(set(ids)) or inventory["eventCount"] < len(ids):
            raise RuntimeError("invalid/duplicate event inventory IDs")
        for tid in ids:
            if not isinstance(tid, str) or not tid.startswith("0x") or len(bytes.fromhex(tid[2:])) != 32:
                raise RuntimeError("invalid bytes32 template ID")
        logs = []
    elif event_source == "etherscan":
        if not config.get("ETHERSCAN_API_KEY"):
            raise RuntimeError("ETHERSCAN_API_KEY is required for explorer event discovery")
        logs = explorer_logs(config["ETHERSCAN_API_KEY"], block, topic)
    else:
        log_client = Client(config.get("BASE_LOGS_RPC_URL", "https://base-rpc.publicnode.com"))
        if log_client.read("eth_getBlockByNumber", [hex(block), False])["hash"] != header["hash"]:
            raise RuntimeError("log provider disagrees about pinned Base block")
        logs = chunked_logs(log_client, first, block, topic, header["hash"], log_window)
    latest = {tid.lower(): None for tid in inventory["templateIds"]} if inventory else {}
    for log in sorted(logs, key=lambda x: (int(x["blockNumber"], 16), int(x["logIndex"], 16))):
        if log.get("removed") or log["address"].lower() != REGISTRY.lower() or log["topics"][0].lower() != topic.lower():
            raise RuntimeError("unexpected event in template inventory")
        latest[log["topics"][1].lower()] = log
    if not latest:
        raise RuntimeError("empty template inventory; refusing to overwrite manifest")
    selector = cast("sig", "getTemplateDetails(bytes32)")
    templates = []
    for template_id in sorted(latest):
        raw = client.read("eth_call", [{"to": REGISTRY, "data": selector + template_id[2:]}, hex(block)])
        item = {"id": template_id, **decode_details(raw)}
        templates.append(item)
        print(template_id, item["title"], flush=True)
    # Detect a source reorganization during export.
    if client.read("eth_getBlockByNumber", [hex(block), False])["hash"] != header["hash"]:
        raise RuntimeError("source block changed during export; retry")
    manifest = {"schemaVersion": 1, "sourceChainId": 8453, "sourceRegistry": REGISTRY,
                "sourceBlock": block, "sourceBlockHash": header["hash"], "targetChainId": 4663,
                "targetRegistry": REGISTRY, "templateCount": len(templates), "templates": templates,
                "discovery": {"event": EVENT, "fromBlock": first, "toBlock": block, "eventCount": inventory["eventCount"] if inventory else len(logs),
                              "eventSource": event_source, "exportedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                              "lastCreation": {tid: {"block": int(log["blockNumber"], 16), "transactionHash": log["transactionHash"]} for tid, log in latest.items() if log is not None}}}
    if inventory:
        manifest["discovery"].update(inventoryFile=event_inventory.as_posix(),
                                     inventorySha256=hashlib.sha256(event_inventory.read_bytes()).hexdigest(),
                                     sourceUrl=inventory.get("sourceUrl"))
    text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    # Atomic replacement: errors above leave any prior reviewed snapshot intact.
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(output)
    print("Exported", len(templates), "templates from", manifest["discovery"]["eventCount"], "events; RPC requests:", client.request_count)
    print("Manifest:", output, "SHA256:", hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--block", type=int, help="pin an explicit Base block; default latest minus 12")
    parser.add_argument("--output", type=Path, default=Path("script/res/base-templates.json"))
    parser.add_argument("--event-source", choices=["etherscan", "rpc"], default="rpc",
                        help="bounded historical RPC scan by default; Etherscan requires Base API coverage")
    parser.add_argument("--log-window", type=int, default=50_000, help="maximum blocks per RPC log interval")
    parser.add_argument("--event-inventory", type=Path, help="reviewed complete explorer event ID inventory; definitions are re-read from RPC")
    args = parser.parse_args()
    try:
        if args.log_window < 1:
            raise ValueError("log window must be positive")
        export(args.block, args.output, args.event_source, args.log_window, args.event_inventory)
    except (RuntimeError, ValueError, KeyError) as error:
        print("Export failed:", str(error), file=sys.stderr)
        sys.exit(1)
