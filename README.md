# SGDK Helper

This is a helper script for developing on Linux with Stephane Dallongeville's
excellent [SGDK](https://github.com/Stephane-D/SGDK).

## Usage

SGDK Helper supports both containerized and native workflows. The advantage
of the former is you don't need to install loads of dependencies on your
machine, just a container tool.

To check if you have a container tool run:

```bash
./sgdk-helper.sh container_tool
```

It will report `podman` or `docker` if you have either tool installed.

> **Note:** If you have both, `podman` is used in preference.

If you don't have one, either install one now or continue with native setup. To
install `podman` on a Debian based system, run:

```bash
sudo apt install podman
```

### Container setup

We build our own container with the dependencies we need for SGDK development
based on a slimmed down Debian container.

```bash
./sgdk-helper.sh build_container
```

### Native setup

```bash
./sgdk-helper.sh toolchain
./sgdk-helper.sh deps
```

## SGDK development

Now that the setup is complete, we can use SGDK Helper for development of
a Mega Drive project.

From the top directory of an SGDK project, build the ROM with:

```bash
sgdk-helper.sh rom
```

> **Note:** An SGDK project looks like this
> [example](https://github.com/Stephane-D/SGDK/tree/master/sample/sonic) from
> SGDK. There are many others both in the SGDK project and around GitHub.

And you can run the ROM in [BlastEm](https://www.retrodev.com/blastem/) with:

```bash
sgdk-helper.sh rom
```

> **Note:** Further documentation coming soon.
> For now, see the documentation in the script.
