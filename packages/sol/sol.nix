{ buildGoModule, fetchFromGitHub }:
{
  sol = buildGoModule rec {
    name = "sol";
    version = "7762c5115dd899bfac10d2f46d066de3c0e81774";
    src = fetchFromGitHub
      {
        owner = "noperator";
        repo = "sol";
        rev = "${version}";
        hash = "sha256-0k/LdWWBBxGDtrnkG69lctvPdwie8s3ckICCZ4ERa2M=";
      };

    vendorHash = "sha256-syWp/8JG2ikzvTrin9UfLPf7YEFvz3P0N2QzPDklkWg=";
  };
}
