{
  vimUtils,
  fetchFromGitHub,
}:

vimUtils.buildVimPlugin {
  pname = "link.vim";
  version = "2.0.3-unstable-2026-03-09";

  src = fetchFromGitHub {
    owner = "qadzek";
    repo = "link.vim";
    rev = "53e09621fc0dcee54e3231422029be19dab75018";
    hash = "sha256-YjKFDv9QyuWDfWiKP6EvjSRbkz/K6e/Neq76ckghKh0=";
  };
}
