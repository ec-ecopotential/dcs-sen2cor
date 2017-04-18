
set -x

SUCCESS=0
ERR_CAT_REF=2
ERR_NO_TILES=4
ERR_PUBLISH_S=6

function cleanExit ()
{
  local retval=$?
  local msg=""
  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_CAT_REF}) msg="Failed to query Level 1C product";;
    ${ERR_NO_TILES}) msg="Failed to discover tiles";;
    ${ERR_PUBLISH_S}) msg="Failed to publish product reference and tile identifiers";;
    *) msg="Unknown error";;
  esac

  # clean up working space
  rm -fr ${TMPDIR}

  [ "${retval}" != "0" ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  exit ${retval}
}

function product2tiles () {

  local identifier=""
  local self=""
  local startdate=""
  local enddate=""
  local tiles=""

  local ref="$1"

  read identifier self startdate enddate < <( opensearch-client "${ref}" identifier,self,startdate,enddate | tr "," " " )

  [ -z ${identifier} ] || [ -z ${startdate} ] || [ -z ${enddate} ] && return ${ERR_CAT_REF}

  # check if product is before 06/12/2016

#  [ "true" == "true" ] && {

    # pre-06/12/2016
    tiles="$( opensearch-client \
      -p "pt=S2MSI1CT" \
      -p "pi=${identifier}" \
      -p "bbox=${bbox}" \
      -p "start=${startdate}" \
      -p "stop=${enddate}" \
      https://catalog.terradue.com/sentinel2/search identifier | tr "\n" ","  | rev | cut -c 2- | rev )"

    [ -z ${tiles} ] && {
      # it's a single tile product
      ciop-log "INFO" "Got single tile product"
      echo "${self}" | ciop-publish -s || return ${ERR_PUBLISH_S}

    } || {

      ciop-log "INFO" "Identified $( echo ${tiles} | tr "," "\n" | wc -l ) tiles in ${identifier}"

      echo "${self},${tiles}" | ciop-publish -s || return ${ERR_PUBLISH_S}

    }
}

function pa2bbox() {

  local pa="$1"

  bbox="$( cat ${_CIOP_APPLICATION_PATH}/etc/pa.bbox | grep "${pa}" | cut -d "," -f 2- )"

  [ -z "${bbox}" ] && return ${ERR_NO_BBOX}

  echo "${bbox}"

}


function main () {

  local catalogue_url="$( cat )"
  local startdate="$( ciop-getparam startdate )"
  local enddate="$( ciop-getparam enddate )"
  local pa="$( ciop-getparam pa )" 

  local bbox

  # TODO check error han
  bbox="$( pa2bbox "${pa}" || return $? )"

  # report activity in log
  ciop-log "INFO" "Processing ${pa}"

  opensearch-client \
    -p "pt=S2MSI1C" \
    -p "bbox=${bbox}" \
    -p "start=${startdate}" \
    -p "stop=${enddate}" \
    ${catalogue_url} | while read ref
  do
    ciop-log "INFO" "reference: ${ref}"

    product2tiles "${ref}" || return $?

  done

}
