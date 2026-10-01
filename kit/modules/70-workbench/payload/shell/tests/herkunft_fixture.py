"""Test-only fixtures for measured humans and non-human setup origins.

The production path never imports this module. Each test module explicitly
patches the one relevant measurement in its own Python process; subprocess
tests keep exercising the real, fail-closed probes.
"""
from __future__ import annotations

from contextlib import contextmanager
from unittest import mock


def gemessener_mensch(modul):
    """Return a patcher for a human measurement inside one test process only."""
    return mock.patch.object(modul, "_measured_human",
                             return_value=(True, "Test-Fixture: gemessener Mensch"))


@contextmanager
def gebundene_governance(modul):
    """Allow legacy data-unit calls to stand for an authenticated controller.

    Provenance regressions do not use this fixture. Subprocesses cannot inherit
    the mock or context variable, so CLI attack tests still exercise fail-closed
    production behavior.
    """
    token = modul._CONTROLLER_ACTOR_BINDING.set({"run": "test-controller-fixture"})
    try:
        with mock.patch.object(modul, "_controller_binding_matches", return_value=True):
            yield
    finally:
        modul._CONTROLLER_ACTOR_BINDING.reset(token)


@contextmanager
def aufbau_herkunft(modul):
    """Enable ``aufbau`` only in this process and only for creation APIs."""
    with mock.patch.object(modul, "_test_setup_proof",
                           return_value=(True, "Test-Fixture: isolierter Aufbau")):
        yield modul.TEST_SETUP_ACTOR
