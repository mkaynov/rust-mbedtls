#!/bin/bash
set -ex

cwd=`pwd`
export script_dir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

export RUST_BACKTRACE=1
export TRAVIS_HOME=$HOME

targets=()
targets+=("x86_64-unknown-linux-gnu")
targets+=("aarch64-unknown-linux-musl")
targets+=("x86_64-fortanix-unknown-sgx")

versions=()
versions+=("beta")
versions+=("nightly")


for local_target in "${targets[@]}"
do
    export TARGET=$local_target
    export TRAVIS_RUST_VERSION="stable"
    $script_dir/ct.sh
done


for local_version in "${versions[@]}"
do
    export TARGET="x86_64-unknown-linux-gnu"
    export AES_NI_SUPPORT=true
    export ZLIB_INSTALLED=true
    export TRAVIS_RUST_VERSION=$local_version
    $script_dir/ct.sh
done

cd $cwd