# NixOS module: services.strata
# Provides a systemd-managed Strata LLM inference server with GPU access,
# hardened service isolation, and optional firewall opening.
{ config, lib, pkgs, strata-packages, ... }:

let
  cfg = config.services.strata;
in {
  options.services.strata = {
    enable = lib.mkEnableOption "Strata LLM inference server";

    package = lib.mkOption {
      type        = lib.types.package;
      default     = strata-packages.strata-server;
      defaultText = lib.literalExpression "strata-nix.packages.\${system}.strata-server";
      description = "The Strata server package to use.";
    };

    dataDir = lib.mkOption {
      type        = lib.types.path;
      default     = "/var/lib/strata";
      description = "Directory for model files, packs, and server configuration.";
    };

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 8080;
      description = "Port for the HTTP API server.";
    };

    host = lib.mkOption {
      type        = lib.types.str;
      default     = "127.0.0.1";
      description = ''
        Listen address.  Keep 127.0.0.1 for local-only access.
        Set to 0.0.0.0 only with an API key.
      '';
    };

    family = lib.mkOption {
      type        = lib.types.enum [ "qwen" "coder" "swift" "unsloth" ];
      default     = "qwen";
      description = "Model family.";
    };

    model = lib.mkOption {
      type        = lib.types.str;
      default     = "IQ2_XS";
      description = "Model quantization (IQ2_XS, Q2_0, IQ3_XXS, IQ3_S, IQ1_M, UD-IQ4_XS, ...).";
    };

    context = lib.mkOption {
      type        = lib.types.int;
      default     = 32768;
      description = "Context window in tokens.";
    };

    apiKey = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      description = "API key.  Prefer apiKeyFile to keep secrets out of the Nix store.";
    };

    apiKeyFile = lib.mkOption {
      type        = lib.types.nullOr lib.types.path;
      default     = null;
      description = "File containing the API key (single line, no trailing newline).";
    };

    gpu = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      description = "Single GPU index (nvidia-smi numbering).  null = auto.";
    };

    gpus = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      description = ''Multi-GPU: "0,1" or "all".'';
    };

    kv = lib.mkOption {
      type        = lib.types.nullOr (lib.types.enum [ "int8" "q4_0" "k8v4" ]);
      default     = null;
      description = "KV cache quantization.  null = setup.py default (int8).";
    };

    vision = lib.mkOption {
      type        = lib.types.enum [ "no" "yes" "cpu" ];
      default     = "no";
      description = "Image encoder: no, yes (GPU), cpu.";
    };

    lowRam = lib.mkOption {
      type        = lib.types.enum [ "auto" "on" "off" ];
      default     = "auto";
      description = "Low-RAM mode (experts from disk instead of RAM).";
    };

    extraArgs = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = "Extra arguments passed to setup.py.";
    };

    openFirewall = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = "Open the firewall for the server port.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.host == "127.0.0.1" || cfg.apiKey != null || cfg.apiKeyFile != null;
        message   = "services.strata: set apiKey or apiKeyFile when host != 127.0.0.1";
      }
    ];

    users.users.strata = {
      isSystemUser = true;
      group        = "strata";
      home         = cfg.dataDir;
      description  = "Strata inference server";
    };
    users.groups.strata = {};

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 strata strata -"
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.strata = {
      description = "Strata LLM inference server";
      after       = [ "network.target" "nvidia-persistenced.service" ];
      wants       = [ "nvidia-persistenced.service" ];
      wantedBy    = [ "multi-user.target" ];

      environment = {
        STRATA_DATA = cfg.dataDir;
      };

      script =
        let
          optArg = flag: val: lib.optionalString (val != null) "${flag} ${lib.escapeShellArg val}";
        in ''
          ${lib.optionalString (cfg.apiKeyFile != null)
            ''API_KEY="$(cat ${lib.escapeShellArg cfg.apiKeyFile})"''}

          exec ${cfg.package}/bin/strata-server \
            --family  ${lib.escapeShellArg cfg.family} \
            --model   ${lib.escapeShellArg cfg.model} \
            --context ${toString cfg.context} \
            --vision  ${cfg.vision} \
            --host    ${lib.escapeShellArg cfg.host} \
            --port    ${toString cfg.port} \
            --low-ram ${cfg.lowRam} \
            --data-dir ${lib.escapeShellArg cfg.dataDir} \
            ${optArg "--api-key" (if cfg.apiKeyFile != null then "$API_KEY" else cfg.apiKey)} \
            ${optArg "--gpu"  cfg.gpu} \
            ${optArg "--gpus" cfg.gpus} \
            ${optArg "--kv"   cfg.kv} \
            ${lib.concatStringsSep " " (map lib.escapeShellArg cfg.extraArgs)}
        '';

      serviceConfig = {
        Type             = "simple";
        User             = "strata";
        Group            = "strata";
        WorkingDirectory = cfg.dataDir;

        Restart    = "on-failure";
        RestartSec = 10;

        # First start downloads ~70 GB of model data
        TimeoutStartSec = "1h";

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem   = "strict";
        ProtectHome     = true;
        ReadWritePaths  = [ cfg.dataDir ];
        PrivateTmp      = true;

        # GPU access
        SupplementaryGroups = [ "video" "render" ];

        # mlock for the engine's pinned expert arena
        LimitMEMLOCK = "infinity";

        # Don't let the OOM killer target this easily
        OOMScoreAdjust = -500;
      };
    };
  };
}
