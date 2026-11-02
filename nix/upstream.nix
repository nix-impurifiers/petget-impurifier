# SPDX-License-Identifier: MIT
{ pkgs }:
pkgs.fetchFromGitHub {
  owner = "puppylinux-woof-CE";
  repo = "woof-CE";
  rev = "cdaa9335d9bc3916e279560c5111d976adec3a94";
  hash = "sha256-vttjAxSAlY41reyvgJphVMdYfvhYGZgnIspQNnVz+Hc=";
}
