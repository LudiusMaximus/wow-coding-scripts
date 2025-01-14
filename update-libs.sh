#!/bin/bash

# Call this script with a directory path as first argument.
# It will traverse all subdirectories and for every found .pkgmeta file
# it will download the stated libs and copy them into the addon's folder.


# In a fresh WSL make sure to install svn like this:
# sudo apt update
# sudo apt full-upgrade
# sudo apt autoremove
# sudo apt install subversion



# The following allows communication between the background function checkout_external and main process.
# https://stackoverflow.com/questions/13207292/bash-background-process-modify-global-variable
rendevouz="/dev/shm/ludiusUpdateLibs"
# Use a directory as a mutex, such that only one process is accessing rendevouz at a time.
# It has to be done with a directory, because mkdir is an atomic operation (unlike touch with a file).
# https://stackoverflow.com/questions/6870221/is-there-any-mutex-semaphore-mechanism-in-shell-scripts
mutex="/tmp/ludiusMutex"


# Bare carriage-return character.
carriage_return=$( printf "\r" )

# Simple .pkgmeta YAML processor.
yaml_keyvalue() {
	yaml_key=${1%%:*}
	yaml_value=${1#$yaml_key:}
	yaml_value=${yaml_value#"${yaml_value%%[! ]*}"} # trim leading whitespace
	yaml_value=${yaml_value#[\'\"]} # trim leading quotes
	yaml_value=${yaml_value%[\'\"]} # trim trailing quotes
}


# SVN date helper function
strtotime() {
	local value="$1" # datetime string
	local format="$2" # strptime string
	if [[ "${OSTYPE,,}" == *"darwin"* ]]; then # bsd
		date -j -f "$format" "$value" "+%s" 2>/dev/null
	else # gnu
		date -d "$value" +%s 2>/dev/null
	fi
}

set_info_git() {
	si_repo_dir="$1"
	si_repo_type="git"
	si_repo_url=$( git -C "$si_repo_dir" remote get-url origin 2>/dev/null | sed -e 's/^git@\(.*\):/https:\/\/\1\//' )
	if [ -z "$si_repo_url" ]; then # no origin so grab the first fetch url
		si_repo_url=$( git -C "$si_repo_dir" remote -v | awk '/(fetch)/ { print $2; exit }' | sed -e 's/^git@\(.*\):/https:\/\/\1\//' )
	fi

	# Populate filter vars.
	si_project_hash=$( git -C "$si_repo_dir" show --no-patch --format="%H" 2>/dev/null )
	si_project_abbreviated_hash=$( git -C "$si_repo_dir" show --no-patch --abbrev=7 --format="%h" 2>/dev/null )
	si_project_author=$( git -C "$si_repo_dir" show --no-patch --format="%an" 2>/dev/null )
	si_project_timestamp=$( git -C "$si_repo_dir" show --no-patch --format="%at" 2>/dev/null )
	si_project_date_iso=$( TZ='' printf "%(%Y-%m-%dT%H:%M:%SZ)T" "$si_project_timestamp" )
	si_project_date_integer=$( TZ='' printf "%(%Y%m%d%H%M%S)T" "$si_project_timestamp" )
	# XXX --depth limits rev-list :\ [ ! -s "$(git rev-parse --git-dir)/shallow" ] || git fetch --unshallow --no-tags
	si_project_revision=$( git -C "$si_repo_dir" rev-list --count "$si_project_hash" 2>/dev/null )

	# Get the tag for the HEAD.
	si_previous_tag=
	si_previous_revision=
	_si_tag=$( git -C "$si_repo_dir" describe --tags --always --abbrev=7 2>/dev/null )
	si_tag=$( git -C "$si_repo_dir" describe --tags --always --abbrev=0 2>/dev/null )
	# Set $si_project_version to the version number of HEAD. May be empty if there are no commits.
	si_project_version=$si_tag
	# The HEAD is not tagged if the HEAD is several commits past the most recent tag.
	if [ "$si_tag" = "$si_project_hash" ]; then
		# --abbrev=0 expands out the full sha if there was no previous tag
		si_project_version=$_si_tag
		si_previous_tag=
		si_tag=
	elif [ "$_si_tag" != "$si_tag" ]; then
		# not on a tag
		si_project_version=$( git -C "$si_repo_dir" describe --tags --abbrev=7 --exclude="*[Aa][Ll][Pp][Hh][Aa]*" 2>/dev/null )
		si_previous_tag=$( git -C "$si_repo_dir" describe --tags --abbrev=0 --exclude="*[Aa][Ll][Pp][Hh][Aa]*" 2>/dev/null )
		si_tag=
	else # we're on a tag, just jump back one commit
		if [[ ${si_tag,,} != *"beta"* && ${si_tag,,} != *"alpha"* ]]; then
			# full release, ignore beta tags
			si_previous_tag=$( git -C "$si_repo_dir" describe --tags --abbrev=0 --exclude="*[Aa][Ll][Pp][Hh][Aa]*" --exclude="*[Bb][Ee][Tt][Aa]*" HEAD~ 2>/dev/null )
		else
			si_previous_tag=$( git -C "$si_repo_dir" describe --tags --abbrev=0 --exclude="*[Aa][Ll][Pp][Hh][Aa]*" HEAD~ 2>/dev/null )
		fi
	fi
}

set_info_svn() {
	si_repo_dir="$1"
	si_repo_type="svn"

	# Temporary file to hold results of "svn info".
	_si_svninfo="${si_repo_dir}/.svn/release_sh_svninfo"
	svn info -r BASE "$si_repo_dir" 2>/dev/null > "$_si_svninfo"

	if [ -s "$_si_svninfo" ]; then
		_si_root=$( awk '/^Repository Root:/ { print $3; exit }' < "$_si_svninfo" )
		_si_url=$( awk '/^URL:/ { print $2; exit }' < "$_si_svninfo" )
		_si_revision=$( awk '/^Last Changed Rev:/ { print $NF; exit }' < "$_si_svninfo" )
		si_repo_url=$_si_root

		case ${_si_url#${_si_root}/} in
		tags/*)
			# Extract the tag from the URL.
			si_tag=${_si_url#${_si_root}/tags/}
			si_tag=${si_tag%%/*}
			si_project_revision="$_si_revision"
			;;
		*)
			# Check if the latest tag matches the working copy revision (/trunk checkout instead of /tags)
			_si_tag_line=$( svn log --verbose --limit 1 "$_si_root/tags" 2>/dev/null | awk '/^   A/ { print $0; exit }' )
			_si_tag=$( echo "$_si_tag_line" | awk '/^   A/ { print $2 }' | awk -F/ '{ print $NF }' )
			_si_tag_from_revision=$( echo "$_si_tag_line" | sed -e 's/^.*:\([0-9]\{1,\}\)).*$/\1/' ) # (from /project/trunk:N)

			if [ "$_si_tag_from_revision" = "$_si_revision" ]; then
				si_tag="$_si_tag"
				si_project_revision=$( svn info "$_si_root/tags/$si_tag" 2>/dev/null | awk '/^Last Changed Rev:/ { print $NF; exit }' )
			else
				# Set $si_project_revision to the highest revision of the project at the checkout path
				si_project_revision=$( svn info --recursive "$si_repo_dir" 2>/dev/null | awk '/^Last Changed Rev:/ { print $NF }' | sort -nr | head -n1 )
			fi
			;;
		esac

		if [ -n "$si_tag" ]; then
			si_project_version="$si_tag"
		else
			si_project_version="r$si_project_revision"
		fi

		# Get the previous tag and it's revision
		_si_limit=$((si_project_revision - 1))
		_si_tag=$( svn log --verbose --limit 1 "$_si_root/tags" -r $_si_limit:1 2>/dev/null | awk '/^   A/ { print $0; exit }' | awk '/^   A/ { print $2 }' | awk -F/ '{ print $NF }' )
		if [ -n "$_si_tag" ]; then
			si_previous_tag="$_si_tag"
			si_previous_revision=$( svn info "$_si_root/tags/$_si_tag" 2>/dev/null | awk '/^Last Changed Rev:/ { print $NF; exit }' )
		fi

		# Populate filter vars.
		si_project_author=$( awk '/^Last Changed Author:/ { print $0; exit }' < "$_si_svninfo" | cut -d" " -f4- )
		_si_timestamp=$( awk '/^Last Changed Date:/ { print $4,$5; exit }' < "$_si_svninfo" )
		si_project_timestamp=$( strtotime "$_si_timestamp" "%F %T" )
		si_project_date_iso=$( TZ='' printf "%(%Y-%m-%dT%H:%M:%SZ)T" "$si_project_timestamp" )
		si_project_date_integer=$( TZ='' printf "%(%Y%m%d%H%M%S)T" "$si_project_timestamp" )
		# SVN repositories have no project hash.
		si_project_hash=
		si_project_abbreviated_hash=

		rm -f "$_si_svninfo" 2>/dev/null
	fi
}

set_info_hg() {
	si_repo_dir="$1"
	si_repo_type="hg"
	si_repo_url=$( hg --cwd "$si_repo_dir" paths -q default )
	if [ -z "$si_repo_url" ]; then # no default so grab the first path
		si_repo_url=$( hg --cwd "$si_repo_dir" paths | awk '{ print $3; exit }' )
	fi

	# Populate filter vars.
	si_project_hash=$( hg --cwd "$si_repo_dir" log -r . --template '{node}' 2>/dev/null )
	si_project_abbreviated_hash=$( hg --cwd "$si_repo_dir" log -r . --template '{node|short}' 2>/dev/null )
	si_project_author=$( hg --cwd "$si_repo_dir" log -r . --template '{author}' 2>/dev/null )
	si_project_timestamp=$( hg --cwd "$si_repo_dir" log -r . --template '{date}' 2>/dev/null | cut -d. -f1 )
	si_project_date_iso=$( TZ='' printf "%(%Y-%m-%dT%H:%M:%SZ)T" "$si_project_timestamp" )
	si_project_date_integer=$( TZ='' printf "%(%Y%m%d%H%M%S)T" "$si_project_timestamp" )
	si_project_revision=$( hg --cwd "$si_repo_dir" log -r . --template '{rev}' 2>/dev/null )

	# Get tag info
	si_tag=
	# I'm just muddling through revsets, so there is probably a better way to do this
	# Ignore tag commits, so v1.0-1 will package as v1.0
	if [ "$( hg --cwd "$si_repo_dir" log -r '.-filelog(.hgtags)' --template '{rev}' 2>/dev/null )" == "" ]; then
		_si_tip=$( hg --cwd "$si_repo_dir" log -r 'last(parents(.))' --template '{rev}' 2>/dev/null )
	else
		_si_tip=$( hg --cwd "$si_repo_dir" log -r . --template '{rev}' 2>/dev/null )
	fi
	si_previous_tag=$( hg --cwd "$si_repo_dir" log -r "$_si_tip" --template '{latesttag}' 2>/dev/null )
	# si_project_version=$( hg --cwd "$si_repo_dir" log -r "$_si_tip" --template "{ ifeq(changessincelatesttag, 0, latesttag, '{latesttag}-{changessincelatesttag}-m{node|short}') }" 2>/dev/null ) # git style
	si_project_version=$( hg --cwd "$si_repo_dir" log -r "$_si_tip" --template "{ ifeq(changessincelatesttag, 0, latesttag, 'r{rev}') }" 2>/dev/null ) # svn style
	if [ "$si_previous_tag" = "$si_project_version" ]; then
		# we're on a tag
		si_tag=$si_previous_tag
		si_previous_tag=$( hg --cwd "$si_repo_dir" log -r "last(parents($_si_tip))" --template '{latesttag}' 2>/dev/null )
	fi
	si_previous_revision=$( hg --cwd "$si_repo_dir" log -r "$si_previous_tag" --template '{rev}' 2>/dev/null )
}






###
### Process .pkgmeta again to perform any pre-move-folders actions.
###

retry() {
	local result=0
	local count=1
	while [[ "$count" -le 3 ]]; do
		[[ "$result" -ne 0 ]] && {
			echo -e "\033[01;31mRetrying (${count}/3)\033[0m" >&2
		}
		"$@" && { result=0 && break; } || result="$?"
		count="$((count + 1))"
		sleep 3
	done
	return "$result"
}


checkout_external() {

	_external_dir=$1
	_external_uri=$2
	_external_tag=$3
	_external_type=$4
	_external_slug=$5 # unused until we can easily fetch the project id
	_external_checkout_type=$6

	_cqe_checkout_dir="$tmpdir/$_external_dir/"
	mkdir -p "$_cqe_checkout_dir"
	if [ "$_external_type" = "git" ]; then
		if [ -z "$_external_tag" ]; then
			echo "Fetching latest version of external $_external_uri"
			retry git clone -q --depth 1 "$_external_uri" "$_cqe_checkout_dir" || return 1
		elif [ "$_external_tag" != "latest" ]; then
			echo "Fetching $_external_checkout_type \"$_external_tag\" from external $_external_uri"
			if [ "$_external_checkout_type" = "commit" ]; then
				retry git clone -q "$_external_uri" "$_cqe_checkout_dir" || return 1
				git -C "$_cqe_checkout_dir" checkout -q "$_external_tag" || return 1
			else
				git -c advice.detachedHead=false clone -q --depth 1 --branch "$_external_tag" "$_external_uri" "$_cqe_checkout_dir" || return 1
			fi
		else # [ "$_external_tag" = "latest" ]; then
			retry git clone -q --depth 50 "$_external_uri" "$_cqe_checkout_dir" || return 1
			_external_tag=$( git -C "$_cqe_checkout_dir" for-each-ref refs/tags --sort=-creatordate --format=%\(refname:short\) --count=1 )
			if [ -n "$_external_tag" ]; then
				echo "Fetching tag \"$_external_tag\" from external $_external_uri"
				git -C "$_cqe_checkout_dir" checkout -q "$_external_tag" || return 1
			else
				echo "Fetching latest version of external $_external_uri"
			fi
		fi

		# pull submodules
		git -C "$_cqe_checkout_dir" submodule -q update --init --recursive || return 1

		set_info_git "$_cqe_checkout_dir"
		echo "Checked out $( git -C "$_cqe_checkout_dir" describe --always --tags --abbrev=7 --long )" #$si_project_abbreviated_hash
	elif [ "$_external_type" = "svn" ]; then
		if [[ $external_uri == *"/trunk" ]]; then
			_cqe_svn_trunk_url=$_external_uri
			_cqe_svn_subdir=
		else
			_cqe_svn_trunk_url="${_external_uri%/trunk/*}/trunk"
			_cqe_svn_subdir=${_external_uri#${_cqe_svn_trunk_url}/}
		fi

		if [ -z "$_external_tag" ]; then
			echo "Fetching latest version of external $_external_uri"
			retry svn checkout -q "$_external_uri" "$_cqe_checkout_dir" || return 1
		else
			_cqe_svn_tag_url="${_cqe_svn_trunk_url%/trunk}/tags"
			if [ "$_external_tag" = "latest" ]; then
				_external_tag=$( svn log --verbose --limit 1 "$_cqe_svn_tag_url" 2>/dev/null | awk '/^   A \/tags\// { print $2; exit }' | awk -F/ '{ print $3 }' )
				if [ -z "$_external_tag" ]; then
					_external_tag="latest"
				fi
			fi
			if [ "$_external_tag" = "latest" ]; then
				echo "No tags found in $_cqe_svn_tag_url"
				echo "Fetching latest version of external $_external_uri"
				retry svn checkout -q "$_external_uri" "$_cqe_checkout_dir" || return 1
			else
				_cqe_external_uri="${_cqe_svn_tag_url}/$_external_tag"
				if [ -n "$_cqe_svn_subdir" ]; then
					_cqe_external_uri="${_cqe_external_uri}/$_cqe_svn_subdir"
				fi
				echo "Fetching tag \"$_external_tag\" from external $_cqe_external_uri"
				retry svn checkout -q "$_cqe_external_uri" "$_cqe_checkout_dir" || return 1
			fi
		fi
		set_info_svn "$_cqe_checkout_dir"
		echo "Checked out r$si_project_revision"
	elif [ "$_external_type" = "hg" ]; then
		if [ -z "$_external_tag" ]; then
			echo "Fetching latest version of external $_external_uri"
			retry hg clone -q "$_external_uri" "$_cqe_checkout_dir" || return 1
		elif [ "$_external_tag" != "latest" ]; then
			echo "Fetching $_external_checkout_type \"$_external_tag\" from external $_external_uri"
			retry hg clone -q --updaterev "$_external_tag" "$_external_uri" "$_cqe_checkout_dir" || return 1
		else # [ "$_external_tag" = "latest" ]; then
			retry hg clone -q "$_external_uri" "$_cqe_checkout_dir" || return 1
			_external_tag=$( hg --cwd "$_cqe_checkout_dir" log -r . --template '{latesttag}' )
			if [ -n "$_external_tag" ]; then
				echo "Fetching tag \"$_external_tag\" from external $_external_uri"
				hg --cwd "$_cqe_checkout_dir" update -q "$_external_tag"
			else
				echo "Fetching latest version of external $_external_uri"
			fi
		fi
		set_info_hg "$_cqe_checkout_dir"
		echo "Checked out r$si_project_revision"
	else
		echo "Unknown external: $_external_uri" >&2
		return 1
	fi
  



  while ! mkdir "$mutex" 2>/dev/null; do
    wait -n
  done
  
  # echo "  Remembering to copy $_cqe_checkout_dir to $_external_dir in file: $rendevouz"
  if [ -f "$rendevouz" ]; then
    . "$rendevouz"
  else
    declare -A toCopy
  fi
  toCopy["$_external_dir"]="$_cqe_checkout_dir"
  declare -p toCopy > "$rendevouz"
  
  rmdir "$mutex"
  
}



external_pids=()

external_dir=
external_uri=
external_tag=
external_type=
external_slug=
external_checkout_type=
process_external() {

	if [ -n "$external_dir" ] && [ -n "$external_uri" ] && [ -z "$skip_externals" ]; then
      
		# convert old curse repo urls
		case $external_uri in
			*git.curseforge.com*|*git.wowace.com*)
				external_type="git"
				# git://git.curseforge.com/wow/$slug/mainline.git -> https://repos.curseforge.com/wow/$slug
				external_uri=${external_uri%/mainline.git}
				external_uri="https://repos${external_uri#*://git}"
				;;
			*svn.curseforge.com*|*svn.wowace.com*)
				external_type="svn"
				# svn://svn.curseforge.com/wow/$slug/mainline/trunk -> https://repos.curseforge.com/wow/$slug/trunk
				external_uri=${external_uri/\/mainline/}
				external_uri="https://repos${external_uri#*://svn}"
				;;
			*hg.curseforge.com*|*hg.wowace.com*)
				external_type="hg"
				# http://hg.curseforge.com/wow/$slug/mainline -> https://repos.curseforge.com/wow/$slug
				external_uri=${external_uri%/mainline}
				external_uri="https://repos${external_uri#*://hg}"
				;;
			svn:*)
				# just in case
				external_type="svn"
				;;
			*)
				if [ -z "$external_type" ]; then
					external_type="git"
				fi
				;;
		esac

		if [[ $external_uri == "https://repos.curseforge.com/wow/"* || $external_uri == "https://repos.wowace.com/wow/"* ]]; then
			if [ -z "$external_slug" ]; then
				external_slug=${external_uri#*/wow/}
				external_slug=${external_slug%%/*}
			fi

			# check if the repo is svn
			_svn_path=${external_uri#*/wow/$external_slug/}
			if [[ "$_svn_path" == "trunk"* ]]; then
				external_type="svn"
			elif [[ "$_svn_path" == "tags/"* ]]; then
				external_type="svn"
				# change the tag path into the trunk path and use the tag var so it gets logged as a tag
				external_tag=${_svn_path#tags/}
				external_tag=${external_tag%%/*}
				external_uri="${external_uri%/tags*}/trunk${_svn_path#tags/$external_tag}"
			fi
		fi

		echo "Fetching external: $external_dir"
		checkout_external "$external_dir" "$external_uri" "$external_tag" "$external_type" "$external_slug" "$external_checkout_type" &> "$tmpdir/.$BASHPID.externalout" &
		external_pids+=($!)
  fi
	external_dir=
	external_uri=
	external_tag=
	external_type=
	external_slug=
	external_checkout_type=
}




# Handle folding sections in CI logs
start_group() { echo "$1"; }
end_group() { echo; }

processPkgmeta() {

  # Clear data from previous directories.
  rm "$rendevouz" 2>/dev/null
  rmdir "$mutex" 2>/dev/null
  
  
  local pkgmeta_file="$1/.pkgmeta"
  
  tmpdir="$1/.tmp"  
  
  # Removing previous temp directory (if any) and create new one.
  rm -fr "$tmpdir"
  mkdir -p "$tmpdir"
  
  yaml_eof=
	while [ -z "$yaml_eof" ]; do
		IFS='' read -r yaml_line || yaml_eof="true"
		# Skip commented out lines.
		if [[ $yaml_line =~ ^[[:space:]]*\# ]]; then
			continue
		fi
		# Strip any trailing CR character.
		yaml_line=${yaml_line%$carriage_return}

		case $yaml_line in
		[!\ ]*:*)
			# Started a new section, so checkout any queued externals.
			process_external
			# Split $yaml_line into a $yaml_key, $yaml_value pair.
			yaml_keyvalue "$yaml_line"
      
			# Set the $pkgmeta_phase for stateful processing.
			pkgmeta_phase=$yaml_key
			;;
		" "*)
			yaml_line=${yaml_line#"${yaml_line%%[! ]*}"} # trim leading whitespace
			case $yaml_line in
			"- "*)
				;;
			*:*)
				# Split $yaml_line into a $yaml_key, $yaml_value pair.
				yaml_keyvalue "$yaml_line"
				case $pkgmeta_phase in
				externals)
					case $yaml_key in
					url) external_uri=$yaml_value ;;
					tag)
						external_tag=$yaml_value
						external_checkout_type=$yaml_key
						;;
					branch)
						external_tag=$yaml_value
						external_checkout_type=$yaml_key
						;;
					commit)
						external_tag=$yaml_value
						external_checkout_type=$yaml_key
						;;
					type) external_type=$yaml_value ;;
					curse-slug) external_slug=$yaml_value ;;
					*)

						# Started a new external, so checkout any queued externals.
						process_external

						external_dir=$yaml_key
						if [ -n "$yaml_value" ]; then
							external_uri=$yaml_value
							# Immediately checkout this fully-specified external.
							process_external
						fi
						;;
					esac
					;;
				esac
				;;
			esac
			;;
		esac
	done < "$pkgmeta_file"
	# Reached end of file, so checkout any remaining queued externals.
	process_external

	if [ ${#external_pids[*]} -gt 0 ]; then
		echo
		echo "Waiting for externals to finish..."
		echo

		while [ ${#external_pids[*]} -gt 0 ]; do
			wait -n
			for i in ${!external_pids[*]}; do
				pid=${external_pids[i]}
				if ! kill -0 $pid 2>/dev/null; then
					_external_output="$tmpdir/.$pid.externalout"
					if ! wait $pid; then
						_external_error=1
						# wrap each line with a bright red color code
						awk '{ printf "\033[01;31m%s\033[0m\n", $0 }' "$_external_output"
						echo
					else
						start_group "$( head -n1 "$_external_output" )" "external.$pid"
						tail -n+2 "$_external_output"
						end_group "external.$pid"
					fi
					rm -f "$_external_output" 2>/dev/null
					unset 'external_pids[i]'
				fi
			done
		done

		if [ -n "$_external_error" ]; then
			echo
			echo "There was an error fetching externals :(" >&2
			exit 1
		fi

	
  
    # Get the directories stored during the background executions of checkout_external.
    . "$rendevouz"
    for i in "${!toCopy[@]}"; do
    
      local source="${toCopy[$i]}"
      local target="$1/$i/"
    
			# Check if the directory exists
			if [ ! -d "$target" ]; then
				# Create the directory if it doesn't exist
				mkdir -p "$target"
			fi
		
      cd "$target"
      if [ -d ".git" ] || [ -f ".git" ]; then
        tput setaf 9
        echo "NOT OVERRIDING WORKING COPY: $target"
        echo
        tput sgr0
        continue
      fi
      

      echo "Copy $source"
      echo "to   $target"

      # Delete old directory and create new empty one.
      rm -fr "$target"
      mkdir "$target"
      
      # To ignore the top level directory name.
      # (https://stackoverflow.com/questions/19482123/extract-part-of-a-string-using-bash-cut-split)
      topDirName="${source%/}"
      topDirName="${topDirName##*/}"
      # echo $topDirName
      
      # Needed, because otherwise we might get this error:
      # find: failed to save initial working directory: No such file or directory
      cd .
      
      # find "$source" \( -name ".*" -a ! -name "." \) -prune -o ! -name "$topDirName" -print
      find "$source" \( -name ".*" -a ! -name "." \) -prune -o ! -name "$topDirName" -print | while read -r line; do
      
        if [ -d "$line" ]; then
          mkdir "$target${line##$source}"
        else
          cp "$line" "$target${line##$source}"
        fi
      
      done
      
      echo "...done"
      echo
      
    done
    
    rm "$rendevouz"
  
  fi
  
  rm -fr "$tmpdir"
  
}




checkDir() {
  local path=$1  

  if [ -d "$path" ]; then
    cd "$path"
    
    if [ -f ".pkgmeta" ]; then
      echo "$(pwd)"
      processPkgmeta "$(pwd)"
      
      # For testing:
      # exit 1
    fi
    
    # Check subdirectories.
    for dir in */; do
      if [ -d "$path$dir" ]; then
        checkDir "$path$dir/"
      fi
    done
  else
    echo "$path not found!!"
  fi
}


# checkDir "$(cygpath -u "$1")/"
checkDir "$1/"