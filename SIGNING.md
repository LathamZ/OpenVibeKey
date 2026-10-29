# Signing strategy for multiple macOS projects

2026-10-30. Generic personal identity v1 issued and VibeKey migrated at user request. No external certificate delivery or recipient-Mac acceptance is claimed.


## Selected self-managed certificate distribution design

The user explicitly selected a recipient-installed personal certificate route. The reviewable
[personal signing design](docs/signing/PERSONAL-SIGNING.md) specifies a developer-level
self-signed CA:false leaf, public-only certificate bundle, CodeSigning-only recipient trust,
separate app permissions, renewal/removal and independent-Mac acceptance. It includes a
recipient guide and an unsigned certificate-profile template. This does not require Apple
Developer Program membership. The generic identity has been issued, explicitly trusted for current-user CodeSigning and installed in VibeKey; public delivery to others remains pending.

Installing the certificate is not a promise of default Gatekeeper acceptance: the existing
app passes codesign verification but is rejected by read-only spctl assessment. A real
quarantined download on a receiver Mac remains untested. Current VibeKey identity is retained.

## Current VibeKey identity

Current identity: self-signed LathamZ Software Signing, CA:false, digitalSignature/codeSigning,
RSA3072/SHA256, five-year validity. Private key is in login keychain; exact public certificate,
fingerprint and metadata are archived outside this repository. The user explicitly approved
only current-user CodeSigning trust, with pre-existing trust entries verified unchanged.

VibeKey now runs lr.15 build24 using this identity. The embedded CMS leaf was matched to the
public CER; builds23/24 have different hashes and the same designated requirement. After one
user migration authorization, normal23→24 update retained Accessibility/Input Monitoring in
the app's own context, with a fresh PID completing navigation. Same implementation, differing
package build metadata; no new physical gesture or independent-recipient acceptance claimed.

The former VibeKey-specific local identity and old signed app/config are retained for rollback.
Future builds reuse the new fixed identity via local configuration. Replacing a certificate is
not an ordinary update; do not regenerate it for each build or assume grants survive rotation.

Foreign-shell permission probes can be attributed to their Codex host and are invalid for this
comparison; actual app-owned PermissionCenter and matching startup-success PID were used.

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
- VibeKey was explicitly migrated to the generic identity after review. A real subject-name change needs
  a new certificate and changes this certificate-pinned DR; merely renaming a keychain label does
  not rename the certificate. Do not rotate the working VibeKey identity just for appearance.
- Only the public certificate may be shared with testers. The signing private key stays local or
  in an encrypted backup under the developer's control; never distribute it with the app or Git.
- Trusting the signer, passing Gatekeeper/notarization and granting Accessibility/Input Monitoring
  are separate decisions. Installing a certificate does not grant app privacy permissions.

The generic personal identity was created at explicit user request; no Apple Developer ID account or external recipient trust was created. External installation and publication still require receiver-side validation.
