#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from agents_model_proxy import AgentsModelProxy, BackendConfig, ModelProxyError, ProxyBinding


class ModelIdentifierTests(unittest.TestCase):
    def test_proxy_rejects_nonfinite_or_boolean_resource_limits(self):
        binding = ProxyBinding('world', 'agent', 'run', 'provider', 'model')
        backend = BackendConfig('provider', 'model', 'openai-responses',
                                'local', 'http://127.0.0.1:1', 'mac', 'mac')
        for limit in (float('nan'), float('inf'), 0, -1, True):
            with self.assertRaises(ModelProxyError):
                AgentsModelProxy(binding, backend, Path('/unused/socket'), Path('/unused'),
                                 (), lambda _: True, io_timeout=limit)
        with self.assertRaises(ModelProxyError):
            AgentsModelProxy(binding, backend, Path('/unused/socket'), Path('/unused'),
                             (), lambda _: True, max_request_bytes=True)

    def test_opaque_model_identifiers_in_both_configs(self):
        constructors = (
            lambda model: ProxyBinding('world', 'agent', 'run', 'provider', model),
            lambda model: BackendConfig('provider', model, 'openai-responses',
                                       'local', 'http://127.0.0.1:1', 'mac', 'mac'),
        )
        for constructor in constructors:
            for model in ('/Users/example/model', 'org/model:tag', 'a' * 512):
                with self.subTest(model=model[:32]):
                    self.assertEqual(constructor(model).model, model)
            for model in ('', 'a' * 513, 'model\n', 'a b', 'a\x00', 'ä', None):
                with self.assertRaises(ModelProxyError):
                    constructor(model)
        with self.assertRaises(ModelProxyError):
            ProxyBinding('/world', 'agent', 'run', 'provider', 'model')


if __name__ == '__main__':
    unittest.main()
