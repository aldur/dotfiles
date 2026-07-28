{
  vimUtils,
  fetchFromGitHub,
}:

vimUtils.buildVimPlugin {
  pname = "clarity.nvim";
  version = "0.2.0-unstable-2026-07-28";

  src = fetchFromGitHub {
    owner = "aldur";
    repo = "clarity.nvim";
    rev = "5c9d8accc29e0262fd9fb2013e1dc45b01bcba1e";
    hash = "sha256-EGrC3wY+WCOykYMJnPqeK6IrcGzByIe7hP8ktdXA2sI=";
  };

  doCheck = false; # Missing runtime dependencies for "require" check
}
