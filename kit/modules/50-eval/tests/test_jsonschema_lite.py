import pytest

from evalkit.jsonschema_lite import SchemaError, errors


def test_valid_object():
    schema = {"type": "object", "required": ["a"], "properties": {"a": {"type": "integer"}}}
    assert errors({"a": 1}, schema) == []


def test_type_mismatch_and_bool_is_not_integer():
    assert errors("x", {"type": "integer"})
    assert errors(True, {"type": "integer"})
    assert errors(True, {"type": "number"})
    assert errors(1.0, {"type": "integer"}) == []


def test_required_additional_and_nested_paths():
    schema = {
        "type": "object",
        "required": ["a"],
        "additionalProperties": False,
        "properties": {"a": {"type": "array", "items": {"type": "string"}}},
    }
    msgs = errors({"b": 1}, schema)
    assert any("missing required property 'a'" in m for m in msgs)
    assert any("unexpected property 'b'" in m for m in msgs)
    assert errors({"a": ["x", 2]}, schema) == ["$.a[1]: expected string, got integer"]


def test_bounds_pattern_enum():
    assert errors(5, {"minimum": 6})
    assert errors(5, {"exclusiveMaximum": 5})
    assert errors("ab", {"pattern": "^a$"})
    assert errors("x", {"enum": ["a", "b"]})
    assert errors(1, {"const": True})  # 1 is not True
    assert errors(0.3, {"multipleOf": 0.1}) == []


def test_combinators():
    assert errors(1, {"anyOf": [{"type": "string"}, {"type": "integer"}]}) == []
    assert errors(1.5, {"anyOf": [{"type": "string"}, {"type": "integer"}]})
    assert errors(1, {"oneOf": [{"type": "integer"}, {"minimum": 0}]})
    assert errors(1, {"not": {"type": "integer"}})


def test_unsupported_keyword_is_an_error_not_a_pass():
    with pytest.raises(SchemaError):
        errors({}, {"$ref": "#/definitions/x"})
