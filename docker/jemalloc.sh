#!/usr/bin/env sh

set -eu

mkdir -p /tmp/jemalloc-build
cd /tmp/jemalloc-build

# Build latest clang

apt install -y git autoconf lsb-release wget software-properties-common gnupg make

bash -c "$(wget -O - https://apt.llvm.org/llvm.sh)"

ln -s /usr/bin/clang-20 /usr/bin/clang
ln -s /usr/bin/clang++-20 /usr/bin/clang++

export CC=clang
export CXX=clang++

echo "Clang v20 installed"

# Build the latest jemalloc

cd /tmp/jemalloc-build
git clone https://github.com/facebook/jemalloc

cd jemalloc

autoconf
./configure
make
make install

echo "jemalloc installed from source"

cd /

rm -rf /tmp/jemalloc-build

apt-get remove -y git autoconf lsb-release wget software-properties-common gnupg make
