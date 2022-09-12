#!/bin/sh

tempFolder="./pkgtemp"
outputFolder="./Build"
name="DEPNotifyOnboarder"
identifier="us.konicaminolta.kmbs.pkg.$name"
version="$(cat ./VERSION)"
appleID="eric_summers@icloud.com"
teamID="L48NM5T974"
keychainProfile="notary-eric_summers"
certName="Developer ID Installer: Eric Summers (L48NM5T974)"

if [ "$(whoami)" != "root" ] ; then
    echo "This script must run as the root user."
    exit 1
fi

/bin/mkdir -p "$outputFolder"

/bin/rm -rf "$tempFolder"
/bin/mkdir -p "$tempFolder"
/bin/mkdir -p "$tempFolder/root/Library/Application Support/DEPNotify/"
/bin/mkdir -p "$tempFolder/root/Library/LaunchDaemons/"
/bin/mkdir -p "$tempFolder/root/Applications/Utilities/"

/bin/cp ./DEPNotifyOnboarder.sh "$tempFolder/root/Library/Application Support/DEPNotify/"
/bin/cp ./DEPNotifyReset.sh "$tempFolder/root/Library/Application Support/DEPNotify/"
/bin/cp ./LaunchDaemons/us.konicaminolta.kmbs.DEPNotifyOnboarder.plist "$tempFolder/root/Library/LaunchDaemons/"
/usr/bin/ditto ./Utilities/DEPNotify.app/ "$tempFolder/root/Applications/Utilities/DEPNotify.app/"

mkdir "$tempFolder/scripts"
cat << EOF > "$tempFolder/scripts/postinstall"
#!/bin/sh
/bin/launchctl load /Library/LaunchDaemons/us.konicaminolta.kmbs.DEPNotifyOnboarder.plist
EOF
chmod 755 "$tempFolder/scripts/postinstall"

chown -R root:wheel "$tempFolder"
chflags 755 "$tempFolder/scripts/postinstall"
chflags 755 "$tempFolder/root/Library/Application Support/DEPNotify/DEPNotifyOnboarder.sh"
chflags 755 "$tempFolder/root/Library/Application Support/DEPNotify/DEPNotifyReset.sh"
chflags 644 "$tempFolder/root/Library/LaunchDaemons/us.konicaminolta.kmbs.DEPNotifyOnboarder.plist"

/usr/bin/pkgbuild --root "$tempFolder/root/" --scripts "$tempFolder/scripts/" --identifier "$identifier" --version "$version" "$tempFolder/$name-$version.pkg" 

/usr/bin/productbuild --package "$tempFolder/$name-$version.pkg" --sign "$certName" "$outputFolder/$name-$version.pkg"

/bin/rm -rf "$tempFolder"

echo "Enter \"$keychainProfile\" when asked for Profile name."
/usr/bin/xcrun notarytool store-credentials --apple-id "$appleID" --team-id "$teamID"

/usr/bin/xcrun notarytool submit "$outputFolder/$name-$version.pkg" --keychain-profile "$keychainProfile" --wait

/usr/bin/xcrun stapler staple "$outputFolder/$name-$version.pkg"

/usr/sbin/spctl --assess --type install -vv "$outputFolder/$name-$version.pkg"

exit 0