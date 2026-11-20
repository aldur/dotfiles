{
  lib,
  stdenv,
  jdk_headless,
}:

# The agent logic of the Android app, as a jar for a desktop JVM. The check
# of the guest module runs it against the bridge and OpenSSH.
stdenv.mkDerivation {
  pname = "avf-ssh-agent-core";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./src;
  };

  nativeBuildInputs = [ jdk_headless ];

  buildPhase = ''
    runHook preBuild
    find src/main/java -name '*.java' > main.txt
    javac --release 17 -Xlint:all -Werror -d classes @main.txt
    jar --create --file avf-ssh-agent-core.jar -C classes .
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    find src/test/java -name '*.java' > test.txt
    javac --release 17 -cp classes -d test-classes @test.txt
    java -ea -cp classes:test-classes io.github.aldur.avfsshagent.core.AllTests
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -D -m 644 avf-ssh-agent-core.jar $out/share/java/avf-ssh-agent-core.jar
    runHook postInstall
  '';

  meta.platforms = lib.platforms.linux;
}
