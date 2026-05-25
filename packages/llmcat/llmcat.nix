{ buildGoModule, fetchFromGitHub }:
buildGoModule rec {
  name = "llmcat";
  version = "c1092576f26465945520100b9f27a9b47cd89d1d";
  src = fetchFromGitHub {
    owner = "everestmz";
    repo = name;
    rev = version;
    hash = "sha256-0kj1ADmfAhPOBh4sy/SQ+8oHZSaE2elrJX87lJo0c8I=";
  };

  vendorHash = "sha256-e0WdB61YJm26e93q04sfhMogmYT+V19GSabDqSwiq5g=";
}
