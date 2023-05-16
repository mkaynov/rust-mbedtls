#!/bin/bash
set -ex
cd "$(dirname "$0")"

# According to `mbedtls-sys/vendor/README.md`, need to install needed pkgs
python3 -m pip install -r ./mbedtls-sys/vendor/scripts/basic.requirements.txt

# setup stack size to ensure big tests run correctly
compiler_stack_size=16
ulimit -s "$(expr "$compiler_stack_size" \* 1024)"
export RUST_MIN_STACK="$(expr "$compiler_stack_size" \* 1024 \* 1024)"

cd "./mbedtls"

if [ -z $TRAVIS_RUST_VERSION ]; then
    echo "Expected TRAVIS_RUST_VERSION to be set in env"
    exit 1
fi

export CFLAGS_x86_64_fortanix_unknown_sgx="-isystem/usr/include/x86_64-linux-gnu -mlvi-hardening -mllvm -x86-experimental-lvi-inline-asm-hardening"
export CC_x86_64_fortanix_unknown_sgx=clang-11
export CARGO_INCREMENTAL=0

# install `cargo-nextest`
cargo install cargo-nextest --locked

if [ "$TRAVIS_RUST_VERSION" == "stable" ] || [ "$TRAVIS_RUST_VERSION" == "beta" ] || [ "$TRAVIS_RUST_VERSION" == "nightly" ]; then
    # Install the rust toolchain
    rustup default $TRAVIS_RUST_VERSION
    rustup target add --toolchain $TRAVIS_RUST_VERSION $TARGET

    # The SGX target cannot be run under test like a ELF binary
    if [ "$TARGET" != "x86_64-fortanix-unknown-sgx" ]; then 
        # make sure that explicitly providing the default target works
        cargo nextest run --target $TARGET --release
        cargo nextest run --features pkcs12 --target $TARGET
        cargo nextest run --features pkcs12_rc2 --target $TARGET
        cargo nextest run --features dsa --target $TARGET
        cargo nextest run --features async-rt --test async_session --target $TARGET
        cargo nextest run --features async-rt --test hyper_async --target $TARGET
        
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
