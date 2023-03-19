#!/usr/bin/env bash


addon_dir=$(pwd)
# echo $addon_dir

mkdir -p "$addon_dir/.release"



### Create changelog.
echo "Create changelog..."


changelog="$addon_dir/.release/CHANGELOG.txt"
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



# Get all tags of this branch ordered from newest to oldest.
alltags=$(git tag --sort=-creatordate --merged $currentbranch)

lasttag=
for sometag in $alltags
do

  if [ -z "$lasttag" ]; then
    echo "### $sometag ($(git log -1 --format=%ai $sometag)) ###" >> "$changelog"
    echo "### $sometag ($(git log -1 --format=%ai $sometag)) ###" >> "$changelog_wowi"
    lasttag=$sometag
    
  else

    # Print the github diff link.
    echo "($project_github_url/compare/$sometag...$lasttag)" >> "$changelog"
    echo "([url=\"$project_github_url/compare/$sometag...$lasttag\"]$project_github_url/compare/$sometag...$lasttag[/url])" >> "$changelog_wowi"
    # Print the annotation of the tag. If the tag has no annotation
    # the message of the last commit is printed.
    tagmessage=$(git tag -l --format='%(contents)' $lasttag)
    if [ -n "$tagmessage" ]; then
      echo "$tagmessage" >> "$changelog"
      echo "$tagmessage" >> "$changelog_wowi"
    fi
    echo >> "$changelog"
    echo >> "$changelog_wowi"

    echo "### $sometag ($(git log -1 --format=%ai $sometag)) ###" >> "$changelog"
    echo "### $sometag ($(git log -1 --format=%ai $sometag)) ###" >> "$changelog_wowi"
    lasttag=$sometag
  fi
  
done

echo "$(git tag -l --format='%(contents)' $lasttag)" >> "$changelog"
echo "$(git tag -l --format='%(contents)' $lasttag)" >> "$changelog_wowi"

echo
echo "$(<"$changelog")"
echo

echo "...done."
echo ""



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
echo ""







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
  
done

# echo $game_versions
# echo $curse_id
# echo $wowi_id






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
  rm -f "$result_file"
else
	echo "Error! ($result)"
	echo "$(<"$result_file")"
	exit
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
  "changelogType": "text"
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

pwd

result=$( echo "$cf_metadata" | curl -sS --ipv4 --retry 3 --retry-delay 10 \
    -w "%{http_code}" -o "$result_file" \
    -H "x-api-token: $CF_API_KEY" \
    -F "metadata=</dev/stdin" \
    -F "file=@$addon_dir/.release/$zip_file" \
    "https://wow.curseforge.com/api/projects/$curse_id/upload-file" )




# echo $result
if [ $result = 200 ]; then
  echo "...success!"
  rm -f "$result_file"
else
	echo "Error! ($result)"
	echo "$(<"$result_file")"
	exit
fi
