# snap2flatpak

Convert Ubuntu snap applications to Flatpak.
This tool downloads and decompresses the Snap's squashfs file and recompiles it into the Flatpak format.
Note that it has only been tested with one Electron apps.

You may need to customize the script.

## Dependencies

- jq
- unsquashfs
- tar
- flatpak-builder
- python3
- curl

## Usage

```shell
git clean -fdx
./convert.sh SNAP_APPNAME
flatpak run com.snap2flatpak.SNAP_APPNAME
```
