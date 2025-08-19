#!/usr/bin/env bash


# In a fresh WSL make sure to:
# sudo apt install zip
# sudo apt install jq



addon_dir=$(pwd)
# echo $addon_dir



# Load API tokens.
# https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR/include_tokens.sh"




mkdir -p "$addon_dir/.release"



### Create changelog.
echo "Creating changelog..."

# \ prevents the line from being interpreted as a header in markdown.
# Two blanks at the end of line enforce line break in markdown.
changelog="$addon_dir/.release/CHANGELOG.md"
changelog_wowi="$addon_dir/.release/CHANGELOG_WOWI.txt"
rm -f "$changelog"
rm -f "$changelog_wowi"

projectName=${PWD##*/}
# echo $projectName

projectVersion=$( git describe )
# echo $projectVersion

project_github_url=$( git remote get-url origin )
# echo $project_github_url
project_github_url=${project_github_url%.git}
# echo $project_github_url



# Function to process tag messages
process_tag_message() {
  local tag_message="$1"
  local changelog_file="$2"
  local wowi_file="$3"

  if [ -n "$tag_message" ]; then
    while IFS= read -r line; do
      if [[ "$line" == "#"* ]]; then
        line="\\#${line:1}"
      elif [[ "$line" == "-"* ]]; then
        line="\\-${line:1}"
      elif [[ "$line" == "*"* ]]; then
        line="\\*${line:1}"
      fi
      line="$line  "
      echo "$line" >> "$changelog_file"
    done <<< "$tag_message"
    echo "$tag_message" >> "$wowi_file"
  fi
}


# Get the most recent tags of this branch ordered from newest to oldest.
max_tags=15
alltags=$(git tag --sort=-creatordate --merged $currentbranch | head -n $((max_tags+1)))

lasttag=
tag_count=0
for sometag in $alltags; do
  tag_count=$((tag_count + 1))

  if [ -z "$lasttag" ]; then
    
    echo "\### $sometag ($(git log -1 --format=%ai $sometag)) ###  " >> "$changelog"
    echo "### $sometag ($(git log -1 --format=%ai $sometag)) ###" >> "$changelog_wowi"
    lasttag=$sometag
    
  else

    # Print the github diff link.
    echo "($project_github_url/compare/$sometag...$lasttag)  " >> "$changelog"
    echo "([url=\"$project_github_url/compare/$sometag...$lasttag\"]$project_github_url/compare/$sometag...$lasttag[/url])" >> "$changelog_wowi"
    # Print the annotation of the tag. (If the tag has no annotation the message of the last commit is printed.)
    tagmessage=$(git tag -l --format='%(contents)' $lasttag)
    
    # Process tagmessage line by line to make the text appear as intended in markdown.
    process_tag_message "$tagmessage" "$changelog" "$changelog_wowi"
    
    echo "  " >> "$changelog"
    echo >> "$changelog_wowi"

    if [ "$tag_count" -le "$max_tags" ]; then
      echo "\### $sometag ($(git log -1 --format=%ai $sometag)) ###  " >> "$changelog"
      echo "### $sometag ($(git log -1 --format=%ai $sometag)) ###" >> "$changelog_wowi"
    fi
    lasttag=$sometag
  fi
  
done

if [ "$tag_count" -le "$max_tags" ]; then
  tagmessage=$(git tag -l --format='%(contents)' "$lasttag")
  process_tag_message "$tagmessage" "$changelog" "$changelog_wowi"
fi

echo
echo "$(<"$changelog")"
echo

echo "...done."
echo
echo



### Make zip file
echo "Creating zip..."

rm -rf "$addon_dir/.release/$projectName"
rsync -av . "$addon_dir/.release/$projectName" --exclude ".*" --exclude "*.bat" --exclude "README.*" >/dev/null

cd "$addon_dir/.release/$projectName"
sed -i "s/@project-version@/$projectVersion/g" *.toc

cd "$addon_dir/.release"
zip_file=$projectName\_$projectVersion.zip
zip -r $zip_file $projectName >/dev/null

echo "...done."
echo







### Process toc files.

cd "$addon_dir"

for toc_file in *.toc; do

  # echo $toc_file
  toc_version=$( grep "## Interface" $toc_file | cut -d' ' -f3 | tr -d '\r' )
  # echo $toc_version
  
  major="${toc_version:0: -4}"
  minor="${toc_version:(${#toc_version}-4):2}"
  patch="${toc_version:(${#toc_version}-2):2}"
  # echo "$major $minor $patch"
  
  # Remove leading zeros.
  # https://stackoverflow.com/questions/11123717/removing-leading-zeros-before-passing-a-shell-variable-to-another-command
  major=$((10#$major))
  minor=$((10#$minor))
  patch=$((10#$patch))
  # echo "$major $minor $patch"
  
  toc_version="$major.$minor.$patch"
  # echo $toc_version
  if [ -z $game_versions ]; then
    game_versions="$toc_version"
  else
    game_versions+=",$toc_version"
  fi
  
  if [ -z $curse_id ]; then
    curse_id=$( grep "## X-Curse-Project-ID" $toc_file | cut -d' ' -f3 | tr -d '\r' )
  else
    if [ $curse_id != $( grep "## X-Curse-Project-ID" $toc_file | cut -d' ' -f3 | tr -d '\r' ) ]; then
      echo "ERROR: TOC files have different curse ids."
      exit
    fi
  fi
  
  if [ -z $wowi_id ]; then
    wowi_id=$( grep "## X-WoWI-ID" $toc_file | cut -d' ' -f3 | tr -d '\r' )
  else
    if [ $wowi_id != $( grep "## X-WoWI-ID" $toc_file | cut -d' ' -f3 | tr -d '\r' ) ]; then
      echo "ERROR: TOC files have different wowi ids."
      exit
    fi
  fi
  
  if [ -z $wago_id ]; then
    wago_id=$( grep "## X-Wago-ID" $toc_file | cut -d' ' -f3 | tr -d '\r' )
  else
    if [ $wago_id != $( grep "## X-Wago-ID" $toc_file | cut -d' ' -f3 | tr -d '\r' ) ]; then
      echo "ERROR: TOC files have different wago ids."
      exit
    fi
  fi
  
done

# echo $game_versions
# echo $curse_id
# echo $wowi_id
# echo $wago_id




# Not all of my projects are already on Wago.
# So check if a Wago ID was found in the TOC files.
if [ -n "$wago_id" ]; then

  ### Upload to Wago.
  # https://docs.wago.io/

  echo "Uploading to Wago..."

  # Get the list of available game versions.
  wago_game_versions=$( curl -s https://addons.wago.io/api/data/game | jq -c '.patches')
  # echo $wago_game_versions

  # Go through all game types ("retail", "classic", etc.) in wago_game_versions
  # and create the support properties string.
  wago_support_properties=""
  for wago_type_quoted in $(jq -c 'keys[]' <<< "$wago_game_versions")
  do
    wago_type=$(echo "$wago_type_quoted" | tr -d '"') # Remove quotes
    wago_type_versions=$(jq --arg t "$wago_type" -c '.[$t]' <<< "$wago_game_versions")
    
    current_type_support_property="\"supported_${wago_type}_patches\": ["
    match_found=false # Flag to track if a match was found for this type.
    
    # Go through game_versions of our addon and check if it is among wago_type_versions.
    for game_version in ${game_versions//,/ }
    do   
      # Use jq to check if game_version exists in wago_type_versions.
      if jq --arg v "$game_version" -e 'contains([$v])' <<< "$wago_type_versions" >/dev/null; then
        match_found=true
        current_type_support_property+="\"$game_version\","
      fi
    done
    
    current_type_support_property=$(echo "$current_type_support_property" | sed 's/,*$//g')
    current_type_support_property+="]"
    # echo "$current_type_support_property"
    
    # Add to wago_support_properties only if a match was found.
    if $match_found; then
      if [ -z "$wago_support_properties" ]; then
        wago_support_properties="$current_type_support_property"
      else
        wago_support_properties="$wago_support_properties, $current_type_support_property"
      fi
    fi
    
  done


  # https://unix.stackexchange.com/questions/360800/what-does-eoc-means
  wago_metadata=$( cat <<EOF
{
  "label": "$projectVersion",
  "stability": "stable",
  "changelog": $( jq --slurp --raw-input '.' < "$changelog" ),
  $wago_support_properties
}
EOF
  )
  # echo $wago_metadata



  result_file="$addon_dir/.release/wago_curl_result.json"

  result=$( echo "$wago_metadata" | curl -sS --ipv4 --retry 3 --retry-delay 10 \
        -w "%{http_code}" -o "$result_file" \
        -H "authorization: Bearer $WAGO_API_KEY" \
        -H "accept: application/json" \
        -F "metadata=</dev/stdin" \
        -F "file=@$addon_dir/.release/$zip_file" \
        "https://addons.wago.io/api/projects/$wago_id/version")

  # echo $result

  if [ $result = 201 ]; then
    echo "...success!"
    echo
    rm -f "$result_file"
  else
    echo "Error! ($result)"
    echo "$(<"$result_file")"
    exit
  fi

fi



# Not all of my projects are already on WoW-Interface.
# So check if a WOWI ID was found in the TOC files.
if [ -n "$wowi_id" ]; then

  ### Upload to WoW-Interface.
  # https://www.wowinterface.com/forums/showthread.php?t=51835
  # To check which game versions there are: https://api.wowinterface.com/addons/compatible.json

  echo "Uploading to WoW-Interface..."

  wowi_args=()
  wowi_args+=(-F "id=$wowi_id")
  wowi_args+=(-F "version=$projectVersion")
  wowi_args+=(-F "changelog=<$changelog_wowi")
  wowi_args+=(-F "updatefile=@$addon_dir/.release/$zip_file")
  wowi_args+=(-F "compatible=$game_versions")

  # echo "${wowi_args[@]}"

  result_file="$addon_dir/.release/wowi_curl_result.json"

  # -sS     Run curl in silent mode, and show no output unless there is an error.
  # --ipv4  Otherwise it takes a long time trying ipv6 apparently.

  result=$( curl -sS --ipv4 --retry 3 --retry-delay 10 \
            -w "%{response_code}" -o "$result_file" \
            -H "x-api-token: $WOWI_API_TOKEN" \
            "${wowi_args[@]}" \
            "https://api.wowinterface.com/addons/update" )


  # echo $result
  if [ $result = 202 ]; then
    echo "...success!"
    echo
    rm -f "$result_file"
  else
    echo "Error! ($result)"
    echo "$(<"$result_file")"
    exit
  fi

fi



### Upload to Curseforge.
# https://support.curseforge.com/en/support/solutions/articles/9000197321-curseforge-upload-api#Project-Upload-File-API


echo "Uploading to Curseforge..."


# Get the list of available game versions.
cf_game_versions=$( curl -s -H "x-api-token: $CF_API_KEY" https://wow.curseforge.com/api/game/versions )
# echo $cf_game_versions


# Replace comma with blank to iterate.
# https://stackoverflow.com/questions/27702452/loop-through-a-comma-separated-shell-variable
for game_version in ${game_versions//,/ }
do
    
  cf_game_id=$( echo $cf_game_versions | jq --arg i "$game_version" '.[] | select(.name == $i) | .id')
  # echo "$game_version -> $cf_game_id "
  
  if [ -z $cf_game_ids ]; then
    cf_game_ids="$cf_game_id"
  else
    cf_game_ids+=",$cf_game_id"
  fi

done

# echo $cf_game_ids



# https://unix.stackexchange.com/questions/360800/what-does-eoc-means
cf_metadata=$( cat <<EOF
{
  "displayName": "$projectVersion",
  "gameVersions": [$cf_game_ids],
  "releaseType": "release",
  "changelog": $( jq --slurp --raw-input '.' < "$changelog" ),
  "changelogType": "markdown"
}
EOF
)
# echo $cf_metadata



# # To test without actually sending (because 'file' field is missing).
# echo $cf_metadata | curl -sS --ipv4 --retry 3 --retry-delay 10 -H "x-api-token: $CF_API_KEY" -F "metadata=</dev/stdin" "https://wow.curseforge.com/api/projects/$curse_id/upload-file" 
# exit



result_file="$addon_dir/.release/curseforge_curl_result.json"

# -sS            Run curl in silent mode, and show no output unless there is an error.
# --ipv4         Otherwise it takes a long time trying ipv6 apparently.
# --trace-ascii  To print the payload that is actually sent.

result=$( echo "$cf_metadata" | curl -sS --ipv4 --retry 3 --retry-delay 10 \
    -w "%{http_code}" -o "$result_file" \
    -H "x-api-token: $CF_API_KEY" \
    -F "metadata=</dev/stdin" \
    -F "file=@$addon_dir/.release/$zip_file" \
    "https://wow.curseforge.com/api/projects/$curse_id/upload-file" )




# echo $result
if [ $result = 200 ]; then
  echo "...success!"
  echo
  rm -f "$result_file"
else
	echo "Error! ($result)"
	echo "$(<"$result_file")"
	exit
fi
