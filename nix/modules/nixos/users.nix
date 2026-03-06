_: {
  users.users.aldur = {
    extraGroups = [ "wheel" ];
    isNormalUser = true;
    homeMode = "700";
  };

  users.mutableUsers = false;
}
