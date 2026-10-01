# Pick the int8 ONNX variant of the brain model for this CPU. Source, then call:
#   brain_model_variant [cpuinfo-file]   -> prints avx512 or avx2
# BRAIN_MODEL_VARIANT=avx2|avx512 overrides the detection.
# avx512: CPU reports avx512f and avx512bw (the file uses AVX-512 int8 kernels).
# avx2:   everything else, including CPUs without AVX-512 and non-Linux systems
#         without /proc/cpuinfo (onnxruntime runs both files on any CPU; only speed differs).

brain_model_variant() {
  local cpuinfo="${1:-${BRAIN_CPUINFO:-/proc/cpuinfo}}" flags
  case "${BRAIN_MODEL_VARIANT:-}" in
    avx2|avx512) echo "$BRAIN_MODEL_VARIANT"; return 0 ;;
    "") ;;
    *) echo "BRAIN_MODEL_VARIANT must be avx2 or avx512" >&2; return 1 ;;
  esac
  if [ -r "$cpuinfo" ]; then
    flags="$(grep -m1 -E '^flags[[:space:]]*:' "$cpuinfo" 2>/dev/null)"
    case " $flags " in
      *" avx512f "*) case " $flags " in *" avx512bw "*) echo avx512; return 0 ;; esac ;;
    esac
  fi
  echo avx2
}

# brain_model_onnx <variant>: ONNX path inside the model directory (needs model.conf sourced)
brain_model_onnx() {
  case "$1" in
    avx512) echo "$BRAIN_MODEL_ONNX_AVX512" ;;
    *) echo "$BRAIN_MODEL_ONNX_AVX2" ;;
  esac
}
