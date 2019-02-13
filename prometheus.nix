
########################################################################
#                                                                      #
# DO NOT EDIT THIS FILE, ALL EDITS SHOULD BE DONE IN THE GIT REPO,     #
# PUSHED TO GITHUB AND PULLED HERE.                                    #
#                                                                      #
# LOCAL EDITS WILL BE OVERWRITTEN.                                     #
#                                                                      #
########################################################################

{ config, lib, pkgs, ... }:

{

  users.extraUsers.prometheus = {
    isNormalUser = false;
    isSystemUser = true;
    shell = pkgs.nologin;
    openssh.authorizedKeys.keyFiles = [ ./keys/prometheus ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [
      "logind"
      "systemd"
    ];
    # We do not need to open the firewall publicly
    openFirewall = false;
  };

}

