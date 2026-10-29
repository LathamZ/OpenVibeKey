# Signing strategy for multiple macOS projects

2026-10-30. Proposal for future projects; no certificate rotation or external distribution is performed here.


## Selected self-managed certificate distribution design

The user explicitly selected a recipient-installed personal certificate route. The reviewable
[personal signing design](docs/signing/PERSONAL-SIGNING.md) specifies a developer-level
self-signed CA:false leaf, public-only certificate bundle, CodeSigning-only recipient trust,
separate app permissions, renewal/removal and independent-Mac acceptance. It includes a
recipient guide and an unsigned certificate-profile template. This does not require Apple
Developer Program membership. No new identity has been issued or trusted yet.

Installing the certificate is not a promise of default Gatekeeper acceptance: the existing
app passes codesign verification but is rejected by read-only spctl assessment. A real
quarantined download on a receiver Mac remains untested. Current VibeKey identity is retained.

## Current VibeKey identity

The local identity is self-signed, subject/issuer Open VibeKey Local Development. It is a leaf
certificate (CA:false), digitalSignature key usage, codeSigning EKU, valid for3650days. Its private
key is in the user's login keychain, with codesign as the permitted application. The user explicitly
approved current-user CodeSigning-only trust. No system-root/TLS trust was configured.

This certificate can sign multiple applications; its subject name does not restrict it to VibeKey.
It does not establish Apple-verified developer identity and cannot issue other certificates.
The per-app bundle identifier and requirement still distinguish each application and its grants.

One actual A/build21→B/build22 replacement passed: distinct CDHashes, identical certificate DR,
permissions remained ready in the normal application's own context, and navigation startup
succeeded in the new PID. Same implementation, different package build metadata. This does not
prove certificate replacement or every future OS/update preserves permissions; gestures were not
retested. Foreign-shell permission probes were attributed to their Codex host and are invalid for
this comparison; use the actual app-owned PermissionCenter and PID-tagged startup evidence.

## Proposed roles

| Role | Identity | Distribution |
|---|---|---|
| Local development | Persistent personal local certificate; future neutral name e.g. LathamZ Local Development | Own Macs, explicit local trust as required |
| Self-managed distribution (selected) | Personal self-signed leaf and public certificate | Recipients explicitly manage code-signing trust, Gatekeeper launch decisions and app permissions; cross-Mac acceptance required |
| Apple distribution route (optional alternative) | Apple-issued Developer ID Application plus notarization | Give recipients the signed/notarized app or archive; no custom personal-certificate installation workflow |
| Signed macOS PKG | Developer ID Installer in addition to the signed app | Installer certificate signs PKG, not a substitute for the application's signature |

Apple describes Developer ID signing and notarization as the outside-App-Store distribution path:
https://developer.apple.com/developer-id/
Certificate roles and account requirements:
https://developer.apple.com/help/account/certificates/create-developer-id-certificates

## Project conventions to adopt after review

- Use developer-scoped identities, not one freshly generated certificate for every project or build.
  Separate local-development and public-release keys. Keep each app's bundle identifier stable.
- Continue the existing VibeKey certificate for VibeKey updates. A real subject-name change needs
  a new certificate and changes this certificate-pinned DR; merely renaming a keychain label does
  not rename the certificate. Do not rotate the working VibeKey identity just for appearance.
- Only the public certificate may be shared with testers. The signing private key stays local or
  in an encrypted backup under the developer's control; never distribute it with the app or Git.
- Trusting the signer, passing Gatekeeper/notarization and granting Accessibility/Input Monitoring
  are separate decisions. Installing a certificate does not grant app privacy permissions.

No new general-purpose identity or Developer ID account was created by this proposal. Future
creation, migration, external trust installation and publication require their own implementation
and verification.
