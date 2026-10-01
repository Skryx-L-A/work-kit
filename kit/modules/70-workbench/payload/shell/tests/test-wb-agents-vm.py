#!/usr/bin/env python3
"""Hermetic tests for the Lima VM carrier; no VM, network, or live config."""

from __future__ import annotations

import json
import importlib.machinery
import importlib.util
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
sys.path.insert(0, str(SHELL))
import agents_vm as av


class FakeLima:
    def __init__(self, lima_home: Path) -> None:
        self.lima_home = lima_home
        self.instances: dict[str, dict] = {}
        self.machine_ids: dict[str, str] = {}
        self.boot_ids: dict[str, str] = {}
        self.calls: list[dict] = []
        self.controller_response = {"ok": True, "value": "accepted"}
        self.raw_controller_response = None
        self.lose_controller_ack = False
        self.bad_ports = False
        self.lose_list_ack = False

    def add_instance(self, name: str, status: str = "Stopped") -> dict:
        directory = self.lima_home / name
        directory.mkdir(parents=True, exist_ok=True)
        info = {
            "name": name,
            "status": status,
            "dir": str(directory),
            "vmType": "vz",
            "arch": "aarch64",
            "cpus": 2,
            "memory": 2 * 1024 ** 3,
            "disk": 8 * 1024 ** 3,
            "sshAddress": "127.0.0.1",
            "config": {
                "plain": True,
                "mounts": [],
                "portForwards": ([{"guestPort": 80}] if self.bad_ports else []),
                "ssh": {"forwardAgent": False, "overVsock": True},
                "containerd": {"system": False, "user": False},
            },
        }
        self.instances[name] = info
        self.machine_ids[name] = "machine-0123456789abcdef"
        self.boot_ids[name] = "boot-0123456789abcdef"
        return info

    def __call__(self, command, *, input, text, stdout, stderr, timeout, env, check):
        self.calls.append({"command": list(command), "input": input, "timeout": timeout,
                           "lima_home": env.get("LIMA_HOME")})
        operation = command[1]
        if operation == "validate":
            return subprocess.CompletedProcess(command, 0, "", "")
        if operation == "list":
            if self.lose_list_ack:
                raise subprocess.TimeoutExpired(command, timeout)
            output = "\n".join(json.dumps(value) for value in self.instances.values())
            return subprocess.CompletedProcess(command, 0, output + ("\n" if output else ""), "")
        if operation == "create":
            name = next(part.split("=", 1)[1] for part in command if part.startswith("--name="))
            if name in self.instances:
                return subprocess.CompletedProcess(command, 1, "", "already exists")
            self.add_instance(name)
            return subprocess.CompletedProcess(command, 0, "", "")
        if operation == "start":
            name = command[-1]
            self.instances[name]["status"] = "Running"
            return subprocess.CompletedProcess(command, 0, "", "")
        if operation == "stop":
            name = command[-1]
            self.instances[name]["status"] = "Stopped"
            return subprocess.CompletedProcess(command, 0, "", "")
        if operation == "shell":
            name = command[2]
            guest_command = command[command.index("--") + 1:]
            if guest_command == ["/bin/cat", "/etc/machine-id",
                                  "/proc/sys/kernel/random/boot_id"]:
                output = self.machine_ids[name] + "\n" + self.boot_ids[name] + "\n"
                return subprocess.CompletedProcess(command, 0, output, "")
            if guest_command == ["/usr/bin/sudo", "--non-interactive", av.GUEST_CONTROLLER]:
                if self.lose_controller_ack:
                    raise subprocess.TimeoutExpired(command, timeout)
                request = json.loads(input)
                response = self.raw_controller_response or {
                    "request": request, "state": "done", "result": self.controller_response,
                }
                return subprocess.CompletedProcess(command, 0,
                                                   json.dumps(response), "")
        raise AssertionError("unexpected fake Lima call: %r" % (command,))


class LimaVMAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="agents-vm-test-")
        self.root = Path(self.temp.name)
        self.lima_home = self.root / "lima"
        self.state_root = self.root / "state"
        self.fake = FakeLima(self.lima_home)
        self.adapter = av.LimaVMAdapter(
            lima_home=self.lima_home,
            state_root=self.state_root,
            runner=self.fake,
            create_timeout=2,
            start_timeout=2,
            stop_timeout=2,
            exec_timeout=2,
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def commands(self, operation: str) -> list[dict]:
        return [call for call in self.fake.calls if call["command"][1] == operation]

    def test_deterministic_mapping_atomic_registration_and_boot_tracking(self):
        world = "welt-alpha"
        self.assertEqual(av.instance_name(world), av.instance_name(world))
        self.assertNotEqual(av.instance_name(world), av.instance_name("welt-beta"))

        started = self.adapter.start(world)
        self.assertEqual(started["state"], "running")
        name = av.instance_name(world)
        record_path = self.adapter._record_path(world)
        record = json.loads(record_path.read_text(encoding="utf-8"))
        marker = json.loads((self.lima_home / name / ".wb-agents-vm-owner.json").read_text())
        self.assertEqual(record["phase"], "owned")
        self.assertEqual(record["desired_state"], "running")
        self.assertEqual(record["observed_state"], "running")
        self.assertEqual(record["ownership_token"], marker["ownership_token"])
        self.assertEqual(stat.S_IMODE(record_path.stat().st_mode), 0o600)
        self.assertFalse(list(record_path.parent.glob(".*.tmp*")))

        self.fake.boot_ids[name] = "boot-fedcba9876543210"
        current = self.adapter.status(world)
        self.assertEqual(current["state"], "running")
        self.assertTrue(current["boot_changed"])
        updated = json.loads(record_path.read_text(encoding="utf-8"))
        self.assertEqual(updated["previous_boot_id"], "boot-0123456789abcdef")
        self.assertEqual(updated["last_boot_id"], "boot-fedcba9876543210")

        stopped = self.adapter.stop(world)
        self.assertEqual(stopped["state"], "stopped")
        stopped_record = json.loads(record_path.read_text(encoding="utf-8"))
        self.assertEqual(stopped_record["desired_state"], "stopped")
        self.assertEqual(stopped_record["observed_state"], "stopped")
        self.assertEqual(stopped_record["stop_snapshot"]["boot_id"], "boot-fedcba9876543210")

    def test_status_never_starts_and_foreign_instance_is_never_adopted_or_stopped(self):
        world = "welt-foreign"
        absent = self.adapter.status(world)
        self.assertEqual(absent["state"], "absent")
        self.assertFalse(self.commands("start"))

        name = av.instance_name(world)
        self.fake.add_instance(name, "Running")
        self.assertEqual(self.adapter.status(world)["state"], "foreign")
        self.assertEqual(self.adapter.start(world)["state"], "foreign")
        self.assertEqual(self.adapter.stop(world)["state"], "foreign")
        self.assertFalse(self.commands("create"))
        self.assertFalse(self.commands("stop"))
        self.assertFalse(self.adapter._record_path(world).exists())

    def test_connection_loss_is_unknown_and_status_never_converts_it_to_absent(self):
        self.fake.lose_list_ack = True
        result = self.adapter.status("welt-unreachable")
        self.assertEqual(result["state"], "unknown")
        self.assertFalse(self.commands("start"))

    def test_changed_guest_identity_blocks_status_and_stop(self):
        world = "welt-replaced"
        self.assertEqual(self.adapter.start(world)["state"], "running")
        name = av.instance_name(world)
        self.fake.machine_ids[name] = "machine-fedcba9876543210"
        self.assertEqual(self.adapter.status(world)["state"], "foreign")
        stop_calls_before = len(self.commands("stop"))
        self.assertEqual(self.adapter.stop(world)["state"], "foreign")
        self.assertEqual(len(self.commands("stop")), stop_calls_before)

    def test_effective_port_forward_violation_never_reaches_start(self):
        world = "welt-bad-config"
        self.fake.bad_ports = True
        result = self.adapter.start(world)
        self.assertEqual(result["state"], "foreign")
        self.assertFalse(self.commands("start"))

    def test_controller_uses_fixed_argv_json_stdin_and_no_shell_string(self):
        world = "welt-controller"
        self.assertEqual(self.adapter.start(world)["state"], "running")
        request = {"host": av.instance_name(world), "world": world,
                   "request_id": "req-1", "op": "status", "agent": "dummy", "run": None}
        result = self.adapter.execute_controller(world, request)
        self.assertEqual(result["state"], "ok")
        controller_call = [call for call in self.commands("shell")
                           if av.GUEST_CONTROLLER in call["command"]][-1]
        self.assertEqual(
            controller_call["command"][-4:],
            ["--", "/usr/bin/sudo", "--non-interactive", av.GUEST_CONTROLLER],
        )
        self.assertNotIn("/bin/sh", controller_call["command"])
        self.assertNotIn("-c", controller_call["command"])
        self.assertEqual(json.loads(controller_call["input"]), request)
        again = self.adapter.execute_controller(world, request)
        self.assertEqual(again["state"], "ok")
        self.assertTrue(again["replayed"])
        controller_calls = [call for call in self.commands("shell")
                            if av.GUEST_CONTROLLER in call["command"]]
        self.assertEqual(len(controller_calls), 1)

    def test_controller_rejects_foreign_world_and_unbound_success(self):
        world = "welt-bound"
        self.assertEqual(self.adapter.start(world)["state"], "running")
        request = {"host": av.instance_name(world), "world": "welt-other",
                   "request_id": "req-world", "op": "status", "agent": "dummy", "run": None}
        with self.assertRaises(av.VMError):
            self.adapter.execute_controller(world, request)
        self.assertFalse([call for call in self.commands("shell")
                          if av.GUEST_CONTROLLER in call["command"]])

        request = {"host": av.instance_name(world), "world": world,
                   "request_id": "req-unbound", "op": "status", "agent": "dummy", "run": None}
        self.fake.raw_controller_response = {"ok": True}
        result = self.adapter.execute_controller(world, request)
        self.assertEqual(result["state"], "unknown")
        self.assertFalse(result["retry"])
        self.fake.raw_controller_response = None
        repeated = self.adapter.execute_controller(world, request)
        self.assertEqual(repeated["state"], "unknown")
        self.assertEqual(len([call for call in self.commands("shell")
                              if av.GUEST_CONTROLLER in call["command"]]), 1)

    @unittest.skipUnless((SHELL / "messungen" / "agents-vm").is_dir(), "kit: shell/messungen (measurements of the build machine) is not shipped (port/strip.txt)")
    def test_guest_wrapper_translates_only_request_id_and_rebinds_response(self):
        path = SHELL / "messungen/agents-vm/guest-controller"
        loader = importlib.machinery.SourceFileLoader("vm_guest_controller_test", str(path))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        request = {"host": "host", "world": "world", "request_id": "request",
                   "op": "start", "agent": "dummy", "run": "run"}
        remote = module.vm_to_remote_request(request)
        self.assertEqual(remote, {"host": "host", "world": "world", "id": "request",
                                  "op": "start", "agent": "dummy", "run": "run"})
        response = module.remote_to_vm_response(
            {"request": remote, "state": "done", "result": {"observed_state": "running"}},
            remote, request,
        )
        self.assertEqual(response["request"], request)
        with self.assertRaises(ValueError):
            module.remote_to_vm_response(
                {"request": {**remote, "world": "other"}, "state": "done", "result": {}},
                remote, request,
            )

    def test_lost_controller_acknowledgement_is_unknown_and_never_retried(self):
        world = "welt-lost-ack"
        self.assertEqual(self.adapter.start(world)["state"], "running")
        self.fake.lose_controller_ack = True
        result = self.adapter.execute_controller(
            world, {"host": av.instance_name(world), "world": world,
                    "request_id": "req-once", "op": "start", "agent": "dummy", "run": "run-once"},
        )
        self.assertEqual(result["state"], "unknown")
        self.assertFalse(result["retry"])
        controller_calls = [call for call in self.commands("shell")
                            if av.GUEST_CONTROLLER in call["command"]]
        self.assertEqual(len(controller_calls), 1)
        repeated = self.adapter.execute_controller(
            world, {"host": av.instance_name(world), "world": world,
                    "request_id": "req-once", "op": "start", "agent": "dummy", "run": "run-once"},
        )
        self.assertEqual(repeated["state"], "unknown")
        self.assertFalse(repeated["retry"])
        controller_calls = [call for call in self.commands("shell")
                            if av.GUEST_CONTROLLER in call["command"]]
        self.assertEqual(len(controller_calls), 1)
        record = json.loads(self.adapter._record_path(world).read_text(encoding="utf-8"))
        self.assertEqual(record["operations"]["req-once"]["state"], "unknown")


if __name__ == "__main__":
    unittest.main()
