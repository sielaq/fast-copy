# Fast Copy
# using pigz and parallel copy

PORT=2222
C=0
declare -a DEST
SSH="ssh -q -o StrictHostKeyChecking=no -o TCPKeepAlive=yes "
NC="/bin/nc.traditional"
CHKSUM="md5sum"

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
 echo "$(basename $0) is a really fast copy between multiple hosts, using streams (fifo and pipes)"
 echo "usage: -s|--source HOST:/path"
 echo "       -d|--destination HOST_A:/pash [HOST_B:/path]...[HOST_N:/path]"
 echo "       -p|--port 2222 (default 2222)"
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
	HOST_SRC=$(echo $1|awk -F\: '{print $1}')
	DIR_SRC=$(echo $1|awk -F\: '{print $2}')
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
  EXIT=0
  echo "$1:"
  APPS=$($SSH $1 "which pigz;which nc;which tar;which screen;ls -A $2|wc -l")
  COUNT_DIR=$(echo "${APPS}" | tail -n1)
  app_check "${APPS}" pigz  || EXIT=1
  app_check "${APPS}" nc    || EXIT=1
  app_check "${APPS}" tar   || EXIT=1
  app_check "${APPS}" screen|| EXIT=1
  [ ! -z $2 ] && {
    [ "$COUNT_DIR" -eq 0 ] && echo -e "$OK destination dir $2 is empty" || {
      echo -e "${NOK} destination dir $2 not empty"; EXIT=1;
    }
  }
  return $EXIT
}

check_sum() {
  $SSH $1 "sudo bash -c \"cd $2;find . -type f | xargs -n1 -P4 $CHKSUM|sort -dk2|$CHKSUM\""
}

#1. check each host if contains needed apps
EXIT=0
check $HOST_SRC || EXIT=1
for i in ${DEST[@]} 
do
  HOST=$(echo $i|awk -F\: '{print $1}')
  DIR=$(echo $i|awk -F\: '{print $2}')
  check $HOST $DIR || EXIT=1
done
[ $EXIT -eq 1 ] && exit 1

echo "Start copying..."

# 2. Install on last host screen ith netcat
HOST_FIRST=$(echo ${DEST[0]}|awk -F\: '{print $1}')
HOST_LAST=$(echo ${DEST[$C-1]}|awk -F\: '{print $1}')
DIR_LAST=$(echo ${DEST[$C-1]}|awk -F\: '{print $2}')
$SSH -f $HOST_LAST "sudo screen -S fcp.$$.C -dm sh -c \"[ -d ${DIR_LAST} ] || mkdir -p ${DIR_LAST};${NC} -l -p ${PORT} -q 0 | pigz -d| tar xvf - -C ${DIR_LAST}\""

# 3. For all hosts in between first and last, install pipe splitter 
ELEM_LAST=""
if [ ${#DEST[@]} -gt 1 ]
then
  for i in "${DEST[@]}"
  do
    [ ! -z $ELEM_LAST ] && {
      HOST_NEXT=$(echo $i|awk -F\: '{print $1}')
      HOST=$(echo ${ELEM_LAST}|awk -F\: '{print $1}')
      DIR=$(echo ${ELEM_LAST}|awk -F\: '{print $2}')
      echo "$HOST - setting up fifo and splitter" 
      $SSH -f $HOST "sudo screen -S fcp.$$.A -dm sh -c \"mkfifo /tmp/myfifo; ${NC} -q 0 ${HOST_NEXT} ${PORT} </tmp/myfifo ; sleep 1d \""
      $SSH -f $HOST "sudo screen -S fcp.$$.B -dm sh -c \"[ -d ${DIR} ] || mkdir -p ${DIR};${NC} -l -p ${PORT} -q 0|tee /tmp/myfifo|pigz -d|tar xvf - -C ${DIR}\"" 
    }
    ELEM_LAST=$i
  done
fi

# 4. Start copy
$SSH $HOST_SRC "sudo bash -c \"tar cv -C ${DIR_SRC} .| pigz | ${NC} -q 0 ${HOST_FIRST} ${PORT}\" " || {
  echo "Copy error"
  exit 1
}

# 5. Clean up
echo "Cleanup - remove fifo(s) and screen(s)"
for i in "${DEST[@]}"
do
  HOST=$(echo $i|awk -F\: '{print $1}')
  $SSH -f $HOST "sudo rm /tmp/myfifo >/dev/null 2>&1;sudo screen -X -S fcp.$$ quit >/dev/null 2>&1" 
done

#6. Verify

check_sum ${HOST_SRC} ${DIR_SRC} > /tmp/$$.$HOST_SRC &
for i in "${DEST[@]}"
do
  HOST=$(echo $i|awk -F\: '{print $1}')
  DIR=$(echo $i|awk -F\: '{print $2}')
  check_sum ${HOST} ${DIR} > /tmp/$$.$HOST &
  echo "in loop"
done

echo wait
wait

SRC_SUM=$(cat /tmp/$$.$HOST_SRC)
echo -e "${HOST_SRC}: \t${SRC_SUM}"
for i in "${DEST[@]}"
do
  HOST=$(echo $i|awk -F\: '{print $1}')
  HOST_SUM=$(cat /tmp/$$.$HOST)
  echo -e "${HOST}: \t${HOST_SUM}"
  [ "$SRC_SUM" = "$HOST_SUM" ] && echo -e "$OK all $CHKSUM from $DIR are identical like on ${HOST_SRC}:${DIR_SRC}" || {
    echo -e "$NOK some $CHKSUM from $DIR are different than ${HOST_SRC}:${DIR_SRC}"
  }
done

rm /tmp/$$.*
exit 0
