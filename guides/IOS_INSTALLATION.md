# Personal iPhone build

**Status:** Runner-only source profile implemented; current ownership tree awaits full CI and
native migration verification. `setup.md` owns actual metadata/artifacts; native builds are held.

Use the pinned Flutter version and `.github/workflows/personal-ios.yml` on GitHub Actions.
The release/AOT build uses `flutter build ios --release --no-codesign` with SOURCE_REVISION.
Do not run a full build locally. The workflow validates the unsigned IPA, source/version/build
identity and checksum using `tool/personal_ios.py`; inspect downloaded artifacts as well.

The payload contains only Runner, empty entitlements and one AppIcon. No HealthKit, App Group,
Watch, widgets, Live Activity, Firebase, telemetry, cloud coach or bundled signing secrets.
Keep generated AccessorySetupKit descriptors, Bluetooth permissions and the exact required
background modes: bluetooth-central, location, audio, fetch and processing. GPS asks While In
Use; the explicitly approved Home region behavior has its separate Always permission.
No silent audio keepalive or extra capability is authorized.

Preserve `com.akshat.personal.whoop` as the source bundle base and the exact final signed
identity already on the phone. Changing source/package names must not create another app or
container. Before an upgrade: verified off-phone encrypted export, exact signed identity and
expiry, source/version/checksum and schema compatibility. Never uninstall to resolve signing.

Full Linux app/package/visual checks precede native compilation. Native/payload success does
not establish phone acceptance: verify launch/offline, ASK pairing/denial/reconnect, locked and
background sync, range loss/return, termination/first unlock, no duplicate ACK/data, phone-step
permissions, GPS/voice, notifications, camera/media restore and at least a 72-hour soak.
Test in-place data/keychain/pairing preservation and natural signing refresh before promotion.
Keep the accepted recovery IPA until the replacement passes; `todo.md` owns all remaining gates.
