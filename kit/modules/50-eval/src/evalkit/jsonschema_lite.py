"""Minimal JSON Schema validator (no dependencies).

Supports the subset that covers typical extraction checks. Keywords outside the
subset raise SchemaError instead of being ignored, so a check never passes silently.
"""

from __future__ import annotations

import math
import re
from typing import Any


class SchemaError(ValueError):
    pass


_ANNOTATIONS = {"$schema", "$id", "$comment", "title", "description", "default", "examples", "format"}
_SUPPORTED = {
    "type", "enum", "const", "properties", "required", "additionalProperties", "items",
    "minItems", "maxItems", "uniqueItems", "minLength", "maxLength", "pattern",
    "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf",
    "anyOf", "oneOf", "allOf", "not",
}


def _type_ok(value: Any, name: str) -> bool:
    if name == "object":
        return isinstance(value, dict)
    if name == "array":
        return isinstance(value, list)
    if name == "string":
        return isinstance(value, str)
    if name == "boolean":
        return isinstance(value, bool)
    if name == "null":
        return value is None
    if name == "integer":
        return (isinstance(value, int) and not isinstance(value, bool)) or (
            isinstance(value, float) and value.is_integer()
        )
    if name == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    raise SchemaError(f"unknown type {name!r}")


def errors(value: Any, schema: Any, path: str = "$") -> list[str]:
    """Return a list of validation error messages (empty when valid)."""
    if schema is True:
        return []
    if schema is False:
        return [f"{path}: no value is allowed here"]
    if not isinstance(schema, dict):
        raise SchemaError(f"schema must be an object or boolean, got {type(schema).__name__}")
    for key in schema:
        if key not in _SUPPORTED and key not in _ANNOTATIONS:
            raise SchemaError(f"unsupported JSON Schema keyword {key!r}")

    out: list[str] = []
    if "type" in schema:
        types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(_type_ok(value, t) for t in types):
            return [f"{path}: expected {'|'.join(types)}, got {_name(value)}"]
    if "enum" in schema and not any(_eq(value, e) for e in schema["enum"]):
        out.append(f"{path}: {value!r} not in enum {schema['enum']!r}")
    if "const" in schema and not _eq(value, schema["const"]):
        out.append(f"{path}: expected constant {schema['const']!r}")

    if isinstance(value, dict):
        for name in schema.get("required", []):
            if name not in value:
                out.append(f"{path}: missing required property {name!r}")
        props = schema.get("properties", {})
        for name, sub in props.items():
            if name in value:
                out.extend(errors(value[name], sub, f"{path}.{name}"))
        extra = schema.get("additionalProperties", True)
        for name in value:
            if name not in props:
                if extra is False:
                    out.append(f"{path}: unexpected property {name!r}")
                elif isinstance(extra, dict):
                    out.extend(errors(value[name], extra, f"{path}.{name}"))
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            out.append(f"{path}: fewer than {schema['minItems']} items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            out.append(f"{path}: more than {schema['maxItems']} items")
        if schema.get("uniqueItems"):
            for i, a in enumerate(value):
                if any(_eq(a, b) for b in value[:i]):
                    out.append(f"{path}: items are not unique")
                    break
        if "items" in schema:
            for i, item in enumerate(value):
                out.extend(errors(item, schema["items"], f"{path}[{i}]"))
    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            out.append(f"{path}: shorter than {schema['minLength']} characters")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            out.append(f"{path}: longer than {schema['maxLength']} characters")
        if "pattern" in schema and not re.search(schema["pattern"], value):
            out.append(f"{path}: does not match pattern {schema['pattern']!r}")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            out.append(f"{path}: {value} < minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            out.append(f"{path}: {value} > maximum {schema['maximum']}")
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            out.append(f"{path}: {value} <= exclusiveMinimum {schema['exclusiveMinimum']}")
        if "exclusiveMaximum" in schema and value >= schema["exclusiveMaximum"]:
            out.append(f"{path}: {value} >= exclusiveMaximum {schema['exclusiveMaximum']}")
        if "multipleOf" in schema:
            q = value / schema["multipleOf"]
            if not math.isclose(q, round(q), abs_tol=1e-9):
                out.append(f"{path}: {value} is not a multiple of {schema['multipleOf']}")

    if "allOf" in schema:
        for sub in schema["allOf"]:
            out.extend(errors(value, sub, path))
    if "anyOf" in schema and not any(not errors(value, s, path) for s in schema["anyOf"]):
        out.append(f"{path}: matches none of anyOf")
    if "oneOf" in schema:
        n = sum(1 for s in schema["oneOf"] if not errors(value, s, path))
        if n != 1:
            out.append(f"{path}: matches {n} of oneOf (expected exactly 1)")
    if "not" in schema and not errors(value, schema["not"], path):
        out.append(f"{path}: matches a schema it must not match")
    return out


def _eq(a: Any, b: Any) -> bool:
    if isinstance(a, bool) != isinstance(b, bool):
        return False
    return a == b


def _name(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    return {dict: "object", list: "array", str: "string", int: "integer", float: "number"}.get(
        type(value), type(value).__name__
    )
