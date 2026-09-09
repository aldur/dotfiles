# The kernel that Baguette boots: the ChromeOS VM kernel, built from the
# public ChromeOS kernel tree with its termina configuration. ChromeOS
# publishes no binary of it. The image ships no kernel, so a boot check
# that wants the real one builds this. `rev` should follow the release
# that the Chromebook runs; `uname -r` in the guest shows the version.
{
  lib,
  stdenv,
  fetchFromGitiles,
  bc,
  bison,
  cpio,
  elfutils,
  flex,
  gmp,
  libmpc,
  mpfr,
  openssl,
  pahole,
  perl,
  python3Minimal,
  zlib,
  zstd,
}:
let
  isX86 = stdenv.hostPlatform.isx86_64;
  arch = if isX86 then "x86_64" else "arm64";
  flavour = "container-vm-${arch}";
  image = if isX86 then "arch/x86/boot/bzImage" else "arch/arm64/boot/Image";
in
stdenv.mkDerivation {
  pname = "termina-kernel";
  # The head of the chromeos-6.6 branch on 2026-09-09.
  version = "6.6.147-chromeos";

  src = fetchFromGitiles {
    url = "https://chromium.googlesource.com/chromiumos/third_party/kernel";
    rev = "a91057729ac86a115c514334de6fde7f715ee8b7";
    hash = "sha256-wTz19Bly3o255VfDYaQWp1H+9vIJL7sEH5Ykkjxe5yk=";
  };

  nativeBuildInputs = [
    bc
    bison
    cpio
    elfutils
    flex
    gmp
    libmpc
    mpfr
    openssl
    pahole
    perl
    python3Minimal
    zlib
    zstd
  ];

  # The kernel sets its own compiler flags.
  hardeningDisable = [ "all" ];
  enableParallelBuilding = true;
  makeFlags = [
    "ARCH=${arch}"
    "KBUILD_BUILD_USER=nixbld"
    "KBUILD_BUILD_HOST=nixos"
  ];

  postPatch = ''
    patchShebangs scripts chromeos/scripts
  '';

  # prepareconfig concatenates the split configuration of ChromeOS:
  # chromeos/config/termina/{base,<arch>/common,<arch>/<flavour>.flavour}.config.
  configurePhase = ''
    runHook preConfigure
    export KBUILD_BUILD_TIMESTAMP="$(date -u -d @$SOURCE_DATE_EPOCH)"
    CHROMEOS_KERNEL_FAMILY=termina bash chromeos/scripts/prepareconfig ${flavour} .config
    make $makeFlags olddefconfig
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make $makeFlags -j$NIX_BUILD_CORES ${baseNameOf image}
    runHook postBuild
  '';

  # `kernel` whatever the architecture, so the caller needs no case.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp ${image} $out/kernel
    cp .config $out/config
    cp include/config/kernel.release $out/release
    runHook postInstall
  '';

  passthru.updatePin = {
    # nix-update knows no gitiles source. To bump: take the commit from
    # https://chromium.googlesource.com/chromiumos/third_party/kernel/+log/refs/heads/chromeos-6.6?format=JSON&n=1
    # set `rev` and `version` (VERSION.PATCHLEVEL.SUBLEVEL of its Makefile),
    # clear `hash`, and build `.#termina-kernel` for the new hash.
    exempt = "fetchFromGitiles: nix-update has no gitiles support; see the comment";
  };

  meta = {
    description = "The ChromeOS VM (termina) kernel that Baguette boots";
    homepage = "https://chromium.googlesource.com/chromiumos/third_party/kernel";
    license = lib.licenses.gpl2Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
