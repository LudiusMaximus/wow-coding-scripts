#!/usr/bin/env bash


mkdir -p .release

changelog=".release/CHANGELOG.txt"
changelog_wowi=".release/CHANGELOG_WOWI.txt"
rm -f $changelog
rm -f $changelog_wowi

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







# Make zip file

rm -rf .release/$projectName 
rsync -av . .release/$projectName --exclude ".*" --exclude "*.bat" --exclude "README.*" >/dev/null

cd .release/$projectName
sed -i "s/@project-version@/$projectVersion/g" *.toc

cd ..
zip -r $projectName\_$projectVersion.zip $projectName >/dev/null

