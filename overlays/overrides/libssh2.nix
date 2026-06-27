# Patch nixpkgs' libssh2 (1.11.1) for CVE-2026-55200 (pre-auth OOB write / RCE in
# ssh2_transport_read) and CVE-2026-55199 (pre-auth DoS in the SSH_MSG_EXT_INFO
# handler). As of 2026-06-25 there is no libssh2 release past 1.11.1 and nixpkgs
# still ships it unpatched (NixOS/nixpkgs#532920).
#
# Two constraints shape this file:
#
# 1. We patch the 1.11.1 tarball rather than building from the fixed upstream
#    commits. libssh2 is in curl's closure, and curl backs `fetchurl`; nixpkgs
#    only breaks the resulting fetchurl -> curl -> libssh2 cycle by building a
#    bootstrap libssh2 with `fetchurl = stdenv.fetchurlBoot`. The git tree ships
#    no ./configure, so a source build needs autoreconf, whose deps are fetched
#    via the regular fetchurl -> re-entering that cycle (infinite recursion at
#    eval time). The release tarball carries ./configure, so it stays cycle-free.
#
# 2. The patches are fetched with fetchTree, i.e. Nix's *native* fetcher
#    (its own libcurl, not nixpkgs curl). A nixpkgs fetchurl/fetchpatch FOD would
#    itself be realised via curl -> libssh2 and re-trigger the same cycle; the
#    native fetch does not. Hashes are pinned inline here, not in flake.lock.
final: prev:
let
  # CVE-2026-55199 fix (src/packet.c EXT_INFO handler). Applies to 1.11.1 as-is.
  cve55199 = fetchTree {
    type = "file";
    url = "https://github.com/libssh2/libssh2/commit/17626857d20b3c9a1addfa45979dadcee1cd84a4.patch";
    narHash = "sha256-MBJw+OOKt1A6ko+NWpKXCCbweRy5mGRdRCS3jl4/56o=";
  };

  # CVE-2026-55200 fix (src/transport.c). The upstream commit was authored after
  # _libssh2_ntohu32 was renamed to ssh2_ntohu32, so its context does not match
  # 1.11.1; rename it back so the hunk applies. runCommand uses stdenv/sed (no
  # curl), so it does not re-enter the bootstrap cycle.
  cve55200Upstream = fetchTree {
    type = "file";
    url = "https://github.com/libssh2/libssh2/commit/97acf3dfda80c91c3a8c9f2372546301d4a1a7a8.patch";
    narHash = "sha256-NOxXbEAENN3jBRBy97OPCHISclAn2+PvqxaqnaRf6Ew=";
  };
  cve55200 = prev.runCommand "libssh2-CVE-2026-55200-1.11.1.patch" { } ''
    sed 's/ssh2_ntohu32/_libssh2_ntohu32/g' ${cve55200Upstream} > $out
  '';
in
{
  # The tripwire is deferred *inside* this attribute on purpose: a top-level
  # `assert` would force prev.libssh2 while the overlay stage is being stacked,
  # which sends nixpkgs' by-name overlay into infinite recursion. It is only
  # forced once something evaluates libssh2 (the system always does, via
  # curl/git/etc.), by which point the package-set fixpoint exists.
  libssh2 =
    let
      upstream = prev.libssh2;

      # Tripwire: fail the build the moment nixpkgs changes its own libssh2 -- a
      # version bump past 1.11.1, or any change to its patch set (e.g. a
      # backported fix). Either signals that nixpkgs likely carries these fixes
      # now and this override should be re-evaluated and deleted.
      upstreamUnchanged = upstream.version == "1.11.1" && builtins.length (upstream.patches or [ ]) == 1;
    in
    assert prev.lib.assertMsg upstreamUnchanged ''
      overlays/overrides/libssh2.nix: nixpkgs's libssh2 changed
      (version=${upstream.version}, patches=${toString (builtins.length (upstream.patches or [ ]))}).
      It may now carry these fixes on its own -- re-check NixOS/nixpkgs#532920
      and delete this override if it is no longer needed.
    '';
    upstream.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        cve55199
        cve55200
      ];
    });
}
