# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
  bundled ? false,
}:
let
  nativeProof = pkgs.pkgsStatic.stdenv.mkDerivation {
    name = "native-static-proof";
    dontUnpack = true;
    buildPhase = ''
      cat > proof.c <<'C'
      #include <stdio.h>
      int main(void) { puts("Hello from native payload"); return 0; }
      C
      $CC proof.c -o proof
    '';
    installPhase = "mkdir -p $out/bin; cp proof $out/bin/";
  };
  upstream = import ../nix/upstream.nix { inherit pkgs; };
  rootfs = upstream + "/woof-code/rootfs-skeleton";
  pet =
    version:
    impurifier.makeNativePet {
      name = "pet-tool";
      inherit version;
      payload = pkgs.runCommand "pet-test-payload" { } ''
        mkdir -p $out/usr/share/pet-test $out/etc $out/usr/libexec/native-pet
        cp ${nativeProof}/bin/proof $out/usr/libexec/native-pet/proof
        echo ${version} > $out/usr/share/pet-test/version
        echo ${version} > $out/etc/pet-test.conf
      '';
      scripts.pinstall = pkgs.writeText "pinstall.sh" "echo installed > /var/pet-install-marker\n";
      scripts.puninstall = pkgs.writeText "puninstall.sh" "echo removed > /var/pet-remove-marker\n";
    };
  tool =
    version:
    pkgs.runCommand "pet-profile-tool-${version}"
      {
        pname = "pet-profile-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/pet-profile-tool
        chmod 755 $out/bin/pet-profile-tool
      '';
  app =
    offline: version:
    impurifier.makePet {
      pkg = tool version;
      inherit offline;
      users.pet-worker = { };
      directories."/var/lib/pet-worker" = {
        owner = "pet-worker:pet-worker";
        mode = "0750";
      };
      lifecycle = {
        onInstall = "test -x /opt/nix/profile/bin/pet-profile-tool; echo initialized > /var/lib/pet-worker/initialized";
        onUpgrade = "test ! -f /var/lib/pet-worker/fail; echo ${version} > /var/lib/pet-worker/migrated";
      };
    };
  fixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  driver =
    version:
    impurifier.buildPet {
      name = "host-driver";
      inherit version;
      payload = fixture.driver version;
    };
  hardware = impurifier.makeOfflinePet {
    pkg = fixture.tool;
    inherit (fixture) hardware;
    hostDependencies = [ "host-driver" ];
  };
  runtime = impurifier.runtimePet;
  legacy = impurifier.makeRuntimePet { version = "0.1"; };
  provider = impurifier.buildPet {
    name = "nix";
    version = "1";
    payload =
      pkgs.runCommand "fixture-native-nix-provider" { }
        "mkdir -p $out/usr/share/impurifier-vm; echo preinstalled > $out/usr/share/impurifier-vm/nix";
  };
  pythonProvider = impurifier.buildPet {
    name = "python3";
    version = "1";
    payload =
      pkgs.runCommand "fixture-native-python-provider" { }
        "mkdir -p $out/usr/share/impurifier-vm; echo preinstalled > $out/usr/share/impurifier-vm/python";
  };
in
{
  native-vm = pkgs.testers.runNixOSTest {
    name = "petget-native-contract";
    requiredFeatures = {
      kvm = false;
      devnet = false;
    };
    nodes.machine = { lib, ... }: {
      nix.settings.substituters = lib.mkForce [ ];
      nix.settings.builders = lib.mkForce "";
      virtualisation.memorySize = 2048;
      virtualisation.useNixStoreImage = true;
      virtualisation.writableStore = true;
      systemd.tmpfiles.rules = [
        "d /usr/bin 0755 root root -"
        "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
        "L+ /usr/bin/nix-store - - - - ${
          if bundled then
            pkgs.writeShellScript "incompatible-nix-store" "echo incompatible; exit 1"
          else
            "${pkgs.nix}/bin/nix-store"
        }"
        "L+ /usr/bin/nix - - - - ${pkgs.nix}/bin/nix"
      ];
      virtualisation.qemu.package = lib.mkForce pkgs.qemu;
      virtualisation.qemu.forceAccel = false;
      environment.systemPackages = [
        pkgs.nix
        pkgs.python3
        pkgs.shadow
        pkgs.bash
        pkgs.gnutar
        pkgs.gzip
        pkgs.file
        pkgs.gettext
        pkgs.busybox
        pkgs.procps
        pkgs.findutils
        pkgs.gnused
        pkgs.gnugrep
        pkgs.xorg-server
      ];
      environment.etc."DISTRO_SPECS".text =
        "DISTRO_BINARY_COMPAT=impurifier-vm\nDISTRO_COMPAT_VERSION=1\n";
      environment.etc."plogin".text = "root\n";
      environment.etc."xdg/menus/hierarchy".source = rootfs + "/etc/xdg/menus/hierarchy";
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      def succeed(command):
          return machine.succeed("export PATH=/usr/sbin:/usr/bin:$PATH; " + command)
      def fail(command):
          return machine.fail("export PATH=/usr/sbin:/usr/bin:$PATH; " + command)
      succeed("mkdir -p /usr/local/petget /usr/sbin /usr/bin /var/packages /var/local/petget /tmp/petget_proc /etc/rc.d")
      succeed("for p in /run/current-system/sw/bin/*; do test -e /usr/bin/$(basename $p) || ln -s $p /usr/bin/; done; ln -s ${pkgs.bash}/bin/bash /bin/bash; ln -s /usr/bin/useradd /usr/sbin/useradd; ln -s /usr/bin/groupadd /usr/sbin/groupadd")
      succeed("cp -r ${rootfs}/usr/local/petget/. /usr/local/petget/; cp ${rootfs}/usr/bin/pet2tgz /usr/bin/; chmod +x /usr/bin/pet2tgz")
      succeed("touch /var/packages/user-installed-packages /var/packages/DISTRO_PKGS_SPECS /tmp/petget_proc/install_quietly /tmp/petget_proc/remove_pets_quietly; echo true > /var/local/petget/nt_category")
      succeed("cp ${pet "1"}/pet-tool-1-1.pet /tmp/; bash /usr/local/petget/installpkg.sh /tmp/pet-tool-1-1.pet > /tmp/install.log 2>&1 || { cat /tmp/install.log; exit 1; }")
      succeed("cat /tmp/install.log; grep '^1$' /usr/share/pet-test/version; grep '^pet-tool-1-1|' /var/packages/user-installed-packages; grep installed /var/pet-install-marker")
      succeed("mkdir -p /srv/native/usr/libexec/native-pet; cp /usr/libexec/native-pet/proof /srv/native/usr/libexec/native-pet/proof; chroot /srv/native /usr/libexec/native-pet/proof | grep Hello")
      succeed("test ! -e /srv/native/nix && test ! -e /usr/sbin/petget-impurifier-activate")
      succeed("echo customized > /etc/pet-test.conf; cp ${pet "2"}/pet-tool-2-1.pet /tmp/; bash /usr/local/petget/installpkg.sh /tmp/pet-tool-2-1.pet > /tmp/upgrade.log 2>&1")
      succeed("grep '^2$' /usr/share/pet-test/version; grep '^2$' /etc/pet-test.conf; test $(wc -l < /var/packages/user-installed-packages) = 1")
      succeed("Xvfb :99 -screen 0 640x480x24 > /tmp/xvfb.log 2>&1 &")
      succeed("DISPLAY=:99 TREE2=pet-tool-2-1 bash /usr/local/petget/removepreview.sh > /tmp/remove.log 2>&1")
      machine.wait_until_succeeds("grep removed /var/pet-remove-marker")
      succeed("test ! -e /usr/share/pet-test/version; test ! -e /etc/pet-test.conf; test ! -s /var/packages/user-installed-packages; test ! -e /usr/libexec/native-pet/proof")
      def native_install(package):
          succeed(f"cp {package}/*.pet /tmp/; for p in /tmp/*.pet; do bash /usr/local/petget/installpkg.sh \"$p\" >> /tmp/native.log 2>&1 || {{ cat /tmp/native.log; exit 1; }}; done")
      native_install("${provider}")
      native_install("${pythonProvider}")
      native_install("${runtime}")
      succeed("test -x /usr/sbin/petget-impurifier; test ! -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
      fail("petget-impurifier install ${app false "1"}/*.pet > /tmp/net.log 2>&1")
      succeed("petget-impurifier install ${app true "1"}/*.pet > /tmp/offline.log 2>&1 || { cat /tmp/offline.log; exit 1; }")
      succeed("test $(/opt/nix/profile/bin/pet-profile-tool) = 1; id pet-worker; test $(stat -c %a /var/lib/pet-worker) = 750; grep initialized /var/lib/pet-worker/initialized")
      native_install("${legacy}")
      fail("petget-impurifier reconcile")
      succeed("test $(/opt/nix/profile/bin/pet-profile-tool) = 1")
      native_install("${runtime}")
      succeed("petget-impurifier reconcile")
      succeed("echo preserved > /var/lib/pet-worker/initialized; petget-impurifier install ${app true "1"}/*.pet; grep preserved /var/lib/pet-worker/initialized")
      fail("petget-impurifier install ${app true "1"}/*.pet ${app false "1"}/*.pet")
      succeed("cp ${app true "1"}/*.pet /tmp/corrupt.pet; printf broken >> /tmp/corrupt.pet")
      fail("petget-impurifier install /tmp/corrupt.pet")
      succeed("rm /tmp/corrupt.pet")
      succeed("touch /var/lib/pet-worker/fail")
      fail("petget-impurifier install ${app true "2"}/*.pet > /tmp/failed-upgrade.log 2>&1")
      succeed("rm /var/lib/pet-worker/fail; petget-impurifier install ${app true "2"}/*.pet; test $(/opt/nix/profile/bin/pet-profile-tool) = 2; grep 2 /var/lib/pet-worker/migrated")
      fail("petget-impurifier install ${hardware}/*.pet")
      succeed("petget-impurifier install ${driver "1"}/*.pet ${hardware}/*.pet > /tmp/hardware.log 2>&1 || { cat /tmp/hardware.log; exit 1; }")
      succeed("test $(/opt/nix/profile/bin/hardware-tool) = 1")
      succeed("petget-impurifier install ${driver "2"}/*.pet; test $(/opt/nix/profile/bin/hardware-tool) = 2")
      fail("DISPLAY=:99 petget-impurifier remove host-driver")
      succeed("test $(/opt/nix/profile/bin/hardware-tool) = 2; test -f /usr/lib/libimpurifier-driver.so.1")
      succeed("DISPLAY=:99 petget-impurifier remove hardware-tool host-driver")
      succeed("nix-collect-garbage; test $(/opt/nix/profile/bin/pet-profile-tool) = 2")
      fail("ROOT=/foreign petget-impurifier reconcile")
      succeed("DISPLAY=:99 petget-impurifier remove pet-profile-tool > /tmp/managed-remove.log 2>&1 || { cat /tmp/managed-remove.log; exit 1; }")
      succeed("test ! -e /opt/nix/profile/bin/pet-profile-tool; test -f /var/lib/pet-worker/initialized")
    '';
  };
}
