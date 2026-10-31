{ ghToken }:
{
  description = "Run GitHub CLI with an age-encrypted token";
  wraps = "gh";
  body = ''
    set -l token (${ghToken}/bin/gh-token)
    or return $status
    if test (count $token) -ne 1; or test -z "$token"
        echo "ghs: no access token returned" >&2
        return 1
    end
    set -lx GH_TOKEN "$token"
    command gh $argv
  '';
}
