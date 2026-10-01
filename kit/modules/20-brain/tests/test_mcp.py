import json
import os
import subprocess
import sys


def rpc(proc, mid, method, params=None):
    msg = {"jsonrpc": "2.0", "id": mid, "method": method}
    if params is not None:
        msg["params"] = params
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()
    return json.loads(proc.stdout.readline())


def call(proc, mid, name, args):
    res = rpc(proc, mid, "tools/call", {"name": name, "arguments": args})["result"]
    return res["isError"], res["content"][0]["text"]


def test_mcp_stdio_roundtrip(env):
    proc = subprocess.Popen([sys.executable, "-m", "kitbrain", "mcp"], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            env=os.environ.copy())
    try:
        init = rpc(proc, 1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                           "clientInfo": {"name": "t", "version": "0"}})
        assert init["result"]["protocolVersion"] == "2025-06-18"
        assert init["result"]["serverInfo"]["name"] == "brain"
        proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        tools = {t["name"] for t in rpc(proc, 2, "tools/list")["result"]["tools"]}
        assert tools == {"search", "read", "new_note", "append", "recent"}

        err, text = call(proc, 3, "new_note", {"type": "howto", "title": "Rotate the VPN key",
                                               "body": "## Steps\n1. open the portal"})
        assert not err and json.loads(text)["path"] == "howto/rotate-the-vpn-key.md"
        err, text = call(proc, 4, "append", {"path": "howto/rotate-the-vpn-key.md",
                                             "body": "2. confirm by mail"})
        assert not err
        err, text = call(proc, 5, "search", {"query": "vpn key", "k": 3})
        assert not err and json.loads(text)["results"][0]["title"] == "Rotate the VPN key"
        err, text = call(proc, 6, "read", {"note": "Rotate the VPN key"})
        assert not err and "confirm by mail" in text
        err, text = call(proc, 7, "recent", {"n": 1})
        assert json.loads(text)[0]["path"] == "howto/rotate-the-vpn-key.md"

        err, text = call(proc, 8, "read", {"note": "../../etc/passwd"})
        assert err and "outside" in text
        assert rpc(proc, 9, "tools/call", {"name": "nope"})["error"]["code"] == -32602
        assert rpc(proc, 10, "unknown/method")["error"]["code"] == -32601
        assert rpc(proc, 11, "ping")["result"] == {}
    finally:
        proc.stdin.close()
        assert proc.wait(timeout=10) == 0
