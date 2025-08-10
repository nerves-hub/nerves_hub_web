#!/usr/bin/env sh

set -eu

cd /tmp

if [ "$(uname -m)" = "x86_64" ]
then
    wget https://github.com/fwup-home/fwup/releases/download/v1.13.2/fwup_1.13.2_amd64.deb
    dpkg -i fwup_1.13.2_amd64.deb
    rm fwup_1.13.2_amd64.deb

    echo "FWUP installed using Debian package"

elif [ "$(uname -m)" = "aarch64" ]
then
    apt-get install -y git build-essential autoconf pkg-config libtool mtools help2man libarchive-dev dosfstools

    git clone https://github.com/fwup-home/fwup.git

    cd fwup

    ./scripts/download_deps.sh
    ./scripts/build_deps.sh
    ./autogen.sh
    PKG_CONFIG_PATH=$PWD/build/host/deps/usr/lib/pkgconfig ./configure --enable-shared=no
    make
    make check
    make install

    cd /
    rm -rf /tmp/fwup

    apt-get remove -y git build-essential autoconf pkg-config libtool mtools help2man libarchive-dev dosfstools

    echo "FWUP installed using source (static library support)"

else
    echo "FWUP installation skipped: Unsupported architecture"
fi
