import subprocess
from pathlib import Path

import pytest

MODULE = Path(__file__).resolve().parents[1]


def variant(tmp_path, flags, override=""):
    cpu = tmp_path / "cpuinfo"
    cpu.write_text(f"processor\t: 0\nflags\t\t: {flags}\n")
    cmd = (f'. "{MODULE}/model.conf"; . "{MODULE}/model-variant.sh"; '
           f'v="$(brain_model_variant "{cpu}")" || exit 1; echo "$v $(brain_model_onnx "$v")"')
    env = {"PATH": "/usr/bin:/bin"}
    if override:
        env["BRAIN_MODEL_VARIANT"] = override
    return subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env)


@pytest.mark.parametrize("flags,want", [
    ("fpu sse2 avx avx2 fma avx512f avx512dq avx512bw avx512vl avx512_vnni", "avx512"),
    ("fpu sse2 avx avx2 fma avx512f", "avx2"),          # no avx512bw
    ("fpu sse2 avx avx2 fma", "avx2"),
    ("", "avx2"),
])
def test_cpu_detection(tmp_path, flags, want):
    out = variant(tmp_path, flags).stdout.split()
    assert out[0] == want
    assert out[1] == {"avx512": "onnx/model_qint8_avx512.onnx", "avx2": "onnx/model_quint8_avx2.onnx"}[want]


def test_override_and_missing_cpuinfo(tmp_path):
    assert variant(tmp_path, "avx2", override="avx512").stdout.split()[0] == "avx512"
    assert variant(tmp_path, "avx2", override="bogus").returncode == 1
    r = subprocess.run(["bash", "-c", f'. "{MODULE}/model-variant.sh"; brain_model_variant /nonexistent'],
                       capture_output=True, text=True)
    assert r.stdout.strip() == "avx2"


def test_model_conf_lists_both_variants():
    conf = (MODULE / "model.conf").read_text()
    assert "onnx/model_qint8_avx512.onnx" in conf.split("BRAIN_MODEL_FILES=")[1].split('"\n')[0]
    assert "onnx/model_quint8_avx2.onnx" in conf.split("BRAIN_MODEL_FILES=")[1].split('"\n')[0]
