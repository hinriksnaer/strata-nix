{
  inputs = {
    strata-nix.url = "github:hinriksnaer/strata-nix";

    # Pin the Strata source to a specific commit for reproducibility.
    strata-src = {
      url   = "github:OWNER/Strata";   # replace with the real repo
      flake = false;
    };
  };

  outputs = { strata-nix, strata-src, ... }: {
    packages.x86_64-linux.default = strata-nix.lib.mkServer {
      inherit strata-src;

      # ── Storage ──
      dataDir = "/mnt/podman_storage/YOUR_USERNAME/weights";

      # ── GPU ──
      gpu      = "0";    # index from: nvidia-smi --query-gpu=index --format=csv,noheader
      cudaArch = "90";   # H200=90, A100=80, RTX40xx=89, RTX30xx=86, RTX20xx=75

      # ── Network ──
      port = 8080;
      host = "127.0.0.1";   # "0.0.0.0" to expose on the network -- requires apiKeyFile

      # ── Model ──
      family  = "qwen";     # qwen | coder | swift | unsloth
      model   = "IQ2_XS";  # IQ2_XS | Q2_0 | IQ3_XXS | IQ3_S | UD-IQ4_XS ...
      context = 32768;

      # ── Optional ──
      # vision     = "no";   # no | yes (GPU) | cpu
      # lowRam     = "auto"; # auto | on | off  (experts from disk vs RAM)
      # kv         = null;   # null | int8 | q4_0 | k8v4
      # gpus       = null;   # multi-GPU: "0,1" or "all"
      # apiKeyFile = "/run/secrets/strata-api-key";
      # extraArgs  = [];
    };
  };
}
