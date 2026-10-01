#!/usr/bin/env python3
import os
import socket
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from agents_linux import SocketBinding, LinuxLauncher
from agents_lauf import StartSpec


class SocketBindingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='.wb-socket-', dir=Path.home())
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.path = self.root / 'channel.sock'
        self.sock = socket.socket(socket.AF_UNIX)
        self.addCleanup(self.sock.close)
        self.sock.bind(str(self.path))
        self.path.chmod(0o600)

    def test_fixed_channel_and_replacement_detection(self):
        binding = SocketBinding(self.path, '/run/wb-model.sock')
        binding.validate()
        for destination in ('/run/docker.sock', '/run/user/1/bus', '/tmp/channel'):
            with self.assertRaises(ValueError):
                SocketBinding(self.path, destination)
        self.path.unlink()
        replacement = socket.socket(socket.AF_UNIX)
        self.addCleanup(replacement.close)
        replacement.bind(str(self.path))
        self.path.chmod(0o600)
        with self.assertRaises(ValueError):
            binding.validate()

    def test_symlink_and_unsafe_permissions_rejected(self):
        alias = self.root / 'alias'
        alias.symlink_to(self.path)
        with self.assertRaises(ValueError):
            SocketBinding(alias, '/run/wb-model.sock')
        self.path.chmod(0o606)
        with self.assertRaises(ValueError):
            SocketBinding(self.path, '/run/wb-model.sock')
        self.path.chmod(0o600)
        self.root.chmod(0o777)
        try:
            with self.assertRaises(ValueError):
                SocketBinding(self.path, '/run/wb-model.sock')
        finally:
            self.root.chmod(0o700)

    def test_command_mounts_only_named_socket_and_keeps_network_isolated(self):
        launcher = object.__new__(LinuxLauncher)
        launcher.bwrap = '/usr/bin/bwrap'
        launcher.read_paths = ()
        launcher.write_paths = ()
        launcher.socket_bindings = (SocketBinding(self.path, '/run/wb-controller.sock'),)
        command = launcher._bwrap_command(StartSpec(('/usr/bin/true',), '/tmp', ()))
        self.assertIn('--unshare-net', command)
        index = command.index(str(self.path))
        self.assertEqual(command[index-1:index+2],
                         ['--ro-bind', str(self.path), '/run/wb-controller.sock'])
        self.assertNotIn(str(self.root), command)


if __name__ == '__main__':
    unittest.main()
