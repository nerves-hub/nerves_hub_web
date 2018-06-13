#!/bin/sh

# This script creates the test .fw files:
#
# unsigned.fw         - A basic unsigned firmware update file
# fwup-key1.pub       - One public key
# fwup-key2.pub       - A second public key
# signed-key1.fw      - unsigned.fw signed with private key that goes with fwup-key1.pub
# signed-other-key.fw - unsigned.fw signed with a key that's not fwup-key1 or fwup-key2
# corrupt.fw          - signed-key1.fw that's been truncated.

cat >test-fwup.conf <<EOF
meta-product = "starter"
meta-description = "D"
meta-version = "1.0.0"
meta-platform = "platform"
meta-architecture = "x86_64"
meta-author = "Me"

 file-resource info.txt {
   contents = "Hello, world!"
}
EOF

fwup -c -f test-fwup.conf -o unsigned.fw
fwup -g
fwup -S -s fwup-key.priv -i unsigned.fw -o signed-key1.fw
mv fwup-key.pub fwup-key1.pub
rm fwup-key.priv
fwup -g
mv fwup-key.pub fwup-key2.pub
rm fwup-key.priv
fwup -g
fwup -S -s fwup-key.priv -i unsigned.fw -o signed-other-key.fw
rm test-fwup.conf fwup-key.priv fwup-key.pub

# This assumes that signed-key1.fw is bigger than 512 bytes
dd if=signed-key1.fw of=corrupt.fw bs=512 count=1
