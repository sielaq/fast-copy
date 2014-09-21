#!/bin/bash
# Fast Copy 
# using pigz and parallel copy

PORT=2222
C=0
declare -a DEST
SSH="ssh -q -o StrictHostKeyChecking=no -o TCPKeepAlive=yes "
NC="/bin/nc.traditional"
CHKSUM="md5sum"
VERIFY=1
COPY=0

RED="\033[31m"
GRN="\033[32m"
YEL="\033[33m"
END="\033[0m"

if [ ! -t 1 ]; then
 RED="";GRN="";YEL="";END=""
fi

OK="[ OK ]"
NOK="[NOK ]"
OK="$GRN$OK$END"
NOK="$RED$NOK$END"


display_help(){
 echo "$(basename $0) is a really fast cascade copy between multiple hosts, using streams (fifo and pipes)"
 echo "restrictions: host cannot be repeated, destinatin directory must be empty"
 echo "usage: -s|--source HOST_0:/path"
 echo "       -d|--destination HOST_1:/path [HOST_2:/path]...[HOST_N:/path]"
 echo "       -p|--port 2222            default is 2222"
 echo "       -v|--verify               verify if sum controls match on all hosts"
 echo "       -o|--only_verify          only verify without copying" 
 echo "ex.: $(basename $0) -s dbmaster:/var/lib/mysql/data -d dblag:/var/lib/mysql/data db:/var/lib/mysql/data"
}

[ $# -eq 0 ] && display_help && exit 0

while :
do
  case "$1" in
    -d | --dst|--destination)
        shift
        while [ "${1+defined}" ] && [[ "${1}" != "-"* ]]; do
          DEST[$C]=$1
          C=$(($C+1))
          shift
        done
        ;;
    -s | --src|--source)
        shift
        HOST_SRC=${1%:*}
        DIR_SRC=${1#*:}
        shift
        ;;
    -h | --help)
        display_help
        exit 0
        ;;
    -p | --port)
        shift
        PORT=$1
        ;;
    -v | --verify)
        shift
        VERIFY=0
        ;;
    -o | --only_verify)
        shift
        VERIFY=0
        COPY=1
        ;;
    --) # End of all options
        shift
        break
        ;;
    -*)
        echo "Error: Unknown option: $1" >&2
        exit 1
        ;;
    *)  # No more options
        break
        ;;
  esac
done

app_check() {
 echo $1 | grep -q $2 && echo -e "${OK} $2 \tinstalled" || { echo -e "$NOK $2 \tnot installed" && return 1; }
}

check() {
  local host=$1
  local dir=$2
  local exit=0
  echo "${host}:"
  local apps=$($SSH ${host} "which pigz;which nc;which tar;which screen;ls -A ${dir} 2>/dev/null|wc -l")
  local count_dir=$(echo "${apps}" | tail -n1)
  app_check "${apps}" pigz  || exit=1
  app_check "${apps}" nc    || exit=1
  app_check "${apps}" tar   || exit=1
  app_check "${apps}" screen|| exit=1
  [ ! -z ${dir} ] && {
    [ "$count_dir" -eq 0 ] && echo -e "$OK destination dir ${dir} is empty" || {
      echo -e "${NOK} destination dir ${dir} not empty"; exit=1;
    }
  }
  return ${exit}
}

check_sum() {
  $SSH $1 "sudo sh -c \"cd $2;find . -type f -print0| xargs -0 -n1 -P4 $CHKSUM|sort -dk2|$CHKSUM\""
}

[ ${COPY} -eq 0 ] && {

  #1. check each host if contains needed apps
  EXIT=0
  echo "Checking all hosts for required tools..."
  check $HOST_SRC || EXIT=1
  for i in ${DEST[@]}
  do
    HOST=${i%:*}
    DIR=${i#*:}
    check $HOST $DIR || EXIT=1
  done
  [ ${EXIT} -eq 1 ] && exit 1
  
  # 2. Install on last host screen with netcat
  echo "Setting up last host..."
  HOST_LAST=${DEST[$C-1]%:*}
  DIR_LAST=${DEST[$C-1]#*:}
  $SSH -f $HOST_LAST "sudo screen -S fcp.$$.C -dm sh -c \"[ -d ${DIR_LAST} ] || mkdir -p ${DIR_LAST};${NC} -l -p ${PORT} -q 0 | pigz -d| tar xvf - -C ${DIR_LAST}\""
  
  # 3. For all hosts in between first and last, install pipe splitter
  echo "Setting up splitter..."
  ELEM_LAST=""
  [ ${#DEST[@]} -gt 1 ] && {
    for i in "${DEST[@]}"
    do
      [ ! -z $ELEM_LAST ] && {
        HOST_NEXT=${i%:*}
        HOST=${ELEM_LAST%:*}
        DIR=${ELEM_LAST#*:}
        echo "$HOST - setting up fifo and splitter"
        $SSH -f $HOST "sudo screen -S fcp.$$.A -dm sh -c \"mkfifo /tmp/myfifo; ${NC} -q 0 ${HOST_NEXT} ${PORT} </tmp/myfifo ; sleep 1d \""
        $SSH -f $HOST "sudo screen -S fcp.$$.B -dm sh -c \"[ -d ${DIR} ] || mkdir -p ${DIR};${NC} -l -p ${PORT} -q 0|tee /tmp/myfifo|pigz -d|tar xvf - -C ${DIR}\""
      }
      ELEM_LAST=$i
    done
  }
  
  # 4. Start copy
  HOST_FIRST=${DEST[0]%:*}
  echo "Start copying..."
  $SSH $HOST_SRC "sudo sh -c \"tar cv -C ${DIR_SRC} .| pigz | ${NC} -q 0 ${HOST_FIRST} ${PORT}\" " || {
    echo "Copy error"
    exit 1
  }
  
  # 5. Clean up - remove fifo(s) and screen(s)
  echo "Clean up..."
  for i in "${DEST[@]}"
  do
    HOST=${i%:*}
    $SSH -f $HOST "sudo rm /tmp/myfifo >/dev/null 2>&1;sudo screen -X -S fcp.$$ quit >/dev/null 2>&1"
  done
}

#6. Verify
[ ${VERIFY} -eq 0 ] && {
  echo "Calculating sum controls, please wait..."
  check_sum ${HOST_SRC} ${DIR_SRC} > /tmp/$$.$HOST_SRC &
  for i in "${DEST[@]}"
  do
    HOST=${i%:*}
    DIR=${i#*:}
    check_sum ${HOST} ${DIR} > /tmp/$$.$HOST &
  done
  wait
  
  SRC_SUM=$(cat /tmp/$$.$HOST_SRC)
  echo -e "${HOST_SRC}: \t${SRC_SUM}"
  for i in "${DEST[@]}"
  do
    HOST=${i%:*}
    HOST_SUM=$(cat /tmp/$$.${HOST})
    echo -e "${HOST}: \t${HOST_SUM}"
    [ "$SRC_SUM" = "$HOST_SUM" ] && echo -e "$OK all $CHKSUM from $DIR are identical like on ${HOST_SRC}:${DIR_SRC}" || {
      echo -e "$NOK some $CHKSUM from $DIR are different than ${HOST_SRC}:${DIR_SRC}"
    }
  done
  
  rm /tmp/$$.*
}

exit 0
