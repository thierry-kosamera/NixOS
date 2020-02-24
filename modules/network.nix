
########################################################################
#                                                                      #
# DO NOT EDIT THIS FILE, ALL EDITS SHOULD BE DONE IN THE GIT REPO,     #
# PUSHED TO GITHUB AND PULLED HERE.                                    #
#                                                                      #
# LOCAL EDITS WILL BE OVERWRITTEN.                                     #
#                                                                      #
########################################################################

{ config, lib, ...}:

with lib;

let
  cfg = config.settings.network;

  ifaceOpts = { name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
      };

      static = {
        address = mkOption {
          type = types.str;
        };

        prefix_length = mkOption {
          type = types.ints.between 0 32;
        };

        gateway = mkOption {
          type = types.str;
        };
      };
    };

    config = {
      name = mkDefault name;
    };
  };
in {
  options = {
    settings.network = {
      host_name = mkOption {
        type = types.str;
      };

      ifaces = mkOption {
        type    = with types; nullOr (attrsOf (submodule ifaceOpts));
        default = null;
      };

      nameservers = mkOption {
        type    = with types; listOf str;
        default = [];
      };

    };
  };

  config = {
    networking = {
      hostName = cfg.host_name;
      # All non-manually configured interfaces are configured by DHCP.
      useDHCP = true;
      dhcpcd = {
        persistent = true;
        # Per the manpage, interfaces matching these but also
        # matching a pattern in denyInterfaces, are still denied
        allowInterfaces = [ "en*" "wl*" ];
        # See: https://wiki.archlinux.org/index.php/Dhcpcd#dhcpcd_and_systemd_network_interfaces
        # We also ignore veth interfaces and the docker bridge, these are managed by Docker
        denyInterfaces  = [ "eth*" "wlan*" "veth*" "docker*" ];
        extraConfig = concatStringsSep "\n\n" (
          mapAttrsToList (iface: conf: ''
            # define static profile
            profile static_${iface}
            static ip_address=${conf.static.address}/${toString conf.static.prefix_length}
            static routers=${conf.static.gateway}

            # fallback to static profile on ${iface}
            interface ${iface}
            fallback static_${iface}
          '') cfg.ifaces
        );
      };
      nameservers = cfg.nameservers;
    };
  };
}

