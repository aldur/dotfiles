# tcpstates of the libbpf-tools in bcc. Nixpkgs packages only the Python
# tools of bcc, and their tcpstates has other column names. The source of
# bcc in Nixpkgs has no submodules, so this uses libbpf and bpftool of
# Nixpkgs.
{
  bcc,
  bpftools,
  elfutils,
  libbpf,
  llvmPackages,
  stdenv,
  zlib,
}:
stdenv.mkDerivation {
  pname = "tcpstates-libbpf";
  inherit (bcc) version src;
  sourceRoot = "${bcc.src.name}/libbpf-tools";

  nativeBuildInputs = [
    bpftools
    # The compiler wrapper adds flags that the BPF target does not accept.
    llvmPackages.clang-unwrapped
    llvmPackages.llvm
  ];
  buildInputs = [
    elfutils
    libbpf
    zlib
  ];

  makeFlags = [
    "BPFTOOL=bpftool"
    "LIBBPF_OBJ=${libbpf}/lib/libbpf.a"
    "USE_BLAZESYM=0"
  ];
  preBuild = ''
    makeFlagsArray+=("INCLUDES=-I$PWD/.output -I${libbpf}/include")
  '';
  buildFlags = [ "tcpstates" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 tcpstates $out/bin/tcpstates
    runHook postInstall
  '';

  meta = {
    inherit (bcc.meta) license platforms;
    mainProgram = "tcpstates";
  };
}
