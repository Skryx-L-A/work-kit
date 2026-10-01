"""Paths and settings.

Resolution order for every setting: environment variable, then
`~/.config/work-kit/brain.toml`, then the built-in default.
"""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass
from pathlib import Path

DEFAULT_MODEL = "paraphrase-multilingual-MiniLM-L12-v2"


def _config_file() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "work-kit" / "brain.toml"


def _data_dir() -> Path:
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "work-kit"


def _load_file() -> dict:
    path = _config_file()
    if not path.is_file():
        return {}
    try:
        with path.open("rb") as fh:
            return tomllib.load(fh)
    except (OSError, tomllib.TOMLDecodeError):
        return {}


@dataclass(frozen=True)
class Settings:
    home: Path
    model: str
    model_dir: Path

    @property
    def state_dir(self) -> Path:
        return self.home / ".brain"

    @property
    def db_path(self) -> Path:
        return self.state_dir / "index.sqlite"


def load() -> Settings:
    cfg = _load_file()
    home = os.environ.get("BRAIN_HOME") or cfg.get("home") or str(Path.home() / "work" / "brain")
    model = os.environ.get("BRAIN_MODEL") or cfg.get("model") or DEFAULT_MODEL
    model_dir = os.environ.get("BRAIN_MODEL_DIR") or cfg.get("model_dir")
    if not model_dir:
        model_dir = str(_data_dir() / "models" / model)
    return Settings(
        home=Path(home).expanduser().resolve(),
        model=model,
        model_dir=Path(model_dir).expanduser(),
    )
