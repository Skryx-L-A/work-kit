#!/usr/bin/env python3
import socket
import io
import json
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import agents_data as ad
from agents_controller import AgentClient, AgentController, ControllerError
from agents_controller_endpoint import ControllerEndpoint
import agents_rpc_client as rpc_cli


class ControllerEndpointTests(unittest.TestCase):
    def test_rpc_cli_rejects_identity_fields_before_connecting(self):
        for body in (b'{"agent_id":"other"}', b'[]', b'not-json', b'x' * 65537):
            output = io.StringIO()
            with patch.object(sys, 'stdin', SimpleNamespace(buffer=io.BytesIO(body))), \
                    patch.object(sys, 'stdout', output), \
                    patch.object(rpc_cli.socket, 'socket') as connect:
                self.assertEqual(rpc_cli.main(['inbox.read']), 2)
                self.assertFalse(json.loads(output.getvalue())['ok'])
                connect.assert_not_called()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='.wb-ctrl-', dir=Path.home())
        self.root = Path(self.tmp.name)
        self.world = self.root / 'world'
        ad.create_world(self.world, name='Endpoint', main_name='main', sender='cli-operator')
        self.current = True
        self.controller = AgentController(self.world, 'run', lambda _: self.current)
        self.endpoints = []
        self.clients = []

    def tearDown(self):
        for client in self.clients:
            client.close()
        for endpoint in self.endpoints:
            endpoint.close()
        self.controller.close()
        self.controller.join()
        self.tmp.cleanup()

    def endpoint(self, **kwargs):
        endpoint = ControllerEndpoint(self.controller, 'main', 'hauptagent',
                                      self.root / 'controller.sock', **kwargs)
        self.endpoints.append(endpoint)
        return endpoint

    def connect(self, endpoint):
        sock = socket.socket(socket.AF_UNIX)
        sock.connect(str(endpoint.path))
        client = AgentClient(sock, 2)
        self.clients.append(client)
        return client

    def test_typed_channel_rejects_identity_injection_and_expired_run(self):
        endpoint = self.endpoint()
        endpoint.binding.validate()
        first = self.connect(endpoint)
        self.assertEqual(first.request('inbox.read'), [])
        with self.assertRaises(ControllerError):
            first.request('inbox.read', {'agent_id': 'other'})
        second = self.connect(endpoint)
        question = second.request('question.ask', {'question_id': 'choice', 'text': 'Which?'})
        self.assertEqual(question['id'], 'choice')
        self.current = False
        with self.assertRaises(ControllerError):
            second.request('question.ask', {'question_id': 'late', 'text': 'Late'})
        self.assertEqual(len(ad.list_questions(self.world)), 1)

    def test_capacity_and_owned_cleanup(self):
        endpoint = self.endpoint(max_connections=1)
        first = self.connect(endpoint)
        self.assertEqual(first.request('inbox.read'), [])
        overflow = socket.socket(socket.AF_UNIX)
        try:
            overflow.settimeout(2)
            overflow.connect(str(endpoint.path))
            self.assertEqual(overflow.recv(1), b'')
        finally:
            overflow.close()
        endpoint.close()
        self.assertFalse(endpoint.path.exists())
        self.assertFalse(endpoint._accept_thread.is_alive())

    def test_existing_socket_is_not_deleted_on_failed_bind(self):
        existing = socket.socket(socket.AF_UNIX)
        path = self.root / 'controller.sock'
        try:
            existing.bind(str(path))
            inode = path.stat().st_ino
            with self.assertRaises(OSError):
                self.endpoint()
            self.assertEqual(path.stat().st_ino, inode)
        finally:
            existing.close()


if __name__ == '__main__':
    unittest.main()
