# petget-impurifier

Build Puppy PET packages that let native PETget own host files and metadata,
while a transactional, garbage-collector-rooted Nix profile supplies programs.
Original code is MIT. Nix itself and Python must already be available; a native
Nix provider/installer is deferred work.

```nix
let
  pet = inputs.petget-impurifier.lib.petget-impurifier { inherit pkgs; };
in {
  runtime = pet.makeRuntimePet {
    nixDependency = "my-nix-provider";
    pythonDependency = "python3";
  };
  app = pet.makeOfflinePet {
    pkg = pkgs.hello;
    configFiles."/etc/hello.conf" = pkgs.writeText "hello.conf" "example\n";
  };
}
```

Outputs are directories containing canonical `name-version-release.pet` files.
PET's compressed tar stream carries its native MD5 footer. This checksum is a
format requirement, not an authenticity guarantee: obtain packages from trusted
sources. The application package has one stable native logical name, with `net`
and `offline` native release identifiers; PETget performs the native replacement.

Install the runtime using native PPM first. Then, as root:

```
petget-impurifier install /path/to/hello-2.12.2-offline.pet
petget-impurifier reconcile
petget-impurifier remove hello
```

The adapter calls native `installpkg.sh` and a narrowly patched
`removepreview.sh`. The pinned upstream removal helper checks forward
dependencies as if they were reverse dependencies, after deleting files. The
adapter instead checks reverse dependencies before invoking removal; its private
copy omits that incorrect late check. Other native removal behavior is retained.
It copies archives first because native `pet2tgz` normally deletes its input. Exact-name dependencies are checked against PETget's installed
package databases. It does not replace PPM's repository solver, GUI, richer
dependency expressions, or confirmation policy. Native removal needs a working
interactive terminal or the host's real display/quiet configuration.

Post-install scripts and asynchronous post-remove scripts do not reliably report
activation failure to ordinary PPM callers. The adapter reconciles after the
native operation and returns activation errors. A failed activation leaves native
package ownership intact; repair the cause and run `reconcile`. Repeating an
already installed archive through the adapter retries activation. Numeric runtime
minimums are checked before activating any selected application.

Native PETget full-install mode overwrites configuration during upgrades and
removes edited configuration during uninstall. Its native inventory owns those
files; copy customizations elsewhere before replacement. Declared data
directories and accounts survive uninstall. CLI applications, account/directory
preparation, lifecycle hooks and host-library snapshots use the shared engine.
Service declarations are rejected: this backend does not assume that Puppy uses
systemd, OpenRC or runit. Native service integration remains future work.

`buildPet` also emits ordinary native packages with an arbitrary payload and
optional `pinstall`/`puninstall` scripts. This permits independent native dependency
providers, including a future Nix installer package. It is not itself an installer.

The VM runs pinned upstream Woof-CE PETget install scripts and the disclosed removal patch on a full-install
filesystem with actual native tools and Xvfb. It tests native archive checks,
metadata, upgrade/removal behavior and the Nix-backed adapter. It does not claim
Puppy's layered save-file, AUFS, overlay boot or desktop integration coverage.

Run `nix flake check -L` for native VM checks and `nix fmt` for formatting.

## Native payloads and bundled clients

`makeNativePet { name; version; payload; dependencies?; ... }` emits a native
PET from a producer-prepared filesystem tree without implicit engine scripts
or Nix dependencies. Native PETget owns installation, replacement and removal.
The producer supplies a runnable target layout; binaries are not relocated.
The VM installs and upgrades native files through actual PETget before installing
the engine, executes the installed static payload in an isolated root without
`/nix`, then checks native removal. The package-manager fixture itself uses the
NixOS host tools; this does not claim a full Puppy boot without Nix.

`makeRuntimePet` optionally accepts `bundledNixStore` and `bundledNixNotices`
for a static ELF client and upstream notices. Bundling omits the default native
Nix dependency; Python remains required. Compatible external clients take
precedence, explicit `IMPURIFIER_NIX_STORE` disables fallback, and failed mutations
are never retried through another client. A bundled-client VM repeats the original
PETget lifecycle suite with an incompatible external candidate. Nix provisioning
remains deferred.
