{ buildGoModule, fetchFromGitHub }:
buildGoModule (finalAttrs: {
  pname = "llmcat";
  version = "0.0.7";
  src = fetchFromGitHub {
    owner = "everestmz";
    repo = "llmcat";
    tag = "v${finalAttrs.version}";
    hash = "sha256-yV+LaLWVhgwHQj69K/KbI6OX+itBxbM9EtRazB1HlkI=";
  };

  vendorHash = "sha256-lRIR6UubOi613KUn+IFv8kjK8HkTvYluhO3H94/TbsQ=";

  passthru.updatePin = { };
})
