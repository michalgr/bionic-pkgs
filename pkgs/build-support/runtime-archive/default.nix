# pkgs/build-support/runtime-archive/default.nix
# High-level derivation helper for computing package closures and staging runtime archives.

{
  lib,
  stdenv,
  bash,
  makeArchive,
  stageRuntimeScript ? ../../../scripts/stage-runtime.sh,
  generateLauncher ? ../../../scripts/generate-launcher.sh,
}:

{
  pname,
  version ? "1.0.0",
  packages ? [ ],
  launcherProgram ? null,
  launcherName ? null,
  targetArch ? stdenv.hostPlatform.parsed.cpu.name,
  archiveName ? "${pname}-${targetArch}.tar.gz",
  compression ? "gzip",
  meta ? { },
}:

let
  isPlatformPkg = p:
    let name = p.name or (p.pname or "");
    in lib.hasInfix "bionic" name;

  getDirectDeps = p:
    if lib.isDerivation p then
      lib.filter (d: lib.isDerivation d && d ? outPath) (
        (p.buildInputs or [ ]) ++ (p.propagatedBuildInputs or [ ])
      )
    else [ ];

  closeRuntimeClosure = pkgs:
    let
      step = current:
        let
          deps = lib.concatMap getDirectDeps current;
          next = lib.unique (current ++ deps);
        in
          if builtins.length next == builtins.length current then
            current
          else
            step next;
    in
      step pkgs;

  libcxxPkgs = lib.optional (stdenv.cc ? libcxx && stdenv.cc.libcxx != null) stdenv.cc.libcxx;

  allPackages = lib.filter (p: !isPlatformPkg p) (
    closeRuntimeClosure (packages ++ libcxxPkgs)
  );

  getRuntimeOutputs = pkg:
    if lib.isDerivation pkg then
      let
        available = lib.filter (out: pkg ? ${out}) [ "out" "bin" "lib" ];
      in
        if available != [ ] then map (out: pkg.${out}) available else [ pkg ]
    else
      [ pkg ];

  packagePaths = lib.unique (map (p: "${p}") (lib.concatMap getRuntimeOutputs allPackages));

  stagedDir = stdenv.mkDerivation {
    pname = "${pname}-staged-${targetArch}";
    inherit version packagePaths;

    nativeBuildInputs = [ bash ];

    buildCommand = ''
      bash ${stageRuntimeScript} \
        --stage "$out" \
        --generate-launcher ${generateLauncher} \
        ${lib.optionalString (launcherProgram != null) "--launcher ${launcherProgram}"} \
        ${lib.optionalString (launcherName != null) "--launcher-name ${launcherName}"} \
        $packagePaths
    '';

    meta = {
      platforms = lib.platforms.linux;
      skipElfCheck = true;
    };
  };
in
makeArchive {
  inherit pname version archiveName compression;
  src = stagedDir;
  meta = {
    description = "Android ${pname} runtime bundle archive (${targetArch})";
    homepage = "https://github.com/michalgr/bionic-pkgs";
    license = lib.licenses.mit;
  } // meta;
}
