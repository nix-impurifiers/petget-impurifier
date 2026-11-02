#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Run native PETget components and report completed profile activation."""
from pathlib import Path
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile


def database():
    paths = [Path('/var/packages/user-installed-packages'), Path('/var/packages/woof-installed-packages')]
    return [line.split('|') for path in paths if path.exists() for line in path.read_text().splitlines() if line]


def metadata(path):
    if not path.is_file() or path.suffix != '.pet':
        raise ValueError('install requires local PET archives')
    content = path.read_bytes()
    if hashlib.md5(content[:-32]).hexdigest().encode() != content[-32:]:
        raise ValueError('PET checksum mismatch')
    with tarfile.open(path) as archive:
        rows = archive.extractfile(path.stem + '/pet.specs').read().decode().strip().split('|')
    if len(rows) < 10 or rows[0] != path.stem or not re.fullmatch(r'[a-z0-9][a-z0-9+.-]*', rows[1]):
        raise ValueError('invalid PET identity')
    return rows


def main():
    for key in ('ROOT', 'DESTDIR', 'IPKG_OFFLINE_ROOT'):
        if os.environ.get(key, '/') not in ('', '/'):
            raise ValueError('native PETget requires the live host root')
    if os.geteuid() != 0:
        raise ValueError('native PETget requires root')
    args = sys.argv[1:]
    if not args or any(a.startswith('-') for a in args):
        raise ValueError('use install ARCHIVE.pet...; remove NAME...; or reconcile')
    status = 0
    if args[0] == 'install' and len(args) > 1:
        sources = [Path(s).absolute() for s in args[1:]]
        specs = [metadata(p) for p in sources]
        selected = [s[1] for s in specs]
        if len(set(selected)) != len(selected):
            raise ValueError('select only one PET per logical package')
        available = set(selected) | {r[1] for r in database() if len(r) > 1}
        for spec in specs:
            for dependency in filter(None, spec[8].split(',')):
                if not re.fullmatch(r'\+[a-z0-9][a-z0-9+.-]*', dependency):
                    raise ValueError('adapter supports exact dependency names; use native PPM for richer constraints')
                if dependency[1:] not in available:
                    raise ValueError('missing native dependency: ' + dependency[1:])
        # PETget's pet2tgz deletes its input by default. Never pass the store copy.
        with tempfile.TemporaryDirectory(prefix='petget-impurifier-') as work:
            for source, spec in zip(sources, specs):
                if any(r[0] == spec[0] for r in database()):
                    continue  # Already installed: reconcile retries failed activation.
                destination = Path(work, source.name)
                shutil.copyfile(source, destination)
                result = subprocess.run(['/bin/bash', '/usr/local/petget/installpkg.sh', str(destination)])
                if result.returncode or not any(r[0] == spec[0] for r in database()):
                    status = result.returncode or 1
                    break
    elif args[0] == 'remove' and len(args) > 1:
        names = args[1:]
        if any(not re.fullmatch(r'[a-z0-9][a-z0-9+.-]*', n) for n in names):
            raise ValueError('remove accepts logical package names')
        for row in database():
            if len(row) > 8 and row[1] not in names:
                required = {d.lstrip('+').split('&')[0] for d in row[8].split(',')}
                if required.intersection(names):
                    raise ValueError('installed package still requires removal target: ' + row[1])
        for name in names:
            matches = [r for r in database() if len(r) > 1 and r[1] == name]
            for row in matches:
                result = subprocess.run(['/bin/bash', '/usr/lib/petget-impurifier/removepreview.sh'], env=os.environ | {'TREE2': row[0]})
                if result.returncode or any(r[0] == row[0] for r in database()):
                    status = result.returncode or 1
                    break
    elif args != ['reconcile']:
        raise ValueError('use install ARCHIVE.pet...; remove NAME...; or reconcile')
    activation = subprocess.run(['/usr/sbin/petget-impurifier-activate']).returncode
    return status or activation


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print('petget-impurifier: ' + str(error), file=sys.stderr)
        sys.exit(1)
