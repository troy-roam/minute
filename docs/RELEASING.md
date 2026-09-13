# Releasing minute

## Local archive

Create an ad-hoc signed release archive for local testing:

```sh
./script/package_release.sh 0.1.0
```

The result is `dist/minute-0.1.0.zip`.

## Developer ID and notarization

Install a Developer ID Application certificate, then configure a notarytool
keychain profile once:

```sh
xcrun notarytool store-credentials minute-notary
```

Build, sign, submit, wait for Apple, and staple the ticket:

```sh
MINUTE_SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
MINUTE_NOTARY_PROFILE="minute-notary" \
./script/package_release.sh 0.1.0
```

Validate the final app before publishing:

```sh
codesign --verify --deep --strict --verbose=2 dist/minute.app
spctl --assess --type execute --verbose=2 dist/minute.app
xcrun stapler validate dist/minute.app
```
