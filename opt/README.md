# Local applications

Place Debian (`*.deb`) or AppImage (`*.AppImage`) files in this directory, then
run `Setup` or `Rebuild`. Vibespace mounts this directory at `/packages`.

- `.deb` packages are installed in the Ubuntu container with `apt`.
- AppImages are copied to `/opt/appimages` with executable permissions and get
  a normalized, version-free command, displayed during Setup. For example,
  `ZCode-3.2.3-win-x64.AppImage` gets the `zcode` command.

The command launches the application in the background, returns the console
prompt immediately, and writes output to
`~/.local/state/vibespace/appimages/<app>.log`.

Source files are not copied into the image and are ignored by Git. During
Setup, modern type 2 AppImages are validated and extracted once into persistent
storage, without FUSE or additional privileges. Legacy type 1 AppImages do not
support this extraction method and are rejected before their command is
created.

T3 Code is not installed natively. To use it, place its AppImage in this
directory like any other local application.
