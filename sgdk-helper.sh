#!/usr/bin/env bash
# SPDX-License-Identifier: ISC
#
# Copyright (C) 2023 Michael Drake <tlsa@netsurf-browser.org>

# shellcheck disable=SC2034 # Using variable indirection

set -e

# Macro preprocessor for the ASxxxx series of assemblers
declare -r MACCER_NAME="maccer"
declare -r MACCER_ARCHIVE="${MACCER_NAME}-026k02.zip"
declare -r MACCER_URL="https://gendev.spritesmind.net/files/${MACCER_ARCHIVE}"

# Z80 assembler
declare -r SJASM_NAME="Sjasm"
declare -r SJASM_REPO="https://github.com/Konamiman/${SJASM_NAME}.git"
declare -r SJASM_REF="v0.39"

# A free and open development kit for the Sega Mega Drive
declare -r SGDK_NAME="SGDK"
declare -r SGDK_REPO="https://github.com/Stephane-D/${SGDK_NAME}.git"
declare -r SGDK_REF="master"

# GNU cross compiler toolchain for Motorola 68000 (m68k-elf)
declare -r TOOLCHAIN_NAME="m68k-gcc-toolchain"
declare -r TOOLCHAIN_REPO="https://github.com/andwn/${TOOLCHAIN_NAME}.git"
declare -r TOOLCHAIN_REF="main"

# SGDK Helper dependency directories. Defaults to `${PWD}/.deps`.
# Override by setting DEP_DIR: `DEP_DIR=/my/path sgdk-helper.sh ...`.
declare -r DEP_SRC_DIR="${DEP_DIR:=${PWD}/.deps}/src"
declare -r DEP_OUT_DIR="${DEP_DIR:=${PWD}/.deps}/out"

# Various directories derived from the dependency directories above.
declare -r SGDK_DIR="${DEP_SRC_DIR}/${SGDK_NAME}"
declare -r SGDK_BIN_DIR="${SGDK_DIR}/bin"
declare -r TOOLCHAIN_DIR="${DEP_SRC_DIR}/${TOOLCHAIN_NAME}"

# SGDK Helper container tag names.
declare -r CONTAINER_TAG=sgdk-helper
declare -r CONTAINER_TOOLCHAIN_TAG="${CONTAINER_TAG}-toolchain"

# List of container tools supported by SGDK Helper.
declare -r CONTAINER_TOOLS="podman docker"

# Get the name of any container tool available.
function container_tool()
{
	for tool in $CONTAINER_TOOLS; do
		if command -v "$tool" -v &> /dev/null; then
			echo "$tool"
			return
		fi
	done

	echo ""
}

# Check if the given container tag exists.
function container_exists()
{
	if "$(container_tool)" image inspect "$1" &> /dev/null; then
		echo true
	else
		echo false
	fi
}

# Install the (Debian) packages needed for toolchain building.
# This is mostly intended to be called as part of the container build process.
function install_pkg_toolchain()
{
	apt-get update

	apt-get install -y \
		bison \
		bzip2 \
		flex \
		g++ \
		gcc \
		git \
		libzstd-dev \
		make \
		texinfo \
		wget \
		xz-utils

	apt-get clean
}

# Install the (Debian) packages needed for SGDK development.
# This is mostly intended to be called as part of the container build process.
function install_pkg_sgdk()
{
	apt-get update

	apt-get install -y \
		ca-certificates-java

	apt-get install -y \
		default-jre-headless \
		libpng-dev \
		unzip

	apt-get clean
}

# Build a container containing the m68k-elf toolchain.
# This builds GCC, and takes a long time.
function build_container_toolchain()
{
	declare -r CONTAINER_STEPS=".container-toolchain"

	{
		echo "FROM amd64/debian:12-slim"
		echo "RUN useradd -ms /bin/sh -d /helper helper"
		echo "RUN mkdir /deps" \
		     " && chown helper:helper /deps/"
		echo "COPY --chown=helper:helper ${0} /helper/sgdk-helper.sh"
		echo "RUN /helper/sgdk-helper.sh $(is_x) install_pkg_toolchain"
		echo "USER helper"
		echo "COPY ${0} /helper/sgdk-helper.sh"
		echo "RUN DEP_DIR=/deps" \
		     "    /helper/sgdk-helper.sh $(is_x) toolchain"
		echo "RUN DEP_DIR=/deps" \
		     "    /helper/sgdk-helper.sh $(is_x) delete_toolchain_src"
	} > "${CONTAINER_STEPS}"

	$(container_tool) build . \
		-t "${CONTAINER_TOOLCHAIN_TAG}" \
		-f "${CONTAINER_STEPS}"

	rm "${CONTAINER_STEPS}"
}

# Build a container containing SGDK and its tools.
# This is based on the toolchain container because the toolchain takes ages
# to build, so it's more optimal to be able to avoid rebuilding that if we
# only want to update the SGDK related components.
function build_container_sgdk()
{
	declare -r CONTAINER_STEPS=".container-sgdk"

	{
		echo "FROM ${CONTAINER_TOOLCHAIN_TAG}"
		echo "USER root"
		echo "RUN mkdir /project" \
		     " && chown helper:helper /project/"
		echo "COPY --chown=helper:helper ${0} /helper/sgdk-helper.sh"
		echo "RUN /helper/sgdk-helper.sh $(is_x) install_pkg_sgdk"
		echo "USER helper"
		echo "RUN DEP_DIR=/deps" \
		     "    /helper/sgdk-helper.sh $(is_x) deps"
	} > "${CONTAINER_STEPS}"

	$(container_tool) build . \
		-t "${CONTAINER_TAG}" \
		-f "${CONTAINER_STEPS}"

	rm "${CONTAINER_STEPS}"
}

# A shorthand for running `build_container_sgdk` that also runs
# `build_container_toolchain` if the toolchain container doesn't
# exist yet. To force `build_container_toolchain` to run again, run
# it explicitly.
function container()
{
	if ! "$(container_exists ${CONTAINER_TOOLCHAIN_TAG})"; then
		build_container_toolchain
	fi

	build_container_sgdk
}

# Helper to fetch given dependency with `wget`.
function wget_fetch()
{
	declare -r URL_VAR=${1}_URL
	declare -r URL=${!URL_VAR}

	mkdir -p "${DEP_SRC_DIR}"

	(cd "${DEP_SRC_DIR}" && \
	 wget --user-agent "Mozilla/4.0" \
	      --timestamping \
	      --no-verbose \
	      "${URL}" \
	)
}

# Helper to clone given dependency with `git`.
# Note, this creates a partial clone (different from a shallow clone), which
# means that blobs are fetched only on demand. You have to enter the clone
# and check something out explicitly to get _anything_.
function git_clone()
{
	declare -r NAME_VAR=${1}_NAME
	declare -r REPO_VAR=${1}_REPO
	declare -r NAME=${!NAME_VAR}
	declare -r REPO=${!REPO_VAR}

	mkdir -p "${DEP_SRC_DIR}"

	if [ -f "${DEP_SRC_DIR}/${NAME}/.git/config" ]; then
		echo "Already cloned: ${DEP_SRC_DIR}/${NAME}"
	else
		git -C "${DEP_SRC_DIR}" clone \
		     --filter=blob:none \
		     --no-checkout \
		     "${REPO}"
	fi
}

# Helper to set up a sparse checkout for a partial clone (optional).
# A sparse checkout filters out parts of a checkout so they don't get fetched.
# Pass the arguments to `git sparse-checkout set`
function git_setup_sparse()
{
	declare -r NAME_VAR=${1}_NAME
	declare -r NAME=${!NAME_VAR}

	shift

	git -C "${DEP_SRC_DIR}/${NAME}" sparse-checkout init
	git -C "${DEP_SRC_DIR}/${NAME}" sparse-checkout set "$@"
}

# Checkout the given ref in a git repo. This will be sparse if that was set up.
function git_update()
{
	declare -r NAME_VAR=${1}_NAME
	declare -r REF_VAR=${1}_REF
	declare -r NAME=${!NAME_VAR}
	declare -r REF=${!REF_VAR}

	git -C "${DEP_SRC_DIR}/${NAME}" fetch
	git -C "${DEP_SRC_DIR}/${NAME}" checkout "${REF}"
	git -C "${DEP_SRC_DIR}/${NAME}" pull
}

# Fetch maccer.
function fetch_maccer()
{
	wget_fetch MACCER
}

# Fetch Sjasm.
function fetch_sjasm()
{
	git_clone SJASM
	git_update SJASM
}

# Fetch SGDK git repo.
# This uses a sparse clone because the SGDK repo contains a lot of Windows
# binaries and many examples with binary resources that we don't need.
function fetch_sgdk()
{
	git_clone SGDK
	git_setup_sparse SGDK --no-cone \
		'/*' \
		'!/*/' \
		'/inc' \
		'/res' \
		'/src' \
		'/tools/bintos' \
		'/tools/xgmtool' \
		'/bin/*.jar'
	git_update SGDK
}

# Fetch the toolchain fetch/config/build repo.
function fetch_toolchain()
{
	git_clone TOOLCHAIN
	git_update TOOLCHAIN
}

# Shorthand to fetch all the dependencies.
function fetch_deps()
{
	fetch_maccer
	fetch_sjasm
	fetch_sgdk
}

# Build maccer.
function build_maccer()
{
	declare -r MACCER_DIR="${DEP_SRC_DIR}/${MACCER_NAME}"

	unzip -u "${DEP_SRC_DIR}/${MACCER_ARCHIVE}" -d "${MACCER_DIR}"

	gcc "${DEP_SRC_DIR}/${MACCER_NAME}/main.c" \
	     -Wall -O2 \
	     -DVERSION_STRING="\"0.26\"" \
	     -DKMOD_VERSION="\"0.26\"" \
	     -lm \
	     -o "${MACCER_DIR}/${MACCER_NAME}"

	strip "${MACCER_DIR}/${MACCER_NAME}"

	mkdir -p "${DEP_OUT_DIR}/bin"
	cp "${MACCER_DIR}/${MACCER_NAME}" "${DEP_OUT_DIR}/bin/mac68k"
}

# Build Sjasm
function build_sjasm()
{
	declare -r SJASM_DIR="${DEP_SRC_DIR}/${SJASM_NAME}/${SJASM_NAME}"

	make -C "${SJASM_DIR}"
	strip "${SJASM_DIR}/sjasm"

	mkdir -p "${DEP_OUT_DIR}/bin"
	cp "${SJASM_DIR}/sjasm" "${DEP_OUT_DIR}/bin"
}

# Build SGDK's xgmtool
function build_sgdk_xgmtool()
{
	declare -r TOOL_DIR="${SGDK_DIR}/tools/xgmtool"

	gcc "${TOOL_DIR}"/src/*.c \
	    -Wall -O2  \
	    -lm \
	    -o "${TOOL_DIR}/xgmtool"
	strip "${TOOL_DIR}/xgmtool"

	mkdir -p "${SGDK_BIN_DIR}"
	cp "${TOOL_DIR}/xgmtool" "${SGDK_BIN_DIR}"
}

# Build SGDK's bintos
function build_sgdk_bintos()
{
	declare -r TOOL_DIR="${SGDK_DIR}/tools/bintos"

	gcc "${TOOL_DIR}/src/bintos.c" \
	    -Wall -O2  \
	    -o "${TOOL_DIR}/bintos"
	strip "${TOOL_DIR}/bintos"

	mkdir -p "${SGDK_BIN_DIR}"
	cp "${TOOL_DIR}/bintos" "${SGDK_BIN_DIR}"
}

# Build SGDK's libmd. Pass either "release" or "debug" to build that variant.
function build_sgdk_lib_variant()
{
	mkdir -p "${SGDK_DIR}/lib"

	make -C "${SGDK_DIR}" -f makelib.gen clean"${1}"
	PATH="${PWD}/${SGDK_BIN_DIR}:${PWD}/${DEP_OUT_DIR}/bin:${PATH}" \
		make -C "${SGDK_DIR}" \
		     -f makelib.gen \
		     LTO_PLUGIN="--plugin=$(lto_plugin_path)" \
		     PREFIX=m68k-elf- \
		     "${1}"
}

# Build SGDK's libmd.
function build_sgdk_lib()
{
	build_sgdk_lib_variant release
	build_sgdk_lib_variant debug
}

# Build SGDK.
function build_sgdk()
{
	build_sgdk_xgmtool
	build_sgdk_bintos
	build_sgdk_lib
}

# Build all the dependencies.
function build_deps()
{
	build_maccer
	build_sjasm
	build_sgdk
}

# Fetch and build all the dependencies.
function deps()
{
	fetch_deps
	build_deps
}

# Build the toolchain.
function build_toolchain()
{
	make -C "${TOOLCHAIN_DIR}" without-newlib
	make -C "${TOOLCHAIN_DIR}" install INSTALL_DIR="${DEP_OUT_DIR}"
}

# Helper to delete the toolchain source.
# This is used after building the toolchain in the container, to reduce the
# container size. It's probably not much use outside the container..
function delete_toolchain_src()
{
	rm -rf "${TOOLCHAIN_DIR}"
}

# Helper to find the link time optimisation plugin.
function lto_plugin_path()
{
	find "${DEP_OUT_DIR}" -name liblto_plugin.so
}

# Fetch and build the toolchain.
function toolchain()
{
	fetch_toolchain
	build_toolchain
}

# Run a command in the given container environment.
# The current directory is mounted inside the container.
# The first argument is the container tag for the container to use.
# The remaining arguments are the command to run inside the container.
# This would normally be run via the `rom` or `shell` functions.
function container_run()
{
	$(container_tool) run -t -i \
		--uidmap 1000:0:1 \
		--uidmap 0:1:1000 \
		--workdir "/project" \
		--env "DEP_DIR=/deps" \
		-v "${PWD}:/project" \
		"$@"
}

# Build a Mega Drive ROM!
#
# This assumes you're currently in the top level of your project source
# tree, and it has the standard SGDK project layout.
#
# You can pass whatever arguments you want to this function and they will
# be passed to `make` for the ROM build. For example, to clean your build,
# pass `clean`: `./sgdk-helper.sh rom clean`.
#
# If you've got a known container tool this will build the ROM inside the
# container. If you have a known container tool, but haven't yet built the
# `sgdk-helper` container, this will also build that. Note, if you also
# haven't built the `sgdk-helper-toolchain` container, that will be built too,
# and it will take a long time.
#
# If you don't have a known container tool, this will try to build the ROM
# directly on your machine. You'll need to install some packages to do this
# (see the `apt-get install` steps in the container build functions for some
# clues). You'll also need to build the toolchain and deps.
function rom()
{
	if [ "$(container_tool)" ] ; then
		if [ "$(container_exists ${CONTAINER_TAG})" = false ] ; then
			container
		fi

		container_run \
			"${CONTAINER_TAG}" \
			/helper/sgdk-helper.sh \
			"$(is_x)" \
			rom "$@"
	else
		PATH="${SGDK_BIN_DIR}:${DEP_OUT_DIR}/bin:${PATH}" \
			make -f "${SGDK_DIR}/makefile.gen" \
			     LTO_PLUGIN="--plugin=$(lto_plugin_path)" \
			     PREFIX=m68k-elf- "$@"
	fi
}

# Get a shell prompt in the ROM build container environment.
# Can be useful for investigating.
function shell()
{
	container_run \
		"${CONTAINER_TAG}" \
		/bin/bash
}

# Run the ROM in a Mega Drive emulator!
function run()
{
	blastem out/rom.bin
}

# Build and run the ROM.
function romrun()
{
	rom
	run
}

# Check if `set -x` mode is set.
# (We detect if it is and propagate it into commands run in the container.)
function is_x()
{
	echo "${-//[^x]/}"
}

# Sets the `-x` option and executes remaining arguments.
# Causes each command that is executed to be printed in the terminal.
function x()
{
	set -x
	"$@"
}

# Print usage.
function print_usage()
{
	echo "Usage:"
	echo "  ${0} [x] command [args]"
	echo ""
	echo "Commands for container setup:"
	echo "  container"
	echo ""
	echo "Commands for native setup:"
	echo "  toolchain"
	echo "  deps"
	echo ""
	echo "Commands for development:"
	echo "  rom"
	echo "  run"
	echo "  romrun"
	echo ""
	echo "Passing 'x' before the command enables 'set -x' for debug."
	echo ""
	echo "Many more commands are available too. Any function defined in"
	echo "${0} can be used as a command."
}

# If no command was given, print usage and exit.
if [ $# -eq 0 ]; then
	print_usage
	exit
fi

# Run the command we were given.
"$@"
