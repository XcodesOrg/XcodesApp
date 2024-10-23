# Swift SRP

This library provides a swift implementation of the Secure Remote Password protocol. Secure Remote Password (SRP) provides username and password authentication without needing to provide your password to the server. As the server never sees your password it can never leak it to anyone else.

The server is provided with a cryptographic verifier that is derived from the password and a salt value that was used in the generation of this verifier. Both client and server generate large private and public keys and with these are able to generate a shared secret. The client then sends a proof they have the secret and if it is verified the server will do the same to verify the server as well.

The SRP protocol is detailed in [RFC2945](https://tools.ietf.org/html/rfc2945). This library implements version 6a of the protocol which includes the username in the salt to avoid the issue where a malicious server attempting to learn if two users have the same password. I believe it is also compliant with [RFC5054](https://tools.ietf.org/html/rfc5054). 

# Usage

First you create a configuration object. This will hold the hashing algorithm you are using, the large safe prime number required and a generator value. There is an enum that holds example primes and generators. It is general safer to use these as they are the ones provided in RFC5054 and have been battle tested. The following generates a configuration using SHA256 and a 2048 bit safe prime. You need to be sure both client and server use the same configuration.
```swift
let configuration = SRPConfiguration<SHA256>(.N2048)
```
When the client wants to create a new user they generate a salt and password verifier for their username and password. 
```swift
let client = SRPClient(configuration: configuration)
let (salt, verifier) = client.generateSaltAndVerifier(username: username, password: password)
```
These are passed to the server who will store them alongside the username in a database.

When the client wants to authenticate with the server they first need to generate a public/private key pair. These keys should only be used once. If you want to authenticate again you should generate a new pair.
```swift
let client = SRPClient(configuration: configuration)
let clientKeys = client.generateKeys()
let clientPublicKey = clientKeys.public
```
The contents of the `clientPublicKey` variable is passed to the server alongside the username to initiate authentication.

The server will then find the username in its database and extract the password verifier and salt that was stored with it. The password verifier is used to generate the servers key pair.
```swift
let server = SRPServer(configuration: configuration)
let serverKeys = server.generateKeys(verifier: values.verifier)
let serverPublicKey = serverKeys.public
```
The server replies with the `serverPublicKey` and the salt value associated with the user. At this point the server will need to store the `serverKeys` and the public key it received from the client, most likely in a database.  

The client then creates the shared secret using the username, password, salt, its own key pair and the server public key. It then has to generate a proof it has the shared secret. This proof is generated from shared secret plus any of the public data available.
```swift
let clientSharedSecret = try client.calculateSharedSecret(
    username: username, 
    password: password, 
    salt: salt, 
    clientKeys: clientKeys, 
    serverPublicKey: serverPublicKey
)
let clientProof = client.calculateClientProof(
    username: username, 
    salt: salt, 
    clientPublicKey: clientKeys.public, 
    serverPublicKey: serverPublicKey, 
    sharedSecret: clientSharedSecret
)
```
This `clientProof` is passed to the server. The server then generates its own version of the shared secret and verifies the `clientProof` is valid and if so will respond with it's own proof that it has the shared secret.
```swift
let serverSharedSecret = try server.calculateSharedSecret(
    clientPublicKey: clientPublicKey, 
    serverKeys: serverKeys, 
    verifier: verifier
)
let serverProof = try server.verifyClientProof(
    proof: clientProof, 
    username: username, 
    salt: salt, 
    clientPublicKey: clientPublicKey, 
    serverPublicKey: serverKeys.public, 
    sharedSecret: serverSharedSecret
)
```
And finally the client can verify the server proof is valid
```swift
try client.verifyServerProof(
    serverProof: serverProof, 
    clientProof: clientProof, 
    clientKeys: clientKeys, 
    sharedSecret: clientSharedSecret
)
```
If at any point any of these functions fail the process should be aborted.

# Compatibility

The library is compliant with RFC5054 and should work with any server implementing this. The library has been verified against 
- example data in RFC5054
- Mozilla test vectors in https://wiki.mozilla.org/Identity/AttachedServices/KeyServerProtocol#SRP_Verifier
- Python library [srptools](https://github.com/idlesign/srptools)
- Typescript library [tssrp6a](https://github.com/midonet/tssrp6a)

## Proof of secret

For generating the proof above I use the method detailed in [RFC2945](https://tools.ietf.org/html/rfc2945#section-3) but not all servers use this method. For this reason I have kept the sharedSecret generation separate from the proof generation, so you can insert your own version. 

I have also supplied a simple proof functions `server.verifySimpleClientProof` and `client.verifySimpleServerProof` which use the proof detailed in the Wikipedia [page](https://en.wikipedia.org/wiki/Secure_Remote_Password_protocol) on Secure Remote Password if you would prefer to use these.
