# SPDX-License-Identifier: MIT
{ pkgs, coreSrc }:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "petget-impurifier";
    sourceInfo = coreSrc;
  };
  buildPet =
    {
      name,
      version,
      payload,
      release ? "1",
      dependencies ? [ ],
      description ? "Nix projected application",
      scripts ? { },
    }:
    assert lib.assertMsg (lib.all (s: builtins.match "[a-z0-9][a-z0-9+.-]*" s != null) (
      [
        name
        version
        release
      ]
      ++ dependencies
    )) "invalid PET identity or dependency";
    assert lib.assertMsg (builtins.match "[^|\n\r]+" description != null) "invalid PET description";
    assert lib.assertMsg (lib.all (
      s:
      lib.elem s [
        "pinstall"
        "puninstall"
      ]
    ) (builtins.attrNames scripts)) "invalid PET script";
    let
      fullName = "${name}-${version}-${release}";
    in
    pkgs.runCommand "${fullName}-pet"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
          pkgs.coreutils
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru = { inherit name version fullName; };
      }
      ''
        mkdir -p "${fullName}" "$out"
        cp -r ${payload}/. "${fullName}/"
        chmod -R u+w "${fullName}"
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (phase: script: ''
            install -m755 ${script} "${fullName}/${phase}.sh"
          '') scripts
        )}
        cp ${pkgs.writeText "pet.specs" "${fullName}|${name}|${version}|${release}|Utility|1K||${fullName}.pet|${lib.concatMapStringsSep "," (d: "+${d}") dependencies}|${description}|any|any||\n"} "${fullName}/pet.specs"
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -cf - "${fullName}" | gzip -n > "$out/${fullName}.pet"
        md5sum "$out/${fullName}.pet" | cut -c1-32 | tr -d '\n' >> "$out/${fullName}.pet"
      '';
  removal = import ./removal.nix { inherit pkgs; };
  phase = pkgs.writeText "pet-phase" "#!/bin/sh\nexec /usr/sbin/petget-impurifier-activate\n";
  makeRuntimePet =
    {
      nixDependency ? "nix",
      pythonDependency ? "python3",
      version ? core.runtimeVersion,
    }:
    buildPet {
      name = "petget-impurifier";
      inherit version;
      dependencies = [
        nixDependency
        pythonDependency
      ];
      scripts = {
        pinstall = phase;
        puninstall = phase;
      };
      payload = pkgs.runCommand "petget-runtime" { } ''
        cp -r ${core.makeRuntimeTree { }} $out
        chmod -R u+w $out
        install -Dm755 ${../src/activate.py} $out/usr/sbin/petget-impurifier-activate
        install -Dm755 ${../src/adapter.py} $out/usr/sbin/petget-impurifier
        cp -r ${removal}/libexec/. $out/usr/lib/petget-impurifier/
        cp -r ${removal}/share/. $out/usr/share/
        mkdir -p $out/usr/share/petget-impurifier
        echo '${version}' > $out/usr/share/petget-impurifier/runtime-version
      '';
    };
  makePet =
    args@{
      pkg,
      hostDependencies ? [ ],
      ...
    }:
    assert lib.assertMsg (
      (args.systemd or null) == null && (args.openrc or null) == null && (args.runit or null) == null
    ) "PET service startup remains native Puppy policy; no systemd/OpenRC/runit backend is assumed";
    let
      application = core.makePayload (
        (builtins.removeAttrs args [ "hostDependencies" ]) // { hostBackend = "openrc"; }
      );
      payload = pkgs.runCommand "pet-application" { } ''
        cp -r ${application} $out
        chmod -R u+w $out
        mkdir -p $out/usr/share/petget-impurifier/requirements
        echo '${core.runtimeVersion}' > $out/usr/share/petget-impurifier/requirements/${application.name}
      '';
    in
    buildPet {
      name = application.name;
      inherit (application) version description;
      release = if application.offline then "offline" else "net";
      inherit payload;
      dependencies = [ "petget-impurifier" ] ++ hostDependencies;
      scripts = {
        pinstall = phase;
        puninstall = phase;
      };
    };
in
{
  inherit buildPet makePet makeRuntimePet;
  makeNetPet = args: makePet (args // { offline = false; });
  makeOfflinePet = args: makePet (args // { offline = true; });
  makePackage = args: {
    net = makePet (args // { offline = false; });
    offline = makePet (args // { offline = true; });
  };
  runtimePet = makeRuntimePet { };
  inherit (core) unit;
}
