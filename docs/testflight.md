# TestFlight

The `testflight` workflow archives a Release build and uploads it to App Store Connect. Release builds use
`https://assistant-link.fly.dev`. Signing is automatic and cloud-managed, so no certificates or provisioning
profiles are stored in the repository or in secrets.

## One-time setup

1. In App Store Connect, create the app record with the bundle ID `ai.assistantlink.app`.
2. Under **Users and Access › Integrations › App Store Connect API**, create a key with the **App Manager** role
   and download the `.p8` (Apple offers it only once). Note the key ID and the issuer ID.
3. Add these repository secrets (Settings › Secrets and variables › Actions):
   - `ASC_KEY_ID`: the key ID.
   - `ASC_ISSUER_ID`: the issuer ID.
   - `ASC_KEY_P8`: the full contents of the `.p8` file.
   - `APPLE_TEAM_ID`: your Apple Developer team ID.

## Upload a build

Actions › testflight › Run workflow. The build number is the run number; the version (0.1.0) comes from
`project.yml`. If the run fails, the `testflight-logs` artifact has the archive and export logs.

## Install

In App Store Connect, add internal testers under the app's TestFlight tab. Once the build has finished processing,
testers install it with the TestFlight app.
