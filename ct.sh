#!/bin/bash
set -ex
cd "$(dirname "$0")"

# According to `mbedtls-sys/vendor/README.md`, need to install needed pkgs
python3 -m pip install -r ./mbedtls-sys/vendor/scripts/basic.requirements.txt

# setup stack size to ensure big tests run correctly
compiler_stack_size=16
ulimit -s "$(expr "$compiler_stack_size" \* 1024)"
export RUST_MIN_STACK="$(expr "$compiler_stack_size" \* 1024 \* 1024)"
export QEMU_STACK_SIZE="$(expr "$compiler_stack_size" \* 1024 \* 1024)"

cd "./mbedtls"

if [ -z $TRAVIS_RUST_VERSION ]; then
    echo "Expected TRAVIS_RUST_VERSION to be set in env"
    exit 1
fi

aarch64_cross_toolchain_hash=c8ee0e7fd58f5ec6811e3cec5fcdd8fc47cb2b49fb50e9d7717696ddb69c812547b5f389558f62dfbf9db7d6ad808a5a515cc466b8ea3e9ab3daeb20ba1adf33
# save to directorie that will be cached
aarch64_cross_toolchain_save_path=$TRAVIS_HOME/.rustup/aarch64-linux-musl-cross.tgz
if [ "$TARGET" == "aarch64-unknown-linux-musl" ]; then
    if ! echo "${aarch64_cross_toolchain_hash} ${aarch64_cross_toolchain_save_path}" | sha512sum -c; then
        wget https://more.musl.cc/10-20210301/x86_64-linux-musl/aarch64-linux-musl-cross.tgz -O ${aarch64_cross_toolchain_save_path}
        echo "${aarch64_cross_toolchain_hash} ${aarch64_cross_toolchain_save_path}" | sha512sum -c
    fi
    tar -xf ${aarch64_cross_toolchain_save_path} -C /tmp;
fi

export CFLAGS_x86_64_fortanix_unknown_sgx="-isystem/usr/include/x86_64-linux-gnu -mlvi-hardening -mllvm -x86-experimental-lvi-inline-asm-hardening"
export CC_x86_64_fortanix_unknown_sgx=clang-11
export CC_aarch64_unknown_linux_musl=/tmp/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=/tmp/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_RUNNER=qemu-aarch64

# download pre-built `cargo-nextest`
cargo_nextest_hash=d22ce5799f3056807fd0cd8223a290c7153a5f084d5ab931fce755c2cabd33f79c0f75542eb724fe07a7ca083f415ec1f84edc46584b06df43d97a0ff91018da
if ! echo "${cargo_nextest_hash} ${CARGO_HOME:-$HOME/.cargo}/bin/cargo-nextest" | sha512sum -c; then
    curl -LsSf https://get.nexte.st/0.9.52/linux | tar zxf - -C ${CARGO_HOME:-$HOME/.cargo}/bin
    echo "${cargo_nextest_hash} ${CARGO_HOME:-$HOME/.cargo}/bin/cargo-nextest" | sha512sum -c
fi

if [ "$TRAVIS_RUST_VERSION" == "stable" ] || [ "$TRAVIS_RUST_VERSION" == "beta" ] || [ "$TRAVIS_RUST_VERSION" == "nightly" ]; then
    # Install the rust toolchain
    rustup default $TRAVIS_RUST_VERSION
    rustup target add --toolchain $TRAVIS_RUST_VERSION $TARGET

    if [ "$TARGET" == "aarch64-unknown-linux-musl" ]; then
        export OPT_LEVEL=3
    fi

    # The SGX target cannot be run under test like a ELF binary
    if [ "$TARGET" != "x86_64-fortanix-unknown-sgx" ]; then 
        # make sure that explicitly providing the default target works
        cargo nextest run --target $TARGET --release
        cargo nextest run --features pkcs12 --target $TARGET
        cargo nextest run --features pkcs12_rc2 --target $TARGET
        cargo nextest run --features dsa --target $TARGET
        cargo nextest run --features async-rt -E 'binary(=async_session) or binary(=hyper_async)' --target $TARGET
        
        # If AES-NI is supported, test the feature
        if [ -n "$AES_NI_SUPPORT" ]; then
            cargo nextest run --features force_aesni_support --target $TARGET
        fi

        # no_std tests only are able to run on x86 platform
        if [ "$TARGET" == "x86_64-unknown-linux-gnu" ]; then
            cargo nextest run --no-default-features --features no_std_deps,rdrand,time --target $TARGET
            cargo nextest run --no-default-features --features no_std_deps,rdrand --target $TARGET
        fi
    else
        cargo +$TRAVIS_RUST_VERSION test --no-run --target=$TARGET
    fi

else
    echo "Unknown version $TRAVIS_RUST_VERSION"
    exit 1
fi
