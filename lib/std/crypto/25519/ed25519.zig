const std = @import("std");
const crypto = std.crypto;
const debug = std.debug;
const fmt = std.fmt;
const mem = std.mem;

const Sha512 = crypto.hash.sha2.Sha512;

const EncodingError = crypto.errors.EncodingError;
const IdentityElementError = crypto.errors.IdentityElementError;
const NonCanonicalError = crypto.errors.NonCanonicalError;
const SignatureVerificationError = crypto.errors.SignatureVerificationError;
const KeyMismatchError = crypto.errors.KeyMismatchError;
const WeakPublicKeyError = crypto.errors.WeakPublicKeyError;

/// Ed25519 (EdDSA) signatures.
pub const Ed25519 = struct {
    /// The underlying elliptic curve.
    pub const Curve = std.crypto.ecc.Edwards25519;

    /// Length (in bytes) of optional random bytes, for non-deterministic signatures.
    pub const noise_length = 32;

    const CompressedScalar = Curve.scalar.CompressedScalar;
    const Scalar = Curve.scalar.Scalar;

    /// An Ed25519 secret key.
    pub const SecretKey = struct {
        /// Length (in bytes) of a raw secret key.
        pub const encoded_length = 64;

        bytes: [encoded_length]u8,

        /// Return the seed used to generate this secret key.
        pub fn seed(self: SecretKey) [KeyPair.seed_length]u8 {
            return self.bytes[0..KeyPair.seed_length].*;
        }

        /// Return the raw public key bytes corresponding to this secret key.
        pub fn publicKeyBytes(self: SecretKey) [PublicKey.encoded_length]u8 {
            return self.bytes[KeyPair.seed_length..].*;
        }

        /// Create a secret key from raw bytes.
        pub fn fromBytes(bytes: [encoded_length]u8) !SecretKey {
            return SecretKey{ .bytes = bytes };
        }

        /// Return the secret key as raw bytes.
        pub fn toBytes(sk: SecretKey) [encoded_length]u8 {
            return sk.bytes;
        }

        // Return the clamped secret scalar and prefix for this secret key
        fn scalarAndPrefix(self: SecretKey) struct { scalar: CompressedScalar, prefix: [32]u8 } {
            var az: [Sha512.digest_length]u8 = undefined;
            var h = Sha512.init(.{});
            h.update(&self.seed());
            h.final(&az);

            var s = az[0..32].*;
            Curve.scalar.clamp(&s);

            return .{ .scalar = s, .prefix = az[32..].* };
        }
    };

    /// A Signer is used to incrementally compute a signature.
    /// It can be obtained from a `KeyPair`, using the `signer()` function.
    pub const Signer = struct {
        h: Sha512,
        scalar: CompressedScalar,
        nonce: CompressedScalar,
        r_bytes: [Curve.encoded_length]u8,

        fn init(scalar: CompressedScalar, nonce: CompressedScalar, public_key: PublicKey) (IdentityElementError || KeyMismatchError || NonCanonicalError || WeakPublicKeyError)!Signer {
            const r = try Curve.basePoint.mul(nonce);
            const r_bytes = r.toBytes();

            var t: [64]u8 = undefined;
            t[0..32].* = r_bytes;
            t[32..].* = public_key.bytes;
            var h = Sha512.init(.{});
            h.update(&t);

            return Signer{ .h = h, .scalar = scalar, .nonce = nonce, .r_bytes = r_bytes };
        }

        /// Add new data to the message being signed.
        pub fn update(self: *Signer, data: []const u8) void {
            self.h.update(data);
        }

        /// Compute a signature over the entire message.
        pub fn finalize(self: *Signer) Signature {
            var hram64: [Sha512.digest_length]u8 = undefined;
            self.h.final(&hram64);
            const hram = Curve.scalar.reduce64(hram64);

            const s = Curve.scalar.mulAdd(hram, self.scalar, self.nonce);

            return Signature{ .r = self.r_bytes, .s = s };
        }
    };

    /// An Ed25519 public key.
    pub const PublicKey = struct {
        /// Length (in bytes) of a raw public key.
        pub const encoded_length = 32;

        bytes: [encoded_length]u8,

        /// Create a public key from raw bytes.
        pub fn fromBytes(bytes: [encoded_length]u8) NonCanonicalError!PublicKey {
            try Curve.rejectNonCanonical(bytes);
            return PublicKey{ .bytes = bytes };
        }

        /// Convert a public key to raw bytes.
        pub fn toBytes(pk: PublicKey) [encoded_length]u8 {
            return pk.bytes;
        }

        fn signWithNonce(public_key: PublicKey, msg: []const u8, scalar: CompressedScalar, nonce: CompressedScalar) (IdentityElementError || NonCanonicalError || KeyMismatchError || WeakPublicKeyError)!Signature {
            var st = try Signer.init(scalar, nonce, public_key);
            st.update(msg);
            return st.finalize();
        }

        fn computeNonceAndSign(public_key: PublicKey, msg: []const u8, noise: ?[noise_length]u8, scalar: CompressedScalar, prefix: []const u8) (IdentityElementError || NonCanonicalError || KeyMismatchError || WeakPublicKeyError)!Signature {
            var h = Sha512.init(.{});
            if (noise) |*z| {
                h.update(z);
            }
            h.update(prefix);
            h.update(msg);
            var nonce64: [64]u8 = undefined;
            h.final(&nonce64);

            const nonce = Curve.scalar.reduce64(nonce64);

            return public_key.signWithNonce(msg, scalar, nonce);
        }
    };

    /// A Verifier is used to incrementally verify a signature.
    /// It can be obtained from a `Signature`, using the `verifier()` function.
    pub const Verifier = struct {
        h: Sha512,
        s: CompressedScalar,
        a: Curve,
        expected_r: Curve,

        pub const InitError = NonCanonicalError || EncodingError || IdentityElementError;

        fn init(sig: Signature, public_key: PublicKey) InitError!Verifier {
            const r = sig.r;
            const s = sig.s;
            try Curve.scalar.rejectNonCanonical(s);
            const a = try Curve.fromBytes(public_key.bytes);
            try a.rejectIdentity();
            try Curve.rejectNonCanonical(r);
            const expected_r = try Curve.fromBytes(r);
            try expected_r.rejectIdentity();

            var h = Sha512.init(.{});
            h.update(&r);
            h.update(&public_key.bytes);

            return Verifier{ .h = h, .s = s, .a = a, .expected_r = expected_r };
        }

        /// Add new content to the message to be verified.
        pub fn update(self: *Verifier, msg: []const u8) void {
            self.h.update(msg);
        }

        pub const VerifyError = WeakPublicKeyError || IdentityElementError ||
            SignatureVerificationError;

        /// Verify that the signature is valid for the entire message.
        pub fn verify(self: *Verifier) VerifyError!void {
            var hram64: [Sha512.digest_length]u8 = undefined;
            self.h.final(&hram64);
            const hram = Curve.scalar.reduce64(hram64);

            const sb_ah = try Curve.basePoint.mulDoubleBasePublic(self.s, self.a.neg(), hram);
            if (self.expected_r.sub(sb_ah).rejectLowOrder()) {
                return error.SignatureVerificationFailed;
            } else |_| {}
        }
    };

    /// An Ed25519 signature.
    pub const Signature = struct {
        /// Length (in bytes) of a raw signature.
        pub const encoded_length = Curve.encoded_length + @sizeOf(CompressedScalar);

        /// The R component of an EdDSA signature.
        r: [Curve.encoded_length]u8,
        /// The S component of an EdDSA signature.
        s: CompressedScalar,

        /// Return the raw signature (r, s) in little-endian format.
        pub fn toBytes(sig: Signature) [encoded_length]u8 {
            var bytes: [encoded_length]u8 = undefined;
            bytes[0..Curve.encoded_length].* = sig.r;
            bytes[Curve.encoded_length..].* = sig.s;
            return bytes;
        }

        /// Create a signature from a raw encoding of (r, s).
        /// EdDSA always assumes little-endian.
        pub fn fromBytes(bytes: [encoded_length]u8) Signature {
            return Signature{
                .r = bytes[0..Curve.encoded_length].*,
                .s = bytes[Curve.encoded_length..].*,
            };
        }

        /// Create a Verifier for incremental verification of a signature.
        pub fn verifier(sig: Signature, public_key: PublicKey) Verifier.InitError!Verifier {
            return Verifier.init(sig, public_key);
        }

        pub const VerifyError = Verifier.InitError || Verifier.VerifyError;

        /// Verify the signature against a message and public key.
        /// Return IdentityElement or NonCanonical if the public key or signature are not in the expected range,
        /// or SignatureVerificationError if the signature is invalid for the given message and key.
        pub fn verify(sig: Signature, msg: []const u8, public_key: PublicKey) VerifyError!void {
            var st = try sig.verifier(public_key);
            st.update(msg);
            try st.verify();
        }
    };

    /// An Ed25519 key pair.
    pub const KeyPair = struct {
        /// Length (in bytes) of a seed required to create a key pair.
        pub const seed_length = noise_length;

        /// Public part.
        public_key: PublicKey,
        /// Secret scalar.
        secret_key: SecretKey,

        /// Deterministically derive a key pair from a cryptograpically secure secret seed.
        ///
        /// To create a new key, applications should generally call `generate()` instead of this function.
        ///
        /// As in RFC 8032, an Ed25519 public key is generated by hashing
        /// the secret key using the SHA-512 function, and interpreting the
        /// bit-swapped, clamped lower-half of the output as the secret scalar.
        ///
        /// For this reason, an EdDSA secret key is commonly called a seed,
        /// from which the actual secret is derived.
        pub fn generateDeterministic(seed: [seed_length]u8) IdentityElementError!KeyPair {
            var az: [Sha512.digest_length]u8 = undefined;
            var h = Sha512.init(.{});
            h.update(&seed);
            h.final(&az);
            const pk_p = Curve.basePoint.clampedMul(az[0..32].*) catch return error.IdentityElement;
            const pk_bytes = pk_p.toBytes();
            var sk_bytes: [SecretKey.encoded_length]u8 = undefined;
            sk_bytes[0..seed_length].* = seed;
            sk_bytes[seed_length..].* = pk_bytes;
            return KeyPair{
                .public_key = PublicKey.fromBytes(pk_bytes) catch unreachable,
                .secret_key = try SecretKey.fromBytes(sk_bytes),
            };
        }

        /// Generate a new, random key pair.
        ///
        /// `crypto.random.bytes` must be supported by the target.
        pub fn generate() KeyPair {
            var random_seed: [seed_length]u8 = undefined;
            while (true) {
                crypto.random.bytes(&random_seed);
                return generateDeterministic(random_seed) catch {
                    @branchHint(.unlikely);
                    continue;
                };
            }
        }

        /// Create a key pair from an existing secret key.
        ///
        /// Note that with EdDSA, storing the seed, and recovering the key pair
        /// from it is recommended over storing the entire secret key.
        /// The seed of an exiting key pair can be obtained with
        /// `key_pair.secret_key.seed()`, and the secret key can then be
        /// recomputed using `SecretKey.generateDeterministic()`.
        pub fn fromSecretKey(secret_key: SecretKey) (NonCanonicalError || EncodingError || IdentityElementError)!KeyPair {
            // It is critical for EdDSA to use the correct public key.
            // In order to enforce this, a SecretKey implicitly includes a copy of the public key.
            // With runtime safety, we can still afford checking that the public key is correct.
            if (std.debug.runtime_safety) {
                const pk_p = try Curve.fromBytes(secret_key.publicKeyBytes());
                const recomputed_kp = try generateDeterministic(secret_key.seed());
                if (!mem.eql(u8, &recomputed_kp.public_key.toBytes(), &pk_p.toBytes())) {
                    return error.NonCanonical;
                }
            }
            return KeyPair{
                .public_key = try PublicKey.fromBytes(secret_key.publicKeyBytes()),
                .secret_key = secret_key,
            };
        }

        /// Sign a message using the key pair.
        /// The noise can be null in order to create deterministic signatures.
        /// If deterministic signatures are not required, the noise should be randomly generated instead.
        /// This helps defend against fault attacks.
        pub fn sign(key_pair: KeyPair, msg: []const u8, noise: ?[noise_length]u8) (IdentityElementError || NonCanonicalError || KeyMismatchError || WeakPublicKeyError)!Signature {
            if (!mem.eql(u8, &key_pair.secret_key.publicKeyBytes(), &key_pair.public_key.toBytes())) {
                return error.KeyMismatch;
            }
            const scalar_and_prefix = key_pair.secret_key.scalarAndPrefix();
            return key_pair.public_key.computeNonceAndSign(
                msg,
                noise,
                scalar_and_prefix.scalar,
                &scalar_and_prefix.prefix,
            );
        }

        /// Create a Signer, that can be used for incremental signing.
        /// Note that the signature is not deterministic.
        /// The noise parameter, if set, should be something unique for each message,
        /// such as a random nonce, or a counter.
        pub fn signer(key_pair: KeyPair, noise: ?[noise_length]u8) (IdentityElementError || KeyMismatchError || NonCanonicalError || WeakPublicKeyError)!Signer {
            if (!mem.eql(u8, &key_pair.secret_key.publicKeyBytes(), &key_pair.public_key.toBytes())) {
                return error.KeyMismatch;
            }
            const scalar_and_prefix = key_pair.secret_key.scalarAndPrefix();
            var h = Sha512.init(.{});
            h.update(&scalar_and_prefix.prefix);
            var noise2: [noise_length]u8 = undefined;
            crypto.random.bytes(&noise2);
            h.update(&noise2);
            if (noise) |*z| {
                h.update(z);
            }
            var nonce64: [64]u8 = undefined;
            h.final(&nonce64);
            const nonce = Curve.scalar.reduce64(nonce64);

            return Signer.init(scalar_and_prefix.scalar, nonce, key_pair.public_key);
        }
    };

    /// A (signature, message, public_key) tuple for batch verification
    pub const BatchElement = struct {
        sig: Signature,
        msg: []const u8,
        public_key: PublicKey,
    };

    /// Verify several signatures in a single operation, much faster than verifying signatures one-by-one
    pub fn verifyBatch(comptime count: usize, signature_batch: [count]BatchElement) (SignatureVerificationError || IdentityElementError || WeakPublicKeyError || EncodingError || NonCanonicalError)!void {
        var r_batch: [count]CompressedScalar = undefined;
        var s_batch: [count]CompressedScalar = undefined;
        var a_batch: [count]Curve = undefined;
        var expected_r_batch: [count]Curve = undefined;

        for (signature_batch, 0..) |signature, i| {
            const r = signature.sig.r;
            const s = signature.sig.s;
            try Curve.scalar.rejectNonCanonical(s);
            const a = try Curve.fromBytes(signature.public_key.bytes);
            try a.rejectIdentity();
            try Curve.rejectNonCanonical(r);
            const expected_r = try Curve.fromBytes(r);
            try expected_r.rejectIdentity();
            expected_r_batch[i] = expected_r;
            r_batch[i] = r;
            s_batch[i] = s;
            a_batch[i] = a;
        }

        var hram_batch: [count]Curve.scalar.CompressedScalar = undefined;
        for (signature_batch, 0..) |signature, i| {
            var h = Sha512.init(.{});
            h.update(&r_batch[i]);
            h.update(&signature.public_key.bytes);
            h.update(signature.msg);
            var hram64: [Sha512.digest_length]u8 = undefined;
            h.final(&hram64);
            hram_batch[i] = Curve.scalar.reduce64(hram64);
        }

        var z_batch: [count]Curve.scalar.CompressedScalar = undefined;
        for (&z_batch) |*z| {
            crypto.random.bytes(z[0..16]);
            @memset(z[16..], 0);
        }

        var zs_sum = Curve.scalar.zero;
        for (z_batch, 0..) |z, i| {
            const zs = Curve.scalar.mul(z, s_batch[i]);
            zs_sum = Curve.scalar.add(zs_sum, zs);
        }
        zs_sum = Curve.scalar.mul8(zs_sum);

        var zhs: [count]Curve.scalar.CompressedScalar = undefined;
        for (z_batch, 0..) |z, i| {
            zhs[i] = Curve.scalar.mul(z, hram_batch[i]);
        }

        const zr = (try Curve.mulMulti(count, expected_r_batch, z_batch)).clearCofactor();
        const zah = (try Curve.mulMulti(count, a_batch, zhs)).clearCofactor();

        const zsb = try Curve.basePoint.mulPublic(zs_sum);
        if (zr.add(zah).sub(zsb).rejectIdentity()) |_| {
            return error.SignatureVerificationFailed;
        } else |_| {}
    }

    /// Ed25519 signatures with key blinding.
    pub const key_blinding = struct {
        /// Length (in bytes) of a blinding seed.
        pub const blind_seed_length = 32;

        /// A blind secret key.
        pub const BlindSecretKey = struct {
            prefix: [64]u8,
            blind_scalar: CompressedScalar,
            blind_public_key: BlindPublicKey,
        };

        /// A blind public key.
        pub const BlindPublicKey = struct {
            /// Public key equivalent, that can used for signature verification.
            key: PublicKey,

            /// Recover a public key from a blind version of it.
            pub fn unblind(blind_public_key: BlindPublicKey, blind_seed: [blind_seed_length]u8, ctx: []const u8) (IdentityElementError || NonCanonicalError || EncodingError || WeakPublicKeyError)!PublicKey {
                const blind_h = blindCtx(blind_seed, ctx);
                const inv_blind_factor = Scalar.fromBytes(blind_h[0..32].*).invert().toBytes();
                const pk_p = try (try Curve.fromBytes(blind_public_key.key.bytes)).mul(inv_blind_factor);
                return PublicKey.fromBytes(pk_p.toBytes());
            }
        };

        /// A blind key pair.
        pub const BlindKeyPair = struct {
            blind_public_key: BlindPublicKey,
            blind_secret_key: BlindSecretKey,

            /// Create an blind key pair from an existing key pair, a blinding seed and a context.
            pub fn init(key_pair: Ed25519.KeyPair, blind_seed: [blind_seed_length]u8, ctx: []const u8) (NonCanonicalError || IdentityElementError)!BlindKeyPair {
                var h: [Sha512.digest_length]u8 = undefined;
                Sha512.hash(&key_pair.secret_key.seed(), &h, .{});
                Curve.scalar.clamp(h[0..32]);
                const scalar = Curve.scalar.reduce(h[0..32].*);

                const blind_h = blindCtx(blind_seed, ctx);
                const blind_factor = Curve.scalar.reduce(blind_h[0..32].*);

                const blind_scalar = Curve.scalar.mul(scalar, blind_factor);
                const blind_public_key = BlindPublicKey{
                    .key = try PublicKey.fromBytes((Curve.basePoint.mul(blind_scalar) catch return error.IdentityElement).toBytes()),
                };

                var prefix: [64]u8 = undefined;
                prefix[0..32].* = h[32..64].*;
                prefix[32..64].* = blind_h[32..64].*;

                const blind_secret_key = BlindSecretKey{
                    .prefix = prefix,
                    .blind_scalar = blind_scalar,
                    .blind_public_key = blind_public_key,
                };
                return BlindKeyPair{
                    .blind_public_key = blind_public_key,
                    .blind_secret_key = blind_secret_key,
                };
            }

            /// Sign a message using a blind key pair, and optional random noise.
            /// Having noise creates non-standard, non-deterministic signatures,
            /// but has been proven to increase resilience against fault attacks.
            pub fn sign(key_pair: BlindKeyPair, msg: []const u8, noise: ?[noise_length]u8) (IdentityElementError || KeyMismatchError || NonCanonicalError || WeakPublicKeyError)!Signature {
                const scalar = key_pair.blind_secret_key.blind_scalar;
                const prefix = key_pair.blind_secret_key.prefix;

                return (try PublicKey.fromBytes(key_pair.blind_public_key.key.bytes))
                    .computeNonceAndSign(msg, noise, scalar, &prefix);
            }
        };

        /// Compute a blind context from a blinding seed and a context.
        fn blindCtx(blind_seed: [blind_seed_length]u8, ctx: []const u8) [Sha512.digest_length]u8 {
            var blind_h: [Sha512.digest_length]u8 = undefined;
            var hx = Sha512.init(.{});
            hx.update(&blind_seed);
            hx.update(&[1]u8{0});
            hx.update(ctx);
            hx.final(&blind_h);
            return blind_h;
        }
    };
};

test "key pair creation" {
    var seed: [32]u8 = undefined;
    _ = try fmt.hexToBytes(seed[0..], "8052030376d47112be7f73ed7a019293dd12ad910b654455798b4667d73de166");
    const key_pair = try Ed25519.KeyPair.generateDeterministic(seed);
    var buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{X}", .{&key_pair.secret_key.toBytes()}), "8052030376D47112BE7F73ED7A019293DD12AD910B654455798B4667D73DE1662D6F7455D97B4A3A10D7293909D1A4F2058CB9A370E43FA8154BB280DB839083");
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{X}", .{&key_pair.public_key.toBytes()}), "2D6F7455D97B4A3A10D7293909D1A4F2058CB9A370E43FA8154BB280DB839083");
}

test "signature" {
    var seed: [32]u8 = undefined;
    _ = try fmt.hexToBytes(seed[0..], "8052030376d47112be7f73ed7a019293dd12ad910b654455798b4667d73de166");
    const key_pair = try Ed25519.KeyPair.generateDeterministic(seed);

    const sig = try key_pair.sign("test", null);
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{X}", .{&sig.toBytes()}), "10A442B4A80CC4225B154F43BEF28D2472CA80221951262EB8E0DF9091575E2687CC486E77263C3418C757522D54F84B0359236ABBBD4ACD20DC297FDCA66808");
    try sig.verify("test", key_pair.public_key);
    try std.testing.expectError(error.SignatureVerificationFailed, sig.verify("TEST", key_pair.public_key));
}

test "batch verification" {
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const key_pair = Ed25519.KeyPair.generate();
        var msg1: [32]u8 = undefined;
        var msg2: [32]u8 = undefined;
        crypto.random.bytes(&msg1);
        crypto.random.bytes(&msg2);
        const sig1 = try key_pair.sign(&msg1, null);
        const sig2 = try key_pair.sign(&msg2, null);
        var signature_batch = [_]Ed25519.BatchElement{
            Ed25519.BatchElement{
                .sig = sig1,
                .msg = &msg1,
                .public_key = key_pair.public_key,
            },
            Ed25519.BatchElement{
                .sig = sig2,
                .msg = &msg2,
                .public_key = key_pair.public_key,
            },
        };
        try Ed25519.verifyBatch(2, signature_batch);

        signature_batch[1].sig = sig1;
        try std.testing.expectError(error.SignatureVerificationFailed, Ed25519.verifyBatch(signature_batch.len, signature_batch));
    }
}

test "test vectors" {
    const Vec = struct {
        msg_hex: *const [64:0]u8,
        public_key_hex: *const [64:0]u8,
        sig_hex: *const [128:0]u8,
        expected: ?anyerror,
    };

    const entries = [_]Vec{
        Vec{
            .msg_hex = "8c93255d71dcab10e8f379c26200f3c7bd5f09d9bc3068d3ef4edeb4853022b6",
            .public_key_hex = "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa",
            .sig_hex = "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a0000000000000000000000000000000000000000000000000000000000000000",
            .expected = error.WeakPublicKey, // 0
        },
        Vec{
            .msg_hex = "9bd9f44f4dcc75bd531b56b2cd280b0bb38fc1cd6d1230e14861d861de092e79",
            .public_key_hex = "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa",
            .sig_hex = "f7badec5b8abeaf699583992219b7b223f1df3fbbea919844e3f7c554a43dd43a5bb704786be79fc476f91d3f3f89b03984d8068dcf1bb7dfc6637b45450ac04",
            .expected = error.WeakPublicKey, // 1
        },
        Vec{
            .msg_hex = "aebf3f2601a0c8c5d39cc7d8911642f740b78168218da8471772b35f9d35b9ab",
            .public_key_hex = "f7badec5b8abeaf699583992219b7b223f1df3fbbea919844e3f7c554a43dd43",
            .sig_hex = "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa8c4bd45aecaca5b24fb97bc10ac27ac8751a7dfe1baff8b953ec9f5833ca260e",
            .expected = null, // 2 - small order R is acceptable
        },
        Vec{
            .msg_hex = "9bd9f44f4dcc75bd531b56b2cd280b0bb38fc1cd6d1230e14861d861de092e79",
            .public_key_hex = "cdb267ce40c5cd45306fa5d2f29731459387dbf9eb933b7bd5aed9a765b88d4d",
            .sig_hex = "9046a64750444938de19f227bb80485e92b83fdb4b6506c160484c016cc1852f87909e14428a7a1d62e9f22f3d3ad7802db02eb2e688b6c52fcd6648a98bd009",
            .expected = null, // 3 - mixed orders
        },
        Vec{
            .msg_hex = "e47d62c63f830dc7a6851a0b1f33ae4bb2f507fb6cffec4011eaccd55b53f56c",
            .public_key_hex = "cdb267ce40c5cd45306fa5d2f29731459387dbf9eb933b7bd5aed9a765b88d4d",
            .sig_hex = "160a1cb0dc9c0258cd0a7d23e94d8fa878bcb1925f2c64246b2dee1796bed5125ec6bc982a269b723e0668e540911a9a6a58921d6925e434ab10aa7940551a09",
            .expected = null, // 4 - cofactored verification
        },
        Vec{
            .msg_hex = "e47d62c63f830dc7a6851a0b1f33ae4bb2f507fb6cffec4011eaccd55b53f56c",
            .public_key_hex = "cdb267ce40c5cd45306fa5d2f29731459387dbf9eb933b7bd5aed9a765b88d4d",
            .sig_hex = "21122a84e0b5fca4052f5b1235c80a537878b38f3142356b2c2384ebad4668b7e40bc836dac0f71076f9abe3a53f9c03c1ceeeddb658d0030494ace586687405",
            .expected = null, // 5 - cofactored verification
        },
        Vec{
            .msg_hex = "85e241a07d148b41e47d62c63f830dc7a6851a0b1f33ae4bb2f507fb6cffec40",
            .public_key_hex = "442aad9f089ad9e14647b1ef9099a1ff4798d78589e66f28eca69c11f582a623",
            .sig_hex = "e96f66be976d82e60150baecff9906684aebb1ef181f67a7189ac78ea23b6c0e547f7690a0e2ddcd04d87dbc3490dc19b3b3052f7ff0538cb68afb369ba3a514",
            .expected = error.NonCanonical, // 6 - S > L
        },
        Vec{
            .msg_hex = "85e241a07d148b41e47d62c63f830dc7a6851a0b1f33ae4bb2f507fb6cffec40",
            .public_key_hex = "442aad9f089ad9e14647b1ef9099a1ff4798d78589e66f28eca69c11f582a623",
            .sig_hex = "8ce5b96c8f26d0ab6c47958c9e68b937104cd36e13c33566acd2fe8d38aa19427e71f98a4734e74f2f13f06f97c20d58cc3f54b8bd0d272f42b695dd7e89a8c2",
            .expected = error.NonCanonical, // 7 - S >> L
        },
        Vec{
            .msg_hex = "9bedc267423725d473888631ebf45988bad3db83851ee85c85e241a07d148b41",
            .public_key_hex = "f7badec5b8abeaf699583992219b7b223f1df3fbbea919844e3f7c554a43dd43",
            .sig_hex = "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff03be9678ac102edcd92b0210bb34d7428d12ffc5df5f37e359941266a4e35f0f",
            .expected = error.IdentityElement, // 8 - non-canonical R
        },
        Vec{
            .msg_hex = "9bedc267423725d473888631ebf45988bad3db83851ee85c85e241a07d148b41",
            .public_key_hex = "f7badec5b8abeaf699583992219b7b223f1df3fbbea919844e3f7c554a43dd43",
            .sig_hex = "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffca8c5b64cd208982aa38d4936621a4775aa233aa0505711d8fdcfdaa943d4908",
            .expected = error.IdentityElement, // 9 - non-canonical R
        },
        Vec{
            .msg_hex = "e96b7021eb39c1a163b6da4e3093dcd3f21387da4cc4572be588fafae23c155b",
            .public_key_hex = "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            .sig_hex = "a9d55260f765261eb9b84e106f665e00b867287a761990d7135963ee0a7d59dca5bb704786be79fc476f91d3f3f89b03984d8068dcf1bb7dfc6637b45450ac04",
            .expected = error.IdentityElement, // 10 - small-order A
        },
        Vec{
            .msg_hex = "39a591f5321bbe07fd5a23dc2f39d025d74526615746727ceefd6e82ae65c06f",
            .public_key_hex = "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            .sig_hex = "a9d55260f765261eb9b84e106f665e00b867287a761990d7135963ee0a7d59dca5bb704786be79fc476f91d3f3f89b03984d8068dcf1bb7dfc6637b45450ac04",
            .expected = error.IdentityElement, // 11 - small-order A
        },
    };
    for (entries) |entry| {
        var msg: [64 / 2]u8 = undefined;
        _ = try fmt.hexToBytes(&msg, entry.msg_hex);
        var public_key_bytes: [32]u8 = undefined;
        _ = try fmt.hexToBytes(&public_key_bytes, entry.public_key_hex);
        const public_key = Ed25519.PublicKey.fromBytes(public_key_bytes) catch |err| {
            try std.testing.expectEqual(entry.expected.?, err);
            continue;
        };
        var sig_bytes: [64]u8 = undefined;
        _ = try fmt.hexToBytes(&sig_bytes, entry.sig_hex);
        const sig = Ed25519.Signature.fromBytes(sig_bytes);
        if (entry.expected) |error_type| {
            try std.testing.expectError(error_type, sig.verify(&msg, public_key));
        } else {
            try sig.verify(&msg, public_key);
        }
    }
}

test "with blind keys" {
    const BlindKeyPair = Ed25519.key_blinding.BlindKeyPair;

    // Create a standard Ed25519 key pair
    const kp = Ed25519.KeyPair.generate();

    // Create a random blinding seed
    var blind: [32]u8 = undefined;
    crypto.random.bytes(&blind);

    // Blind the key pair
    const blind_kp = try BlindKeyPair.init(kp, blind, "ctx");

    // Sign a message and check that it can be verified with the blind public key
    const msg = "test";
    const sig = try blind_kp.sign(msg, null);
    try sig.verify(msg, blind_kp.blind_public_key.key);

    // Unblind the public key
    const pk = try blind_kp.blind_public_key.unblind(blind, "ctx");
    try std.testing.expectEqualSlices(u8, &pk.toBytes(), &kp.public_key.toBytes());
}

test "signatures with streaming" {
    const kp = Ed25519.KeyPair.generate();

    var signer = try kp.signer(null);
    signer.update("mes");
    signer.update("sage");
    const sig = signer.finalize();

    try sig.verify("message", kp.public_key);

    var verifier = try sig.verifier(kp.public_key);
    verifier.update("mess");
    verifier.update("age");
    try verifier.verify();
}

test "key pair from secret key" {
    const kp = Ed25519.KeyPair.generate();
    const kp2 = try Ed25519.KeyPair.fromSecretKey(kp.secret_key);
    try std.testing.expectEqualSlices(u8, &kp.secret_key.toBytes(), &kp2.secret_key.toBytes());
    try std.testing.expectEqualSlices(u8, &kp.public_key.toBytes(), &kp2.public_key.toBytes());
}
