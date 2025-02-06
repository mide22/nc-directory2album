#!/bin/bash
### About
# This shell script can create Nextcloud-Photo-Albums from your directory-organized photos/videos.
# Default behavior:
# Over all enabled users, take all first level directories inside /Photos, which are not hidden
# for each of them:
# 1. check if a file named .noimage, .noindex, .nomedia or .nomemories is in the directory, skip if this is the case
# 2. Get the info about the last script-run or "0" as fallback
# 3. Find multimedia files (images, videos) which are created or modified since last script-run and are not hidden and not in hidden subdirectories. Visible subdirectories will be processed too, even with an ignore-file!
# If no multimedia file found, process next directory
# 4. Before processing first file:
# 4.1 process files:scan on directory to be sure all files are known to nextcloud
# 4.2 photo album will be created, named by directory
# 5. All multimedia files found in the directory will be added to this album.
# 6. Timestamp when the directory was processed will be stored in user:setting directory2album "album_indexed_datetimes"
#
# Autor: Michael Deichen <https://github.com/mide22>
# License: GPL v3

### Settings
# ! directories without trailing slash /
#
# Path in user files where the album directories are stored
root_path_of_albums="Photos"
# todo: enhancement:
#  - use user:setting. Maybe photos "photosSourceDirectories" (php-array) or memories "timelinePath" (always a path?)
#  - or use a tag - how to get directories by tag viá occ?

### Maybe changes needed, depends on your hosting
# Directory of your nextcloud instance
nextcloud_dir="$(realpath "$(dirname "$(realpath "$0")")/../../")"

# Execution of OCC command
occ() {
  # "${nextcloud_dir}/occ" "$@"
  php "${nextcloud_dir}/occ" "$@"
  # /usr/bin/php83 "${nextcloud_dir}/occ" "$@"
}

### Installation
# Copy this script into apps/directory2album directory in your nextcloud instance and make it executable.
# Maybe the directory "apps" does not exist, so create it

### Usage
# just run it every time you added multimedia files to your directories. May run in a cronjob.

### End of settings

# Generate album name from the directory path
get_album_name_from_path() {
  local directory_path=$1
  local album_name
  album_name=$(basename "$directory_path")
  # replace | and : with - because that are reserved characters in datetime-storage
  album_name="${album_name//[|:]/-}"
  echo "${album_name}"
}

# reading album_indexed_datetime for all user albums. Format: album_indexed_datetimes[ALBUM NAME]=datetime
read_album_indexed_datetimes() {
  local setting_value
  local album_list
  album_indexed_datetimes=()
  setting_value=$(occ user:setting --default-value "" "${user_id}" directory2album "album_indexed_datetimes")
  IFS='|' read -r -a album_list <<<"${setting_value}"
  for data_string in "${album_list[@]}"; do
    local data_values
    IFS=':' read -r -a data_values <<<"${data_string}"
    album_indexed_datetimes["${data_values[0]}"]="${data_values[1]}"
  done
}

# Get datetime when the album was indexed last time. datetime = unix epoch / seconds since 1970
get_album_last_indexed_datetime() {
  local album_name=$1
  value="${album_indexed_datetimes["${album_name}"]}"
  re='^[0-9]+$'
  if ! [[ ${value} =~ ${re} ]]; then
    echo "0"
  else
    echo "${value}"
  fi
}

# Set datetime when the album was indexed last time. datetime = unix epoch / seconds since 1970
# Format: Albums are separated with a pipe | and all data (datetime only a.t.m.) are separated with a :
# In example: Album 1:123123123|Album 2:123123222
set_album_last_indexed_datetime() {
  local album_name=$1
  local datetime=$2
  album_indexed_datetimes["${album_name}"]="${datetime}"
  # need nameref for using all chars as array key in for-loop, incl. the evil space
  declare -n list=album_indexed_datetimes
  local setting_value=""
  for album_name in "${!list[@]}"; do
    setting_value="${setting_value}|${album_name}:${list[$album_name]}"
  done
  # remove leading |
  setting_value="${setting_value:1}"
  occ user:setting "${user_id}" directory2album "album_indexed_datetimes" "${setting_value}"
}

# Very simple user info extraction, not solid
get_user_info() {
  local info_key=$1
  local value
  value=$(occ user:info "${user_id}" | grep " ${info_key}: " | sed 's/^[^:]\+: \+//')
  echo "${value}"
}

# Find files in $directory and add them to $album_name
# Important: do not echo something when no file was found! This is used to know if something was changed.
find_and_add_files() {
  local first_file=1
  find "${directory}" -type f -not -path '*/.*' \( -newerct "@${last_indexed_datetime}" -or -newermt "@${last_indexed_datetime}" \) \( -iname "*.jpg" -or -iname "*.jpeg" -or -iname "*.png" -or -iname "*.tif" -or -iname "*.bmp" -or -iname "*.gif" -or -iname "*.mp4" -or -iname "*.mpg" -or -iname "*.mpeg" -or -iname "*.avi" -or -iname "*.mkv" \) -print0 |
    while IFS= read -r -d "" file; do
      if (("${first_file}" == 1)); then
        # Some actions before first file will be processed
        # Scan directory first, https://docs.nextcloud.com/server/latest/admin_manual/occ_command.html#scan
        scan_dir_path=$(realpath --relative-to "${nextcloud_dir}/data" "${directory}")
        echo "Scan directory ${scan_dir_path}."
        occ files:scan --path="${scan_dir_path}"
        echo "Create Album named ${album_name} for user ${user_id} and add files from directory ${directory}."
        occ photos:albums:create --no-interaction --no-warnings "${user_id}" "${album_name}"
        first_file=0
      fi

      relative_file_path=$(realpath --relative-to "${user_dir}/files" "${file}")
      echo "Add file to ${album_name}: ${relative_file_path}"
      occ photos:albums:add --no-interaction --no-warnings "${user_id}" "${album_name}" "${file}"
    done
}

# Process to create an album for user, based on directory
directory_to_album() {
  local directory=$1

  # check for ignore-files
  if [ -e "${directory}/.noimage" ] || [ -e "${directory}/.noindex" ] || [ -e "${directory}/.nomedia" ] || [ -e "${directory}/.nomemories" ]; then
    echo "Found hidden ignore-file in directory ${directory} from user ${user_id}, skip process!" >&2
    return 1
  fi

  album_name=$(get_album_name_from_path "${directory}")

  # check last run
  last_indexed_datetime=$(get_album_last_indexed_datetime "${album_name}")
  now_datetime=$(date +%s)
  if ((last_indexed_datetime > now_datetime)); then
    echo "Album ${album_name} from user ${user_id} seems to be up to date because it was last indexed on $(date -d "@${last_indexed_datetime}"), skip process!" >&2
    return 1
  fi

  echo "Processing album ${album_name} from user ${user_id}, last indexed on $(date -d "@${last_indexed_datetime}")."

  local result=""
  result=$(find_and_add_files)
  # Set indexed date time only when something was changed, just for performance reasons.
  if [ ! -z "${result}" ]; then
    set_album_last_indexed_datetime "${album_name}" "${now_datetime}"
    echo "${result}"
  fi
}

test_environment() {
  # Check occ command
  if [ ! "$(occ -V)" ]; then
    echo "Critical: OCC command does not work. Executable? PHP-Version?" >&2
    exit 1
  fi

  # Check for support of assoc array with space in key and nameref
  local arr
  local nref
  declare -A arr
  arr["one"]="first"
  arr["just a key"]="with a value"
  arr["three"]="third"
  declare -n nref=arr
  if ! [ "${nref["just a key"]}" = "with a value" ]; then
    echo "Critical: Your shell does not support nameref. Try bash version 4+. See https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html#index-declare" >&2
    exit 1
  fi
}

run() {
  # Global list of album names and the datetime of their last indexing
  declare -A album_indexed_datetimes

  # Run it for each enabled user
  (occ user:list) | while IFS= read -r user_line; do
    user_id=$(echo -n "${user_line}" | sed 's/^ *- *\([^:]\+\):.\+/\1/')

    # Skip user if is not enabled
    enabled="$(get_user_info "enabled")"
    if [ ! "${enabled}" = "true" ]; then
      echo "User ${user_id} is not enabled, skip." >&2
      continue
    fi
    echo "Working on user ${user_id}."
    read_album_indexed_datetimes
    user_dir="$(get_user_info "user_directory")"

    # Process 1st level directories only in $root_path_of_albums without hidden ones
    find "${user_dir}/files/${root_path_of_albums}" -depth -maxdepth 1 -mindepth 1 -type d -not -path '*/.*' -print0 |
      while IFS= read -r -d '' directory; do
        directory_to_album "${directory}"
      done
  done
}

test_environment
run
