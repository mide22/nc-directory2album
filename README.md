# Bash script for creating Nextcloud-Photo-Albums from your directory-organized photos or videos

## System requirements
* Bash version 4 or newer
* Nextcloud Photos app

## Default behavior
* Over all enabled users, take all first level directories inside /Photos, which are not hidden
* For each found directory:
  1. Check if a file named .noimage, .noindex, .nomedia or .nomemories is in the directory, skip if this is the case
  1. Get the info about the last script-run or "0" as fallback
  1. Find multimedia files (images, videos) which are created or modified since last script-run and are not hidden and not in hidden subdirectories.
     Visible subdirectories will be processed too, even with an ignore-file! 
  
     If no multimedia file found, process next directory
  1. Before processing first file:
     1. Execute files:scan on directory to be sure all files are known to nextcloud
     1. Photo album will be created, named by directory
  1. All multimedia files found in the directory will be added to this album.
  1. Timestamp when the directory was processed will be stored in user:setting directory2album "album_indexed_datetimes"

## Settings
* You can set up the directory where your directory-organized photos/videos are. Default: Photos
* In the function get_album_name_from_path you can tune your album names. Default: basename of the directory without | and : because that are reserved characters. 

## Installation
Copy this script into apps/directory2album directory in your nextcloud instance and make it executable.

## Usage
1. Test the script in your test environment first.
1. Run the script every time you added multimedia files to your directories. May run a cronjob.

## Legal
Autor: Michael Deichen <https://github.com/mide22>

License: GPL v3
