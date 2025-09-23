{ pkgs, ... }:
{
  users.users.aldur = {
    shell = pkgs.fish;
  };
}
