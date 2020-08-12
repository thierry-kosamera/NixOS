{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.settings.services.traefik;
in

{

  options.settings.services.traefik = {
    enable = mkEnableOption "the Traefik service";

    version = mkOption {
      type = types.str;
      default = "2.2";
      readOnly = true;
    };

    image = mkOption {
      type = types.str;
      default = "traefik";
      readOnly = true;
    };

    service_name = mkOption {
      type = types.str;
      default = "nixos-traefik";
      readOnly = true;
    };

    network_name = mkOption {
      type = types.str;
      default = "traefik_backend";
    };

    acme = {
      storage = mkOption {
        type = types.str;
        default = "/letsencrypt";
        readOnly = true;
      };

      email_address = mkOption {
        type = types.str;
        default = "dr.watson@brussels.msf.org";
        readOnly = true;
      };
    };
  };

  # Options that cannot be defined on the command line, can be defined by
  # creating a YAML file in the Nix store using the nixpkgs builders and
  # by then bind-mounting these configuration files into the Traefik container.
  config = mkIf cfg.enable {
    docker-containers = let
      dynamic_config_file_name   = "traefik-dynamic.yaml";
      dynamic_config_file_target = "/${dynamic_config_file_name}";
      dynamic_config_file_source = pkgs.writeText dynamic_config_file_name ''
        ---
        tls:
          options:
            default:
              minVersion: "VersionTLS12"
              sniStrict: true
              cipherSuites:
                - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
                - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
                - "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
                - "TLS_AES_128_GCM_SHA256"
                - "TLS_AES_256_GCM_SHA384"
                - "TLS_CHACHA20_POLY1305_SHA256"
      '';
    in {
      "${cfg.service_name}" = {
        image = "${cfg.image}:${cfg.version}";
        cmd = [
          "--api.insecure=false"
          "--ping"
          "--log.level=INFO"
          "--accesslog=true"
          "--metrics.prometheus=true"
          "--providers.file.watch=true"
          "--providers.file.filename=${dynamic_config_file_target}"
          # We use the Docker provider, but do not expose containers by default
          # A container need to set the correct labels before we forward traffic to it
          "--providers.docker=true"
          "--providers.docker.network=${cfg.network_name}"
          "--providers.docker.exposedbydefault=false"
          "--entrypoints.web.address=:80"
          "--entrypoints.websecure.address=:443"
          # We redirect HTTP to HTTPS
          "--entrypoints.web.http.redirections.entrypoint.to=websecure"
          "--entrypoints.web.http.redirections.entrypoint.scheme=https"
          "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
          "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
          # "--certificatesresolvers.letsencrypt.acme.caserver=http://acme-staging-v02.api.letsencrypt.org/directory"
          "--certificatesresolvers.letsencrypt.acme.email=${cfg.acme.email_address}"
          "--certificatesresolvers.letsencrypt.acme.storage=${cfg.acme.storage}/acme.json"
        ];
        ports = [
          "80:80"
          "443:443"
        ];
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro"
          "${dynamic_config_file_source}:${dynamic_config_file_target}:ro"
          "traefik_letsencrypt:/${cfg.acme.storage}"
        ];
        workdir = "/opt";
        extraDockerOptions = [
          "--network=${cfg.network_name}"
          "--health-cmd=traefik healthcheck --ping"
          "--health-interval=10s"
          "--health-retries=5"
          "--health-timeout=3s"
          # Define the security-headers middleware
          "--label=traefik.http.middlewares.security-headers.headers.sslredirect=true"
          "--label=traefik.http.middlewares.security-headers.headers.forceSTSHeader=true"
          "--label=traefik.http.middlewares.security-headers.headers.stsPreload=true"
          "--label=traefik.http.middlewares.security-headers.headers.stsSeconds=315360000"
          "--label=traefik.http.middlewares.security-headers.headers.stsIncludeSubdomains=true"
        ];
      };
    };

    # We add an additional pre-start script to create the Traefik Docker network.
    systemd.services = let
      docker    = "${pkgs.docker}/bin/docker";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      traefik_docker_service = "docker-${cfg.service_name}";
    in {
      "${traefik_docker_service}" = {
        serviceConfig.ExecStartPre = let
          script = pkgs.writeShellScript "${cfg.service_name}-create-network" ''
            if [ -z $(${docker} network list --filter "name=^${cfg.network_name}$" --quiet) ]; then
              ${docker} network create ${cfg.network_name}
            fi
          '';
        in [ script ];
      };

      #TODO: how can we cleanup old images?
      "${cfg.service_name}-pull" = {
        inherit (cfg) enable;
        description   = "Automatically pull the latest version of the Traefik image";
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          ${docker} pull ${cfg.image}:${cfg.version}
          ${systemctl} try-restart ${traefik_docker_service}.service
        '';
        startAt = "Wed 03:00";
      };
    };
  };

}

