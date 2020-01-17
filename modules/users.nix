
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

let

  userOpts = { name, config, ... }: {

    options = {

      name = mkOption {
        type = types.str;
      };

      enable = mkOption {
        type    = types.bool;
        default = false;
      };

      sshAllowed = mkOption {
        type    = types.bool;
        default = false;
      };

      extraGroups = mkOption {
        type    = with types; listOf str;
        default = [];
      };

      hasShell = mkOption {
        type    = types.bool;
        default = false;
      };

      isSystemUser = mkOption {
        type    = types.bool;
        default = false;
      };

      canTunnel = mkOption {
        type    = types.bool;
        default = false;
      };

    };

    config = {
      name = mkDefault name;
    };
  };

in {

  options = {

    settings.users = {
      users = mkOption {
        type    = with types; loaOf (submodule userOpts);
        default = [];
      };

      ssh-group = mkOption {
        type = types.str;
        default = "ssh-users";
        description = ''
          Group to tag users who are allowed log in via SSH
          (either for shell or for tunnel access).
        '';
      };

      fwd-tunnel-group = mkOption {
        type = types.str;
        default = "ssh-fwd-tun-users";
      };

    };

  };

  config = let
    ssh-group = config.settings.users.ssh-group;
    fwd-tunnel-group = config.settings.users.fwd-tunnel-group;
    toKeyPath = name: ../keys + ("/" + name);
  in {

    users = {

      # !! This line is very important !!
      # Without it, the ssh-users group is not created
      # and no-one has SSH access to the system!
      groups."${ssh-group}"        = { };
      groups."${fwd-tunnel-group}" = { };

      users = mapAttrs (name: user: {
        name         = name;
        isNormalUser = user.hasShell;
        isSystemUser = user.isSystemUser;
        extraGroups  = user.extraGroups ++
                         (optional (user.sshAllowed || user.canTunnel) ssh-group) ++
                         (optional user.canTunnel fwd-tunnel-group);
        shell        = mkIf (!user.hasShell) pkgs.nologin;
        openssh.authorizedKeys.keyFiles = [ (toKeyPath name) ];
      }) (filterAttrs (_: user: user.enable) config.settings.users.users);

    };

    settings.reverse_tunnel.relay.tunneller.keyFiles =
      mapAttrsToList (name: _: toKeyPath name)
        (filterAttrs (_: user: user.canTunnel) config.settings.users.users);

  };

}
