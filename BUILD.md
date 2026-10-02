# Building and Packaging me_cleaner

This guide details how to compile, package, and install **me_cleaner** from source, with a particular focus on generating native **RPM packages** for Fedora, Red Hat Enterprise Linux (RHEL), CentOS Stream, and Fedora Asahi Remix (aarch64).

---

## Table of Contents

- [Overview](#overview)
- [Automated Compilation & Testing (build.sh)](#automated-compilation--testing-buildsh)
- [Prerequisites & Dependencies](#prerequisites--dependencies)
  - [Fedora / RHEL / CentOS / Fedora Asahi Remix](#fedora--rhel--centos--fedora-asahi-remix)
  - [Debian / Ubuntu](#debian--ubuntu)
  - [Arch Linux](#arch-linux)
- [Manual RPM Build Process](#manual-rpm-build-process)
  - [1. Prepare the RPM Build Directory Structure](#1-prepare-the-rpm-build-directory-structure)
  - [2. Generate the Source Tarball](#2-generate-the-source-tarball)
  - [3. Place the RPM Spec File](#3-place-the-rpm-spec-file)
  - [4. Build the Binary and Source RPMs](#4-build-the-binary-and-source-rpms)
  - [5. Install and Verify the RPM](#5-install-and-verify-the-rpm)
- [Standard Python Installation (Alternative)](#standard-python-installation-alternative)
  - [Using pip (Recommended for users without RPM)](#using-pip-recommended-for-users-without-rpm)
  - [Virtual Environment (Isolated)](#virtual-environment-isolated)
  - [Direct Execution](#direct-execution)
- [Optional: Building a Standalone Executable (PyInstaller)](#optional-building-a-standalone-executable-pyinstaller)
- [Package Verification & Testing](#package-verification--testing)
- [Troubleshooting & FAQ](#troubleshooting--faq)

---

## Overview

`me_cleaner` is a lightweight Python tool used to partially deblob and deactivate Intel Management Engine (ME) and TXE firmware. Because it is written in pure Python 3 without platform-specific compiled C extensions, the resulting RPM package is built as `noarch`, making it fully compatible with both x86_64 and ARM64 (`aarch64` such as Apple Silicon on Fedora Asahi Remix).

Our RPM packaging includes:
- Both `me_cleaner` and `me_cleaner.py` executables in `/usr/bin/`
- Standard Python egg/dist metadata in `/usr/lib/python3.*/site-packages/`
- Man pages (`me_cleaner.1.gz` and `me_cleaner.py.1.gz`) in `/usr/share/man/man1/`
- License (`COPYING`) and documentation (`README.md`)

---

## Automated Compilation & Testing (build.sh)

A turnkey build and test automation script `build.sh` is provided in the repository. It automatically handles source tarball creation, RPM compilation, and end-to-end verification tests.

### Quick Start

Simply run:

```bash
chmod +x build.sh
./build.sh
```

This single command will:
1. Validate required build tools (`rpmbuild`, `python3`, `git`, `tar`, `rpm2cpio`, `cpio`).
2. Generate the source tarball `me_cleaner-1.2.tar.gz` and place it in `~/rpmbuild/SOURCES/`.
3. Compile both binary RPM (`.noarch.rpm`) and source RPM (`.src.rpm`).
4. Perform automated verification tests:
   - Queries and validates RPM metadata (`rpm -qip`).
   - Verifies the file manifest for `/usr/bin/me_cleaner`, `/usr/bin/me_cleaner.py`, and man pages.
   - Extracts the package to an isolated sandbox and executes `me_cleaner --version`, `me_cleaner.py --version`, and `me_cleaner --help`.
   - Checks python3 shebang correctness.
5. Display the path to the ready-to-install RPM and the installation command.

### Available Options

```text
Usage: build.sh [OPTIONS]

Options:
  -r, --rpm          Build RPM package (default: true)
  -w, --wheel        Build Python wheel package (default: false)
  -t, --test         Run verification tests on built artifacts (default: true)
  --no-test          Skip artifact verification tests
  -c, --clean        Clean build directories and temporary files
  -h, --help         Show this help message and exit
```

---

## Prerequisites & Dependencies

### Fedora / RHEL / CentOS / Fedora Asahi Remix

Install the development tools, Python 3 packages, and RPM packaging utilities:

```bash
sudo dnf install -y \
    python3 \
    python3-devel \
    python3-setuptools \
    python3-pip \
    rpm-build \
    rpmdevtools \
    git
```

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y \
    python3 \
    python3-setuptools \
    python3-pip \
    git
```

### Arch Linux

```bash
sudo pacman -S --needed \
    python \
    python-setuptools \
    git
```

---

## Manual RPM Build Process

Follow these steps to produce an installable `.rpm` and source `.src.rpm`:

### 1. Prepare the RPM Build Directory Structure

Ensure the standard `rpmbuild` tree exists in your home directory:

```bash
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
```
*(Or run `rpmdev-setuptree` if `rpmdevtools` is installed)*.

### 2. Generate the Source Tarball

From the root of the `me_cleaner` repository:

```bash
git archive --format=tar.gz --prefix=me_cleaner-1.2/ HEAD -o ~/rpmbuild/SOURCES/me_cleaner-1.2.tar.gz
```

Verify that the tarball was created:

```bash
tar -ztvf ~/rpmbuild/SOURCES/me_cleaner-1.2.tar.gz
```

### 3. Place the RPM Spec File

Copy the `me_cleaner.spec` file into `~/rpmbuild/SPECS/`:

```bash
cp me_cleaner.spec ~/rpmbuild/SPECS/
```

### 4. Build the Binary and Source RPMs

Execute `rpmbuild` against the spec file:

```bash
rpmbuild -ba ~/rpmbuild/SPECS/me_cleaner.spec
```

Once the build finishes, the resulting RPMs will be located at:
- **Binary RPM:** `~/rpmbuild/RPMS/noarch/me_cleaner-1.2-1.fc*.noarch.rpm`
- **Source RPM (SRPM):** `~/rpmbuild/SRPMS/me_cleaner-1.2-1.fc*.src.rpm`

### 5. Install and Verify the RPM

Install the package directly using `dnf` or `rpm`:

```bash
sudo dnf install ~/rpmbuild/RPMS/noarch/me_cleaner-1.2-1.fc*.noarch.rpm
```

Verify the installation:

```bash
me_cleaner --version
me_cleaner.py --version
man me_cleaner
```

To list all files installed by the package:

```bash
rpm -ql me_cleaner
```

To remove the package if needed:

```bash
sudo dnf remove me_cleaner
```

---

## Standard Python Installation (Alternative)

If you are not on an RPM-based distribution or prefer installing via Python packaging:

### Using pip (Recommended for users without RPM)

From the project root:

```bash
python3 -m pip install .
```

For editable / development mode:

```bash
python3 -m pip install -e .
```

### Virtual Environment (Isolated)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install .
me_cleaner --help
```

### Direct Execution

`me_cleaner.py` has no external third-party dependencies outside the standard Python library:

```bash
python3 me_cleaner.py --help
```

---

## Optional: Building a Standalone Executable (PyInstaller)

If you want a single self-contained binary that can be copied to systems without needing `python3` or `setup.py` on the host:

1. Install PyInstaller:
   ```bash
   pip install pyinstaller
   ```

2. Compile `me_cleaner.py` into a single standalone binary:
   ```bash
   pyinstaller --onefile --name me_cleaner me_cleaner.py
   ```

3. The compiled binary will be placed in `dist/me_cleaner`:
   ```bash
   ./dist/me_cleaner --version
   ```

---

## Package Verification & Testing

Inspect the package metadata and file tree:

```bash
# Query package details
rpm -qip ~/rpmbuild/RPMS/noarch/me_cleaner-1.2-*.rpm

# List packaged files
rpm -qlp ~/rpmbuild/RPMS/noarch/me_cleaner-1.2-*.rpm

# Test basic operation on a dummy/valid image
me_cleaner -c /path/to/intel_firmware_dump.bin
```

---

## Troubleshooting & FAQ

### Issue: `python3: No module named 'setuptools'`
**Resolution:** Install `python3-setuptools`:
```bash
sudo dnf install -y python3-setuptools
```

### Issue: `error: File /home/.../rpmbuild/SOURCES/me_cleaner-1.2.tar.gz: No such file or directory`
**Resolution:** Ensure you ran `git archive` to generate `me_cleaner-1.2.tar.gz` and placed it into `~/rpmbuild/SOURCES/`.

### Issue: Command `me_cleaner` not found after manual installation
**Resolution:** When using `pip install --user`, ensure `~/.local/bin` is in your `$PATH`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```
RPM package installs to `/usr/bin/`, which is already in `$PATH` system-wide.
