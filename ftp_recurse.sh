ftp_recurse() {
  # default values - may have been exported already
  [[ "$simulate" ]]      || local simulate=0
  [[ "$verbose" ]]       || local verbose=0
  [[ "$source_prefix" ]] || local source_prefix=/
  [[ "$target_prefix" ]] || local target_prefix="$(pwd)/"
  [[ "$err_log" ]]       || local err_log="$(pwd)/err_log"

  # parse args
  while (( ${#@} ))
  do
    case $1 in
      # setting modes
      (-s|--simulate)     simulate=1;       shift ;;
      (-v|--verbose)      verbose=1;        shift ;;
      (-l|--local-owner)  local_owner="$2"; shift 2 ;;
      (--did-su)          local_owner="";   shift ;;
      # gathering creds
      (-u) ftp_user="$2"; shift 2 ;;
      (-p) ftp_pass="$2"; shift 2 ;;
      (-h) ftp_host="$2"; shift 2 ;;
      # setting source and target directories to clone
      (-s_pref)
        source_prefix="$2";
        [[ "$source_prefix" == */ ]] || source_prefix+="/"
        shift 2
        ;;
      (-t_pref)
        target_prefix="$2"
        [[ "$target_prefix" == */ ]] || target_prefix+="/"
        shift 2
        ;;
      (*) local sync_path="$1" ; shift ;;
    esac
  done

  # ensure we have credentials
  [[ "$ftp_user" || "$ftp_pass" || "$ftp_host" ]] || return

  # make these things available to recursive calls
  export source_prefix target_prefix ${!ftp_*} verbose simulate
  export -f ftp_recurse

  # check if the user set a local owner to transfer files
  if [[ "$local_owner" ]]
  then
    # if we're not already running as root, warn the user
    # they're about to have to log in
    if ((UID))
    then
      echo "switching to $local_owner now"
    fi
    export prompt=$"\e[96mas $local_owner\e[0m "
    su $local_owner -p -s /bin/bash -c "ftp_recurse --did-su"
    return
  fi

  if (( simulate ))
  then
    echo -e "${prompt}\e[97mpretending to populate \e[92m$target_prefix$sync_path\e[97m from \e[93m$source_prefix$sync_path\e[0m"
  else
    echo -e "${prompt}\e[97mpopulating \e[92m$target_prefix$sync_path\e[97m from \e[93m$source_prefix$sync_path\e[0m"
    mkdir -p "$target_prefix$sync_path"
    pushd "$target_prefix$sync_path" &>/dev/null
  fi

  {
    echo "quote USER $ftp_user"
    echo "quote PASS $ftp_pass"
    echo "cd \"$source_prefix$sync_path\""
    echo "ls -lA"
    echo "quit"
  } | ftp -n "$ftp_host" | while read perm c o g s t1 t2 t3 file
  do
    if [[ "$perm" == -* ]]
    then
      if (( simulate ))
      then
        echo -e "${prompt}\e[97mpretending to get: \e[93m$sync_path$file\e[0m"
      else
        {
          echo "quote USER $ftp_user"
          echo "quote PASS $ftp_pass"
          echo "cd \"$source_prefix$sync_path\""
          echo "get \"$file\""
          echo "quit"
        } | ftp -n "$ftp_host"
        if [[ -e "$target_prefix$sync_path$file" ]]
        then
          echo -e "${prompt}\e[97mgot: \e[92m$target_prefix$sync_path$file\e[0m"
        else
          echo -e "${prompt}\e[91;1merr: \e[92m$target_prefix$sync_path$file\e[0m" | tee -a $err_log
        fi
      fi
    elif [[ "$perm" == d* ]]
    then # it's a directory
      if [[ ! "$file" == '.' && ! "$file" == '..' ]]
      then # it's not the present or parent directory
        ftp_recurse "$sync_path$file/" || return $?
      fi
    fi
  done
  (( simulate )) || popd &> /dev/null
}
