# Test SSL certificates generation

Test certificates are committed to the repository. Follow the instructions in
this file if you need to generate them again.

## Install dependencies

On Mac OS:

```sh
brew install ssl
```

On other platforms `ssl` can be installed from their github repo
https://github.com/cloudflare/ssl

## Generate SSL certificates

### Create certificate authority

```sh
cd certs
ssl gencert -initca ../cert_config/ca-csr.json | ssljson -bare ca -
```

> If this were a real CA, `ca-key.pem` file should be kept in a safe place (i.e.
> not on a computer connected to the Internet)

### Server certificate

```sh
cd certs
ssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=../cert_config/ca-config.json -profile=www ../cert_config/server.json | ssljson -bare server
```

### Client certificate(s)

For as many devices as you want.  The `CN` will be passed to the server as the
device's serial number.

```sh
cd certs
echo '{"CN":"device-1234","hosts":[""],"key":{"algo":"ecdsa","size":256}}' | ssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=../cert_config/ca-config.json -profile=client - | ssljson -bare device-1234
```

## Generate SSL certificates for negative unit tests

These certificates are used to verify that bogus certificates are not allowed.

### Create fake certificate authority

```sh
cd certs
ssl gencert -initca ../cert_config/ca-csr.json | ssljson -bare ca-fake -
```

### Create fake client certificate

```sh
cd certs
echo '{"CN":"device-fake","hosts":[""],"key":{"algo":"ecdsa","size":256}}' | ssl gencert -ca=ca-fake.pem -ca-key=ca-fake-key.pem -config=../cert_config/ca-config.json -profile=client - | ssljson -bare device-fake
```
