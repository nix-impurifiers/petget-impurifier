# Testing

Run `nix flake check -L`. Use actual pinned Woof-CE PETget scripts in QEMU, actual
native archives and package databases. Never replace native operations with mock
commands. Cover native failures, interrupted activation, offline imports, account
and directory preparation, garbage collection and native config behavior.
