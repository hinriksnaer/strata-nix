"""
Patch Strata's setup.py for the Nix environment:
  1. get_llama_cpp() -> return pre-fetched Nix store path (no download)
  2. pip_install()   -> no-op (packages pre-baked in pythonEnv, store is immutable)
  3. gpus()          -> MIG support: _mig_vram_gb() helper + vram fallback

Usage: python3 patch-setup-py.py <path-to-setup.py> <llama-cpp-store-path>
"""
import sys
import re
from pathlib import Path

setup_py = Path(sys.argv[1])
llama_src = sys.argv[2]
src = setup_py.read_text()

# ---------------------------------------------------------------------------
# Patch 1: get_llama_cpp() -> return Nix store path directly
# ---------------------------------------------------------------------------
m = re.search(
    r"^def get_llama_cpp\(\):.*?^    return llama\n",
    src, re.MULTILINE | re.DOTALL
)
assert m, "get_llama_cpp() not found in setup.py"
old = m.group(0)
new = (
    "def get_llama_cpp():\n"
    "    \"\"\"Nix: return pre-fetched llama.cpp from the Nix store (no download needed).\"\"\"\n"
    "    return Path(" + repr(llama_src) + ")\n"
)
src = src.replace(old, new)

# ---------------------------------------------------------------------------
# Patch 2: pip_install() -> no-op
# ---------------------------------------------------------------------------
m = re.search(
    r"^def pip_install\(packages, what\):.*?^    ok\(f\"\{what\} installed\"\)\n",
    src, re.MULTILINE | re.DOTALL
)
assert m, "pip_install() not found in setup.py"
old = m.group(0)
new = (
    "def pip_install(packages, what):\n"
    "    \"\"\"Nix: all packages are pre-installed in the pythonEnv; pip is not used.\"\"\"\n"
    "    ok(f\"{what} already installed\")\n"
)
src = src.replace(old, new)

# ---------------------------------------------------------------------------
# Patch 3a: inject _mig_vram_gb() helper before gpus()
# ---------------------------------------------------------------------------
mig_helper = (
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
src = src.replace("def gpus():", mig_helper + "def gpus():", 1)

# ---------------------------------------------------------------------------
# Patch 3b: use _mig_vram_gb() in found.append inside gpus()
# ---------------------------------------------------------------------------
old_append = (
    '            found.append({"index": int(idx), "name": name, "vram_gb": float(mem) / 1024.0, "arch": cc.replace(".", ""),\n'
    '                          "driver": drv})'
)
new_append = (
    '            vram_gb = _mig_vram_gb(name) if "[" in mem else float(mem) / 1024.0\n'
    '            found.append({"index": int(idx), "name": name, "vram_gb": vram_gb, "arch": cc.replace(".", ""),\n'
    '                          "driver": drv})'
)
assert old_append in src, "found.append() line not found in setup.py"
src = src.replace(old_append, new_append, 1)

setup_py.write_text(src)
print("setup.py patched successfully")
