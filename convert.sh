#!/bin/bash

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "${HERE}"

# from bashkit https://github.com/Wuageorg/bashkit
check::cmd() {
    # check if a shell command is available
    local cmd
    for cmd; do
        # else test command
        command -v "${cmd}" &> /dev/null \
        || { echo "${cmd} not found" >&2; exit 127; }
    done
}

json::from_yaml() {
    python3 -c '
import sys, json, yaml;
json.dump(
    yaml.safe_load(
        open(sys.argv[1])
    ),
    sys.stdout,
    indent=4,
    default=str
)' "$@"
}

check::cmd jq unsquashfs tar flatpak-builder python3 curl

snap_name="$1"
snap_url=https://search.apps.ubuntu.com/api/v1/package/${snap_name}

appid=com.snap2flatpak.${snap_name}

pkg=snap2flatpak.snap

if [[ ! -f "$pkg" ]]; then
    pkg_url=$(curl -L "$snap_url" | jq -r .anon_download_url)
    curl -L "$pkg_url" -o "$pkg"
fi

sqfs=squashfs-root

if [[ ! -d "$sqfs" ]]; then
    unsquashfs "$pkg"
    # dirty patch
    if [[ -f "$sqfs"/desktop-common.sh ]]; then
        head -n -2 "$sqfs"/desktop-common.sh > "$sqfs"/desktop-common.sh.tmp
        mv "$sqfs"/desktop-common.sh.tmp "$sqfs"/desktop-common.sh
        echo 'unset LIBGL_DRIVERS_PATH; unset LIBVA_DRIVERS_PATH; exec "$@"' >> "$sqfs"/desktop-common.sh
        chmod +x "$sqfs"/desktop-common.sh
    fi

    # cp .desktop files
    mkdir -p "$sqfs"/icons/hicolor/512x512/apps/
    mkdir "$sqfs"/applications/
    find "$sqfs" -name '*.desktop' | while read -r i; do
        exportname="${appid}.${i##*/}"
        sed 's|Exec=.*$|Exec=snap2flatpak.sh|;s|Icon=.*$|Icon='"${exportname}|" < "$i" > "$sqfs"/applications/"$exportname";
        cp "$sqfs"/meta/gui/icon.png "$sqfs"/icons/hicolor/512x512/apps/"$exportname".png
    done
    cp "$sqfs"/meta/gui/icon.png "$sqfs"/icons/hicolor/512x512/apps/"${appid}".png
fi

if [[ ! -f "fs.tar" ]]; then
    tar cf "fs.tar" "$sqfs"
fi

meta=$(json::from_yaml "${sqfs}"/meta/snap.yaml)
command=$(printf '%s' "$meta" | jq -r .apps."${snap_name}".command)

cat > init.sh <<-EOF

export SNAP_USER_DATA="\${HOME}"/.var/app/${appid}
export SNAP_USER_COMMON="\${SNAP_USER_DATA}"


ln -s "\$SNAP_USER_DATA"/config "\$SNAP_USER_DATA"/.config 2>/dev/null
ln -s "\$SNAP_USER_DATA"/cache  "\$SNAP_USER_DATA"/.cache  2>/dev/null
ln -s "\$SNAP_USER_DATA"/cache  "\$HOME"/.cache            2>/dev/null
ln -s "\$SNAP_USER_DATA"/config "\$HOME"/.config           2>/dev/null

touch "\$SNAP_USER_DATA"/config/user-dirs.dirs
touch "\$SNAP_USER_DATA"/config/user-dirs.locale

$(printf '%s' "$meta" | jq -r .apps."${snap_name}".environment'|to_entries|map("export \(.key)=\(.value|tostring)")|.[]')

# override SNAP_DESKTOP_RUNTIME
export SNAP_DESKTOP_RUNTIME=

echo SNAP=\$SNAP
echo SNAP_ARCH=\$SNAP_ARCH
echo SNAP_USER_DATA=\$SNAP_USER_DATA
echo SNAP_USER_COMMON=\$SNAP_USER_COMMON
echo SNAP_DESKTOP_RUNTIME=\$SNAP_DESKTOP_RUNTIME
echo LD_LIBRARY_PATH=\$LD_LIBRARY_PATH
echo LD_PRELOAD=\$LD_PRELOAD
echo PATH=\$PATH
echo TMPDIR=\$TMPDIR
echo LIBGL_DRIVERS_PATH=\$LIBGL_DRIVERS_PATH
echo LIBVA_DRIVERS_PATH=\$LIBVA_DRIVERS_PATH

exec "\${SNAP}/"${command} "\${@}"
EOF


# cat > "${appid}.appdata.xml" <<EOF
# <?xml version="1.0" encoding="UTF-8"?>
# <component type="desktop">
#   <id>${appid}</id>
#   <name>${snap_name}</name>
#   <launchable type="desktop-id">${appid}.desktop</launchable>
#   <provides>
#     <binary>${appid}</binary>
#   </provides>
# </component>
# EOF


# "desktop-file-name-suffix" : " 🏳️‍⚧️",

cat > "${appid}.json" <<EOF
{
    "app-id" : "${appid}",
    "base": "org.electronjs.Electron2.BaseApp",
    "base-version": "23.08",
    "runtime": "org.freedesktop.Platform",
    "runtime-version": "23.08",
    "sdk": "org.freedesktop.Sdk",
    "command" : "snap2flatpak.sh",
    "finish-args" : [
        "--share=network",
        "--share=ipc",
        "--socket=pulseaudio",
        "--socket=x11",
        "--device=dri",
        "--env=SNAP=/app/share",
        "--env=SNAP_ARCH=amd64"
    ],
    "modules" : [
        {
            "name" : "${snap_name}",
            "buildsystem" : "simple",
            "build-commands" : [
                "install -m755 -p -D init.sh /app/bin/snap2flatpak.sh",
                "mkdir -p /app/share /app/lib",
                "tar xf fs.tar -C /app/share --strip-components 1"
            ],
            "sources" : [
                {
                    "type": "file",
                    "path": "init.sh"
                },
                {
                    "type": "file",
                    "path": "fs.tar"
                }
            ]
        },
        {
            "name": "libsecret",
            "buildsystem": "meson",
            "config-opts": [
                "-Dmanpage=false",
                "-Dvapi=false",
                "-Dgtk_doc=false"
            ],
            "cleanup": [
                "/bin",
                "/include",
                "/lib/pkgconfig",
                "/share/gir-1.0",
                "/share/man"
            ],
            "sources": [
                {
                    "type": "archive",
                    "url": "https://download.gnome.org/sources/libsecret/0.20/libsecret-0.20.4.tar.xz",
                    "sha256": "325a4c54db320c406711bf2b55e5cb5b6c29823426aa82596a907595abb39d28"
                }
            ]
        }
    ]
}
EOF

flatpak-builder --user --arch=x86_64 --force-clean --install builds "${appid}.json"

