{ modulesPath,config, ... }: {
  imports = [ "${modulesPath}/virtualisation/amazon-image.nix" ];
  ec2.hvm = true;
networking.hostName = "sshrelay1";

}