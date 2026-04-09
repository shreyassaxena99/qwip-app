#!/bin/bash
set -e

ASSETS_DIR="/Users/shreyassaxena/development/qwip/qwip/Assets.xcassets"

download_icon() {
  local lucide_name="$1"
  local asset_name="$2"
  local dir="${ASSETS_DIR}/${asset_name}.imageset"

  mkdir -p "$dir"

  local svg_url="https://unpkg.com/lucide-static@latest/icons/${lucide_name}.svg"
  if curl -sfL "$svg_url" -o "${dir}/${asset_name}.svg"; then
    echo "✓ ${asset_name}"
  else
    echo "✗ FAILED: ${lucide_name}"
    return 1
  fi

  cat > "${dir}/Contents.json" << CONTENTS
{
  "images": [
    {
      "filename": "${asset_name}.svg",
      "idiom": "universal"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  },
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template"
  }
}
CONTENTS
}

download_icon "coffee"         "ic_coffee"
download_icon "laptop-2"       "ic_laptop_2"
download_icon "dumbbell"       "ic_dumbbell"
download_icon "hotel"          "ic_hotel"
download_icon "book-open"      "ic_book_open"
download_icon "utensils"       "ic_utensils"
download_icon "map-pin"        "ic_map_pin"
download_icon "volume-x"       "ic_volume_x"
download_icon "volume-1"       "ic_volume_1"
download_icon "volume-2"       "ic_volume_2"
download_icon "check-circle"   "ic_check_circle"
download_icon "credit-card"    "ic_credit_card"
download_icon "key-round"      "ic_key_round"
download_icon "x"              "ic_x"
download_icon "heart"          "ic_heart"
download_icon "star"           "ic_star"
download_icon "share-2"        "ic_share_2"
download_icon "route"          "ic_route"
download_icon "wifi"           "ic_wifi"
download_icon "plug-zap"       "ic_plug_zap"
download_icon "sun"            "ic_sun"
download_icon "paw-print"      "ic_paw_print"
download_icon "users"          "ic_users"
download_icon "phone"          "ic_phone"
download_icon "globe"          "ic_globe"
download_icon "arrow-up-right" "ic_arrow_up_right"
download_icon "arrow-right"    "ic_arrow_right"
download_icon "check"          "ic_check"
download_icon "user"           "ic_user"
download_icon "settings"       "ic_settings"
download_icon "info"           "ic_info"
download_icon "circle-user"    "ic_circle_user"
download_icon "chevron-right"  "ic_chevron_right"
download_icon "briefcase"      "ic_briefcase"
download_icon "house"          "ic_house"
download_icon "building-2"     "ic_building_2"
download_icon "mail"           "ic_mail"
download_icon "sun-moon"       "ic_sun_moon"
download_icon "map"            "ic_map"
download_icon "shield-check"   "ic_shield_check"
download_icon "log-out"        "ic_log_out"
download_icon "trash-2"        "ic_trash_2"

echo "All done."
