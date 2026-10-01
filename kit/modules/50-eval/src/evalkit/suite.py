"""Suite files: loading and validation."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from . import graders
from .providers import Provider, ProviderError, build_provider


class SuiteError(ValueError):
    """The suite file is invalid."""


@dataclass
class Case:
    id: str
    input: str
    graders: list[dict]


@dataclass
class Suite:
    name: str
    description: str
    path: Path
    sha256: str
    repetitions: int
    timeout: float
    prompt: str | None
    providers: list[Provider]
    judges: list[Provider]
    cases: list[Case]
    top_keys: list[str] = field(default_factory=list)

    @property
    def base_dir(self) -> Path:
        return self.path.parent


_TOP_KEYS = {"name", "description", "repetitions", "timeout", "prompt", "providers", "judges", "cases"}
_CASE_KEYS = {"id", "input", "input_file", "graders"}


def _read_yaml(path: Path) -> tuple[Any, str]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise SuiteError(f"cannot read {path}: {exc.strerror}") from exc
    try:
        return yaml.safe_load(raw.decode("utf-8")), hashlib.sha256(raw).hexdigest()
    except (yaml.YAMLError, UnicodeDecodeError) as exc:
        raise SuiteError(f"{path}: invalid YAML: {exc}") from exc


def load_suite(path: str | Path) -> Suite:
    path = Path(path).resolve()
    data, digest = _read_yaml(path)
    if not isinstance(data, dict):
        raise SuiteError(f"{path.name}: top level must be a mapping")
    unknown = set(data) - _TOP_KEYS
    if unknown:
        raise SuiteError(f"{path.name}: unknown top-level key(s): {', '.join(sorted(unknown))}")
    base = path.parent

    def positive(key: str, default: float, integer: bool = False) -> Any:
        value = data.get(key, default)
        ok = isinstance(value, int if integer else (int, float)) and not isinstance(value, bool)
        if not ok or value <= 0:
            raise SuiteError(f"{path.name}: '{key}' must be a positive {'integer' if integer else 'number'}")
        return value

    providers = _providers(data.get("providers"), base, path.name, "providers", required=True)
    judges = _providers(data.get("judges"), base, path.name, "judges", required=False)
    ids = [p.id for p in providers]
    if len(set(ids)) != len(ids):
        raise SuiteError(f"{path.name}: duplicate provider ids")
    if data.get("prompt") is not None and "{input}" not in str(data["prompt"]):
        raise SuiteError(f"{path.name}: 'prompt' must contain {{input}}")
    cases = _cases(data.get("cases"), base, path.name, [j.id for j in judges])

    return Suite(
        name=str(data.get("name") or path.stem),
        description=str(data.get("description") or "").strip(),
        path=path,
        sha256=digest,
        repetitions=positive("repetitions", 1, integer=True),
        timeout=float(positive("timeout", 60)),
        prompt=data.get("prompt"),
        providers=providers,
        judges=judges,
        cases=cases,
        top_keys=sorted(data),
    )


def _providers(raw: Any, base: Path, fname: str, key: str, required: bool) -> list[Provider]:
    if raw is None:
        if required:
            raise SuiteError(f"{fname}: '{key}' is required")
        return []
    if not isinstance(raw, list) or (required and not raw):
        raise SuiteError(f"{fname}: '{key}' must be a non-empty list")
    out = []
    for i, spec in enumerate(raw):
        try:
            out.append(build_provider(spec, base, f"{fname}: {key}[{i}]"))
        except ProviderError as exc:
            raise SuiteError(str(exc)) from exc
    return out


def _cases(raw: Any, base: Path, fname: str, judge_ids: list[str]) -> list[Case]:
    if not isinstance(raw, list) or not raw:
        raise SuiteError(f"{fname}: 'cases' must be a non-empty list")
    cases, seen = [], set()
    for i, spec in enumerate(raw):
        where = f"{fname}: cases[{i}]"
        if not isinstance(spec, dict):
            raise SuiteError(f"{where}: case must be a mapping")
        unknown = set(spec) - _CASE_KEYS
        if unknown:
            raise SuiteError(f"{where}: unknown key(s): {', '.join(sorted(unknown))}")
        cid = str(spec.get("id", f"case-{i + 1}"))
        if cid in seen:
            raise SuiteError(f"{where}: duplicate case id {cid!r}")
        seen.add(cid)
        where = f"{fname}: case {cid}"
        if ("input" in spec) == ("input_file" in spec):
            raise SuiteError(f"{where}: give exactly one of 'input' or 'input_file'")
        if "input_file" in spec:
            file = base / str(spec["input_file"])
            try:
                text = file.read_text(encoding="utf-8")
            except OSError as exc:
                raise SuiteError(f"{where}: cannot read input_file {file}: {exc.strerror}") from exc
        else:
            text = str(spec["input"])
        raw_graders = spec.get("graders")
        if not isinstance(raw_graders, list) or not raw_graders:
            raise SuiteError(f"{where}: 'graders' must be a non-empty list")
        try:
            normalised = [
                graders.normalise(g, f"{where}, graders[{j}]", base, judge_ids)
                for j, g in enumerate(raw_graders)
            ]
        except graders.GraderConfigError as exc:
            raise SuiteError(f"{fname}: {exc}") from exc
        cases.append(Case(cid, text, normalised))
    return cases
