# SPDX-License-Identifier: MIT
{ ... }:
{ lib, inputs, ... }: {
  flake.lib = lib.mkForce {
    petget-impurifier =
      { pkgs }:
      import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
    in
    {
      packages = {
        default = impurifier.runtimePet;
        runtime-pet = impurifier.runtimePet;
        hello-net-pet = impurifier.makeNetPet { pkg = pkgs.hello; };
        hello-offline-pet = impurifier.makeOfflinePet { pkg = pkgs.hello; };
      };
      formatter = pkgs.nixfmt-tree;
      checks =
        (import ../../../tests {
          inherit pkgs impurifier;
          coreSrc = inputs.impurifier;
        })
        // {
          bundled-vm =
            (import ../../../tests {
              inherit pkgs;
              coreSrc = inputs.impurifier;
              bundled = true;
              impurifier =
                let
                  wrap =
                    args:
                    impurifier.makeRuntimePet (
                      args
                      // {
                        bundledNixStore = "${
                          import (inputs.impurifier + "/tests/static-nix.nix") { inherit pkgs; }
                        }/bin/nix-store";
                        bundledNixNotices = [ "${pkgs.nix.src}/COPYING" ];
                      }
                    );
                in
                impurifier
                // {
                  makeRuntimePet = wrap;
                  runtimePet = wrap { };
                };
            }).native-vm;
        };
    };
}
