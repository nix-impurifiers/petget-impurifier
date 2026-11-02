# Third-party material

Original code in this repository is MIT. Tests fetch Woof-CE revision
`cdaa9335d9bc3916e279560c5111d976adec3a94` from
https://github.com/puppylinux-woof-CE/woof-CE.

PETget's installpkg.sh and removepreview.sh retain their upstream Barry Kauler
copyright and "2009 Lesser GPL licence v2" notices. Other Woof-CE components
retain their individual notices. Installation scripts are used unmodified.
The runtime includes a private
removepreview.sh with its incorrect late forward-dependency check removed;
the MIT adapter checks reverse dependencies before native removal. The runtime
ships the original script and LGPL 2.1 text alongside the modified shell source.
See nix/removal.nix for the exact reproducible patch; this repository's MIT
license does not relicense them. Test artifacts also include packages under their own upstream licenses.
