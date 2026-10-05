"""
Patch Strata's setup.py for the Nix environment.

Design principle: minimise divergence from upstream. Every patch targets a
stable anchor (function signature, module-level constant) so that upstream
changes to function bodies do not break us.

Patches applied:
  1. ROOT split: mutable state (engine/, configs, logs) -> STRATA_DATA_DIR
                 read-only static files (data/, serve/, tools/) -> _NIX_STORE_ROOT
  2. get_llama_cpp()  -> return pre-fetched Nix store path (no download)
  3. pip_install()    -> no-op (packages pre-baked in pythonEnv)
  4. gpus() MIG mode  -> _mig_vram_gb() helper for [Insufficient Permissions]

Usage: python3 patch-setup-py.py <path-to-setup.py> <llama-cpp-store-path>
"""
import sys
import re
from pathlib import Path

setup_py = Path(sys.argv[1])
llama_src = sys.argv[2]
src = setup_py.read_text()

# ---------------------------------------------------------------------------
# Patch 1: ROOT split
#
# Original (single line):
#   ROOT = Path(__file__).resolve().parent
#
# After patch:
#   ROOT = Path(__file__).resolve().parent
#   _NIX_STORE_ROOT = ROOT                      # immutable: data/, serve/, tools/, …
#   ROOT = Path(os.environ["STRATA_DATA_DIR"])  # mutable state: configs, engine/, logs
#
# Then bulk-redirect read-only subdir refs to _NIX_STORE_ROOT.
# ---------------------------------------------------------------------------
ROOT_LINE = 'ROOT = Path(__file__).resolve().parent\n'
assert ROOT_LINE in src, "ROOT definition line not found in setup.py"

ROOT_PATCH = (
    'ROOT = Path(__file__).resolve().parent\n'
    '_NIX_STORE_ROOT = ROOT                       '
    '# immutable Nix store: data/, serve/, tools/, …\n'
    'ROOT = Path(os.environ["STRATA_DATA_DIR"])   '
    '# mutable state: engine/, configs, logs → user data dir\n'
)
src = src.replace(ROOT_LINE, ROOT_PATCH, 1)

# Bulk-redirect read-only subdir references from ROOT to _NIX_STORE_ROOT.
# These subdirs are never written by setup.py on Linux (sycl is Windows-only,
# tools/hip is AMD-only reads).  The replacement is a simple string substitution
# on the quoted path fragment so it is insensitive to surrounding code changes.
for subdir in (
    '"data"',
    '"serve"',
    '"tools"',
    '"sycl"',
    '"CMakeLists.txt"',
    '"requirements.txt"',
):
    src = src.replace(f'ROOT / {subdir}', f'_NIX_STORE_ROOT / {subdir}')

# REQUIREMENTS constant uses the variable directly (not ROOT / "requirements.txt")
# but we replaced that above.  Double-check the bare REQUIREMENTS path is gone:
# (nothing extra needed - the module-level line uses ROOT / "requirements.txt")

# ---------------------------------------------------------------------------
# Patch 2: get_llama_cpp() -> return Nix store path directly
#
# Anchor: function signature + first line of body (stable; body may change).
# ---------------------------------------------------------------------------
m = re.search(
    r"^def get_llama_cpp\(\):.*?^    return llama\n",
    src, re.MULTILINE | re.DOTALL
)
assert m, "get_llama_cpp() not found in setup.py"
src = src.replace(m.group(0), (
    "def get_llama_cpp():\n"
    "    \"\"\"Nix: return pre-fetched llama.cpp from the Nix store (no download needed).\"\"\"\n"
    "    return Path(" + repr(llama_src) + ")\n"
))

# ---------------------------------------------------------------------------
# Patch 3: pip_install() -> no-op
#
# Anchor: function signature + last line of body (stable).
# ---------------------------------------------------------------------------
m = re.search(
    r"^def pip_install\(packages, what\):.*?^    ok\(f\"\{what\} installed\"\)\n",
    src, re.MULTILINE | re.DOTALL
)
assert m, "pip_install() not found in setup.py"
src = src.replace(m.group(0), (
    "def pip_install(packages, what):\n"
    "    \"\"\"Nix: all packages are pre-installed in the pythonEnv; pip is not used.\"\"\"\n"
    "    ok(f\"{what} already installed\")\n"
))

# ---------------------------------------------------------------------------
# Patch 4a: inject _mig_vram_gb() helper before gpus()
#
# Anchor: "def gpus():" (unique in the file).
# ---------------------------------------------------------------------------
MIG_HELPER = (
    "def _mig_vram_gb(gpu_name):\n"
    "    \"\"\"Fallback VRAM for MIG mode: nvidia-smi returns [Insufficient Permissions]\n"
    "    for memory.total on unprivileged callers. Parse slice GiB from nvidia-smi -L.\"\"\"\n"
    "    import re as _re\n"
    "    s = out([\"nvidia-smi\", \"-L\"])\n"
    "    m = _re.search(r\"MIG\\s+\\S*?(\\d+(?:\\.\\d+)?)gb\", s, _re.IGNORECASE)\n"
    "    return float(m.group(1)) if m else 0.0\n"
    "\n"
    "\n"
)
assert "def gpus():" in src, "def gpus(): not found in setup.py"
src = src.replace("def gpus():", MIG_HELPER + "def gpus():", 1)

# ---------------------------------------------------------------------------
# Patch 4b: use _mig_vram_gb() in found.append inside gpus()
#
# Anchor: exact found.append line (stable - it's the model GPU data structure).
# ---------------------------------------------------------------------------
OLD_APPEND = (
    '            found.append({"index": int(idx), "name": name, "vram_gb": float(mem) / 1024.0, "arch": cc.replace(".", ""),\n'
    '                          "driver": drv})'
)
NEW_APPEND = (
    '            vram_gb = _mig_vram_gb(name) if "[" in mem else float(mem) / 1024.0\n'
    '            found.append({"index": int(idx), "name": name, "vram_gb": vram_gb, "arch": cc.replace(".", ""),\n'
    '                          "driver": drv})'
)
assert OLD_APPEND in src, "found.append() line not found in setup.py"
src = src.replace(OLD_APPEND, NEW_APPEND, 1)

setup_py.write_text(src)
print("setup.py patched successfully")
