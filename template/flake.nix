{
  inputs.strata-nix.url = "github:hinriksnaer/strata-nix";

  outputs = { strata-nix, ... }: {
    packages.x86_64-linux.default = strata-nix.lib.mkServer {
      # ── Required ──
      dataDir = "/mnt/podman_storage/${builtins.getEnv "USER"}/weights";
      gpu     = "0";            # GPU index from nvidia-smi
      port    = 8080;
      host    = "127.0.0.1";   # set to "0.0.0.0" + apiKeyFile for network access
      family  = "qwen";        # qwen | coder | swift | unsloth
      model   = "IQ2_XS";     # IQ2_XS | Q2_0 | IQ3_XXS | IQ3_S | UD-IQ4_XS ...
      context = 32768;

      # ── Optional ──
      # vision     = "no";     # no | yes (GPU) | cpu
      # lowRam     = "auto";   # auto | on | off
      # kv         = null;     # null | int8 | q4_0 | k8v4
      # gpus       = null;     # multi-GPU: "0,1" or "all"
      # apiKeyFile = "/run/secrets/strata-api-key";
      # extraArgs  = [];
    };
  };
}
