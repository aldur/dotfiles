{ buildGoModule, fetchFromGitHub }:
buildGoModule {
  pname = "llmcat";
  version = "0.0.7-unstable-2025-03-22";
  src = fetchFromGitHub {
    owner = "everestmz";
    repo = "llmcat";
    rev = "950be582c022f8245b0caa74b53d76a39609c600";
    hash = "sha256-yV+LaLWVhgwHQj69K/KbI6OX+itBxbM9EtRazB1HlkI=";
  };

  vendorHash = "sha256-lRIR6UubOi613KUn+IFv8kjK8HkTvYluhO3H94/TbsQ=";
}
