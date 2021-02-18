# Device Authentication

This document describes how NervesHub authenticates devices.

## Background

NervesHub requires devices to present an X.509 certificate when they connect.
This certificate, called the device certificate, must be signed by another
certificate, called the signer certificate. The signer certificate is also
called a Certificate Authority or CA certificate, but don't think of it as
coming from an Internet Certificate Authority like Let's Encrypt, etc. The
signer certificate is a self-signed certificate provided by a NervesHub user
that's registered to a NervesHub organization. The private key to the signer
certificate should be kept secret since NervesHub will trust devices.

NervesHub pins device certificates to simplify authentication for the common
case and to detect and log unusual events. It can be helpful to think of
authentication with NervesHub mostly like having a split password. I.e.,
NervesHub has the public side of the password and so long as the device can
prove that it has the private key side of the password, NervesHub will let it
in. The signing certificate comes in when NervesHub does not already have a
device's certificate on file.

## Authentication steps

Devices connect to NervesHub over TLS. NervesHub requests a certificate from the
device. After the TLS stack receives the certificate, it does some processing
and then passes it on to NervesHub code that does the following.  Note that
nothing in the X.509 certificate from the device is trusted at the beginning.

1. Compute a SHA-1 hash on the device certificate in DER form. This is
   called the certificate fingerprint.
2. Look up the certificate fingerprint in the DB
    a. If it exists and certificate has not expired, allow the device
    b. If it exists and the certificate has expired, allow the device if
       expired device certs are enabled
3. The certificate fingerprint is unknown. This is a new device certificate
4. Compute a SHA-1 hash of the public key in DER form. This is called the
   public key fingerprint.
5. Look the public key fingerprint up in the DB
    a. If it does not exist, go to step 6.
    b. If the common name in the device certificate does not match the
       Device ID associated with the public key SHA, reject the device.
       Two devices are not allowed to share a public key.
    c. Look up the authority that signed the device certificate (AKI) and
       verify that it is known and in the same organization. Devices
       must use registered signing certificates and can't switch
       organizations.
    d. Validate the certificate path the normal way (check signatures, expiry,
       etc. up the chain). Reject if not valid.
    e. The device rotated certificates, but did not change its public key.
       Record the new certificate fingerprint and allow.
6. Neither the certificate nor the public key have been seen before.
7. Check that the device certificate includes a common name. This will be
   the device ID should it be accepted.
8. Look up the authority that signed the device certificate and verify that
   it is known to NervesHub. Reject devices signed by certificates that have
   not been registered.
9. Validate the certificate path the normal way (check signatures, expiry,
   etc. for the chain)
10. Look up the device by it's reported device ID in the organization that
   has the signing cert that was used.
    a. If the device does not exist, reject. In the future a just-in-time
       provisioning rule would be run here.
11. Verify that the device is allowed to change its public key. If not, then
    reject. Devices that store their private keys in secure hardware devices
    may be configured to not allow this, so it would be bad for NervesHub to
    allow it under the flawed assumption that a certificate rotation was
    happening.
12. The device certificate is declared valid. Record public key and certificate
    fingerprints in the database and allow the device to proceed.
