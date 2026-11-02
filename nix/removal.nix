# SPDX-License-Identifier: MIT
{ pkgs }:
let
  upstream = import ./upstream.nix { inherit pkgs; };
  root = upstream + "/woof-code/rootfs-skeleton";
in
pkgs.runCommand "petget-removal-with-adapter-preflight" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    mkdir -p $out/libexec $out/share/licenses/petget $out/share/src/petget
    cp ${root}/usr/local/petget/removepreview.sh $out/libexec/removepreview.sh
    cp ${root}/usr/local/petget/removepreview.sh $out/share/src/petget/removepreview.sh.original
    cp ${root}/usr/share/doc/legal/lgpl-2.1.txt $out/share/licenses/petget/COPYING.LESSER
    chmod u+w $out/libexec/removepreview.sh
  python3 - "$out/libexec/removepreview.sh" <<'PY'
  import sys
  from pathlib import Path
  path = Path(sys.argv[1])
  source = path.read_text()
  start = source.index('#any user-installed deps?...')
  end = source.index('#131221 131222\n#check install history', start)
  source = source[:start] + '# Modified by nix-impurifiers: the adapter checks reverse dependencies\n# before any removal. The upstream forward-dependency check ran after deletion.\n' + source[end:]
  path.write_text(source)
  PY
    chmod 755 $out/libexec/removepreview.sh
''
