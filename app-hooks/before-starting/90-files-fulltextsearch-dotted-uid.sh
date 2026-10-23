#!/bin/sh
# Temporary workaround for https://github.com/nextcloud/files_fulltextsearch/issues/389
# Remove when the fix is released upstream for Nextcloud 35.
set -eu

app_dir=/var/www/html/custom_apps/files_fulltextsearch
source_file="$app_dir/lib/Service/SearchService.php"
patch_file="$(dirname "$0")/files-fulltextsearch-dotted-uid.patch"

# Apps installed through the App Store are not necessarily present during setup.
[ -f "$source_file" ] && [ -f "$app_dir/appinfo/info.xml" ] || exit 0

version=$(sed -n 's/.*<version>\([^<]*\)<\/version>.*/\1/p' "$app_dir/appinfo/info.xml" | head -n 1)
case "$version" in
    35.*) ;;
    *) exit 0 ;;
esac

fixed='$userId = $searchResult->getRequest()->getAuthor();'
broken='$userId = $this->filesService->secureUsername($searchResult->getRequest()->getAuthor());'

if grep -Fq "$fixed" "$source_file"; then
    echo "files_fulltextsearch: dotted-UID fix already present"
    exit 0
fi

if ! grep -Fq "$broken" "$source_file"; then
    echo "WARNING: files_fulltextsearch $version changed; review dotted-UID fix" >&2
    exit 0
fi

if ! patch --batch --fuzz=0 --dry-run -p1 -d "$app_dir" < "$patch_file" >/dev/null; then
    echo "WARNING: files_fulltextsearch dotted-UID patch does not apply; keeping Nextcloud available" >&2
    exit 0
fi

patch --batch --fuzz=0 -p1 -d "$app_dir" < "$patch_file"
if ! php -l "$source_file" >/dev/null; then
    patch --batch --fuzz=0 -R -p1 -d "$app_dir" < "$patch_file"
    echo "WARNING: files_fulltextsearch patch failed PHP syntax check; reverted" >&2
    exit 0
fi

echo "files_fulltextsearch $version: applied temporary dotted-UID fix"
