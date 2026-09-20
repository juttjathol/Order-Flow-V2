#!/usr/bin/env node
// Generate an Ed25519 keypair for LICENSE_SIGNING_KEY (PKCS8 base64 private)
// and the matching SPKI public key for the app (kLicensePubKey).
import { generateKeyPairSync } from "node:crypto";

const { publicKey, privateKey } = generateKeyPairSync("ed25519");
const pub = publicKey.export({ type: "spki", format: "der" }).toString("base64");
const priv = privateKey.export({ type: "pkcs8", format: "der" }).toString("base64");
console.log("PUBLIC_SPKI_B64=" + pub);
console.log("LICENSE_SIGNING_KEY=" + priv);
console.log("Put LICENSE_SIGNING_KEY in Cloudflare Pages secrets. Commit only the public key.");
