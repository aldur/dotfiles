{ buildGoModule, fetchFromGitHub }:
buildGoModule rec {
  name = "llmcat";
  version = "950be582c022f8245b0caa74b53d76a39609c600";
  src = fetchFromGitHub {
    owner = "everestmz";
    repo = name;
    rev = version;
    hash = "sha256-yV+LaLWVhgwHQj69K/KbI6OX+itBxbM9EtRazB1HlkI=";
  };

  vendorHash = "sha256-lRIR6UubOi613KUn+IFv8kjK8HkTvYluhO3H94/TbsQ=";
}
