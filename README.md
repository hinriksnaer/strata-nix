# strata-nix

Nix packaging for [Strata](https://github.com/Niko1221/Strata) — OpenAI-compatible
LLM inference for Qwen3.8-Flash-Next on a single NVIDIA GPU + system RAM.

## Usage

```bash
nix run github:hinriksnaer/strata-nix -- \
  --family qwen --model IQ2_XS --gpu 0 --port 8080 \
  --data-dir /path/to/data
```

First run downloads the model (~68 GB for IQ2_XS), calibrates, and starts the server.
Subsequent runs start immediately using the saved config.

## Models

| Model     | RAM   | Quality                    |
|-----------|-------|----------------------------|
| `IQ2_XS`  | 48 GB | 2-bit, fast                |
| `IQ3_XXS` | 60 GB | 3-bit, better              |
| `IQ3_S`   | 62 GB | 3.5-bit, matches full BF16 |

## Requirements

- x86_64-linux
- NVIDIA GPU (sm_90 / H200; adjust `cudaArch` in `flake.nix` for other cards)
- Nix with flakes enabled
