
########################################################################
#                                                                      #
# DO NOT EDIT THIS FILE, ALL EDITS SHOULD BE DONE IN THE GIT REPO,     #
# PUSHED TO GITHUB AND PULLED HERE.                                    #
#                                                                      #
# LOCAL EDITS WILL BE OVERWRITTEN.                                     #
#                                                                      #
########################################################################

{ config, lib, pkgs, ... }:

with lib;

{

  options = {
    settings.docker.enable = mkOption {
      type = types.bool;
      default = false;
    };
  };

  config = mkIf config.settings.docker.enable {

    environment = {
      systemPackages = with pkgs; [
        git
        docker_compose
      ];

      # For containers running java, allows to bind mount /etc/timezone
      etc = mkIf (config.time.timeZone != null) {
        timezone.text = config.time.timeZone;
      };
    };

    boot.kernel.sysctl = {
      "vm.overcommit_memory" = 1;
      "net.core.somaxconn" = 65535;
    };

    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
      extraOptions = concatStringsSep " " (
        # Do not break currently running non-encrypted set-ups.
        (lists.optional config.settings.crypto.enable "--data-root  \"/opt/docker\"") ++
        # Docker internal IP addressing
        # Ranges used: 172.28.0.0/16, 172.29.0.0/16
        #
        # Docker bridge
        # 172.28.0.1/18
        #   -> 2^14 - 2 (16382) hosts 172.28.0.1 -> 172.28.127.254
        #
        # Custom networks (448 networks in total)
        # 172.28.64.0/18 in /24 blocks
        #   -> 2^6 (64) networks 172.28.64.0/24 -> 172.28.127.0/24
        # 172.28.128.0/17 in /24 blocks
        #   -> 2^7 (128) networks 172.28.128.0/24 -> 172.28.255.0/24
        # 172.29.0.0/16 in /24 blocks
        #   -> 2^8 (256) networks 172.29.0.0/24 -> 172.29.255.0/24
        [
          "--bip \"172.28.0.1/18\""
          "--default-address-pool \"base=172.28.64.0/18,size=24\""
          "--default-address-pool \"base=172.28.128.0/17,size=24\""
          "--default-address-pool \"base=172.29.0.0/16,size=24\""
        ]
      );
    };
  };
}
