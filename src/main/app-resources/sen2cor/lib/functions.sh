set -x
# define the exit codes
SUCCESS=0
ERR_NO_RESOLUTION=5
ERR_DOWNLOAD_1C=10
ERR_GRANULE_DIR=15
ERR_SEN2COR=20
ERR_LEVEL_2A_DIR=25
ERR_COMPRESSION=30
ERR_PUBLISH=35

# add a trap to exit gracefully
function cleanExit ()
{
  local retval=$?
  local msg=""
  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_NO_RESOLUTION}) msg="No target resolution provided, must be one of 10, 20 or 60";;
    ${ERR_DOWNLOAD_1C}) msg="Failed to retrieve Sentinel-2 Level 1C product";;
    ${ERR_GRANULE_DIR}) msg="Couldn't find the Sentinel-2 Level 1C product granule directory";;
    ${ERR_SEN2COR}) msg="SEN2COR main binary L2A_Process failed";;
    ${ERR_LEVEL_2A_DIR}) msg="Couldn't find the Sentinel-2 Level 2A product";;
    ${ERR_COMPRESSION}) msg="Failed to compress the Sentinel-2 Level 2A product";;
    ${ERR_PUBLISH}) msg="Failed to publish the Sentinel-2 Level 2A product";;
    *) msg="Unknown error";;
  esac

  [ "${retval}" != "0" ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  exit ${retval}
}

function setGDALEnv() {
  # setup GDAL environment
  export GDAL_HOME=$( find /opt/anaconda/pkgs/ -name "gdal-2.1.3-py27_?" )
  export PATH=$GDAL_HOME/bin/:$PATH
  export LD_LIBRARY_PATH=$GDAL_HOME/lib/:/opt/anaconda/pkgs/geos-3.4.2-0/lib:/opt/anaconda/lib:$LD_LIBRARY_PATH
  export GDAL_DATA=$GDAL_HOME/share/gdal
}

function sen2cor_env() {

  # setup SEN2COR environment
  export SEN2COR_BIN=/opt/anaconda/lib/python2.7/site-packages/sen2cor
  export PATH=/opt/anaconda/bin/:$PATH
  export SEN2COR_HOME=$TMPDIR/sen2cor/

  mkdir -p $TMPDIR/sen2cor/cfg
  cp $SEN2COR_BIN/cfg/L2A_GIPP.xml $SEN2COR_HOME/cfg
  cp $SEN2COR_BIN/cfg/L2A_CAL_AC_GIPP.xml $SEN2COR_HOME/cfg/
  cp $SEN2COR_BIN/cfg/L2A_CAL_SC_GIPP.xml $SEN2COR_HOME/cfg/

}

function convert() {

  local l1c=$1
  local l2a=$2
  local format=$3
  local proj_win=$4

  # get source proj for all three possible resolutions
  source_res10m=$( find ${l1c} -name "*B02.jp2" )
  source_res20m=$( find ${l1c} -name "*B05.jp2" )
  source_res60m=$( find ${l1c} -name "*B01.jp2" )

  for res in 10 20 60
  do
    tmp_res=source_res${res}m
    source_res=${!tmp_res}
    for band in $( find ${l2a} -name "*${res}m.jp2" )
    do
      tif_name=$( echo ${band} | sed 's/jp2/tif/' )
      ${_CIOP_APPLICATION_PATH}/sen2cor/bin/gdalcopyproj.py \
      ${source_res} \
      ${band}
  
     # TODO add compression -co COMPRESS=LZW
      #gdal_translate -of GTiff -epo -projwin $( echo ${proj_win} | tr "," " " ) ${band} ${TMPDIR}/${tif_name} 
      gdal_translate \
        -of GTiff \
        ${band} \
        ${tif_name} 1>&2    

      echo ${tif_name}

    done
  done

}

function preview() {

  local l2a=$1

  for band in $( find ${l2a} -name "*$m.jp2" )
  do
    preview_name=$( echo ${band} | sed 's/jp2/png/' )
    gdal_translate \
      -of PNG \
      ${band} \
      ${preview_name} 1>&2 || return ${ERR_GDAL_TRANSLATE}

    echo ${preview_name} 

  done
}

function process_2A() {

  local ref=$1
  local resolution=$2
  local format=$3
  local proj_win=$4
  local granules=$5
  local online_resource=""


  read identifier online_resource startdate enddate orbit_number wrslon < <( opensearch-client -m EOP ${ref} identifier,enclosure,startdate,enddate,orbitNumber,wrsLongitudeGrid  | tr "," " " )

  [ -z ${online_resource} ] && return ${ERR_NO_RESOLUTION}

  local_s2="$( echo "${online_resource}" | ciop-copy -O ${TMPDIR} - )"
  

  [ ! -d ${local_s2} ] && return ${ERR_DOWNLOAD_1C}

  cd ${local_s2}

  granule_path=${identifier}.SAFE/GRANULE

  [ ! -d ${granule_path} ] && return ${ERR_GRANULE_DIR}

  [ ! -z "${granules}" ] && {
    ls ${granule_path} | grep -Ev ${granules} | while read dead_granule
    do
      ciop-log "INFO" "Excluding granule ${dead_granule}"
      rm -fr ${granule_path}/${dead_granule}
    done
  }

  ciop-log "INFO" "Invoke SEN2COR L2A_Process"
  L2A_Process --resolution ${resolution} ${identifier}.SAFE 1>&2 # || return ${ERR_SEN2COR}

  level_2a="$( echo ${identifier} | sed 's/OPER/USER/' | sed 's/MSIL1C/MSIL2A/' )"

  [ ! -d ${level_2a}.SAFE ] && return ${ERR_LEVEL_2A_DIR}

  [ "${format}" == "GeoTiff" ] && {

    convert ${local_s2}/${identifier}.SAFE ${local_s2}/${level_2a}.SAFE ${format} ${proj_win}

  #  cd ${level_2a}.SAFE
 
  #  metadata="$( find . -maxdepth 1 -name "*MTD*.xml" )"
  #  counter=0
  #  gdalinfo ${metadata} 2> /dev/null | grep -E  "SUBDATASET_._NAME" \
  #   | grep -v "PREVIEW" |  cut -d "=" -f 2 | while read subset
  #  do
  #    ciop-log "INFO" "Process ${subset}"
  #    gdal_translate \
  #      ${subset} \
  #      ${TMPDIR}/${level_2a}_${counter}.TIF 1>&2 || return ${ERR_GDAL_TRANSLATE}
  #
  #    echo ${TMPDIR}/${level_2a}_${counter}.TIF #.gz
  # done

  } || {

    ciop-log "INFO" "Compression Level 2A in SAFE format"

    tar cfz ${TMPDIR}/${level_2a}.tgz "${level_2a}.SAFE" 1>&2 || return ${ERR_COMPRESSION}
    echo ${TMPDIR}/${level_2a}.tgz

  }

#  preview ${local_s2}/${level_2a}.SAFE 
 
  # Preview
  #cd ${level_2a}.SAFE

  #  metadata="$( find . -maxdepth 1 -name "*MTD*.xml" )"
  #  counter=0
  #  gdalinfo ${metadata} 2> /dev/null | grep -E  "SUBDATASET_._NAME" \
  #   | grep "PREVIEW" |  cut -d "=" -f 2 | while read subset
  #  do
  #    ciop-log "INFO" "Process ${subset}"
  #    gdal_translate \
  #      -of PNG \
  #      ${subset} \
  #      ${TMPDIR}/${level_2a}_${counter}.png 1>&2 || return ${ERR_GDAL_TRANSLATE}
  #
  #    echo ${TMPDIR}/${level_2a}_${counter}.png
  # done

}

function get_projwin() {

  local pa="$1"
  local win

  win="$( cat ${_CIOP_APPLICATION_PATH}/etc/pa.projwin | grep "${pa}" | cut -d "," -f 2- )"

  [ -z "${win}" ] && return ${ERR_PROJWIN}

  echo "${win}"

}


function main() {

  sen2cor_env
  setGDALEnv

  local resolution="$( ciop-getparam resolution)"
  local format="$( ciop-getparam format )"
  local pa="$( ciop-getparam pa )"

  local short_pa=CM

  local proj_win

  proj_win="$( get_projwin ${pa} )"

  [ -z "${proj_win}" ] && return ${ERR_PROJWIN}

  while read input
  do
    ciop-log "INFO" "Processing ${input}"

    ref="$( echo ${input} | cut -d "," -f 1)"

    read identifier online_resource startdate enddate orbit_number wrslon < <( opensearch-client -m EOP ${ref} identifier,enclosure,startdate,enddate,orbitNumber,wrsLongitudeGrid  | tr "," " " )

    granules="$( echo $input | cut -d "," -f 2- | tr "," "|")"

    [ "${ref}" == ${granules} ] && granules=""

    ciop-log "INFO" "Processsing $( echo ${granules} | tr "|" "\n" | wc -l ) tiles of Sentinel-2 product ${identifier}"

    results="$( process_2A ${ref} ${resolution} ${format} "${proj_win}" ${granules} || return $? )"
    res=$?

    [ "${res}" != "0"  ] && return ${res}   

    for result in $( echo ${results} | tr " " "\n" | grep -v png )
    do
      mission=$( echo ${identifier} | cut -c 1-3 )
      tile=$( basename ${result} | cut -d "_" -f 2 )
      acq_time=$( basename ${result} | cut -d "_" -f 3 )
      creaf_tail=$( basename ${result} | cut -d "_" -f 3- )
      creaf_name=$(dirname ${result} )/${mission}_MSIL2A_${tile}_${short_pa}_${creaf_tail}
 
      creaf_dir=${TMPDIR}/${mission}_MSIL2A_${tile}_${short_pa}_${acq_time}
      ciop-log "DEBUG" "creaf dir ${creaf_dir}"
      mkdir -p ${creaf_dir}

      ciop-log "DEBUG" "creaf name: ${creaf_name}"
      mv ${result} ${creaf_dir}/${creaf_name}
      result=${creaf_dir}/${creaf_name}

      # update metadata
      cp /application/sen2cor/etc/eop-template.xml ${result}.xml
      target_xml=${result}.xml

      # set identifier
      metadata \
        "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:identifier" \
        "$( basename "${result}" )" \
        ${target_xml}

      # set product type
      metadata \
        "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:productType" \
        "S2A_L2A_PROTO" \
        ${target_xml}

      # set processor name
      metadata \
        "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:processing/D:ProcessingInformation/D:processorName" \
        "dcs-sen2cor" \
        ${target_xml}

      metadata \
        "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:processing/D:ProcessingInformation/D:processorVersion" \
        "1.0" \
        ${target_xml}

      # set processor name
      metadata \
        "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:processing/D:ProcessingInformation/D:nativeProductFormat" \
        "${format}" \
        ${target_xml}


      # set processor name
      metadata \
        "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:processing/D:ProcessingInformation/D:processingCenter" \
        "Terradue Cloud Platform" \
        ${target_xml}

      # set startdate
      metadata \
        "//A:EarthObservation/B:phenomenonTime/C:TimePeriod/C:beginPosition" \
        "${startdate}" \
        ${target_xml}

      # set stopdate
      metadata \
        "//A:EarthObservation/B:phenomenonTime/C:TimePeriod/C:endPosition" \
        "${enddate}" \
        ${target_xml}

      # set orbit direction
      metadata \
        "//A:EarthObservation/B:procedure/D:EarthObservationEquipment/D:acquisitionParameters/D:Acquisition/D:orbitDirection" \
        "DESCENDING" \
        ${target_xml}

      # set wrsLongitudeGrid
      metadata \
        "//A:EarthObservation/B:procedure/D:EarthObservationEquipment/D:acquisitionParameters/D:Acquisition/D:wrsLongitudeGrid" \
        "${wrslon}" \
        ${target_xml}

      # set orbitnumber
      metadata \
        "//A:EarthObservation/B:procedure/D:EarthObservationEquipment/D:acquisitionParameters/D:Acquisition/D:orbitNumber" \
        "${orbit_number}" \
        ${target_xml}

      ciop-publish -m ${result} || return ${ERR_PUBLISH}
      ciop-publish -m ${result}.xml || return ${ERR_PUBLISH}
    done
  
 #   for result in $( echo ${results} | tr " " "\n" | grep png )
#    do
#      ciop-publish -m ${result} || return ${ERR_PUBLISH}
#    done
    rm -fr ${creaf_dir}
    rm -fr S2*
  done

}

function metadata() {

  local xpath="$1"
  local value="$2"
  local target_xml="$3"
 
  xmlstarlet ed -L \
    -N A="http://www.opengis.net/opt/2.1" \
    -N B="http://www.opengis.net/om/2.0" \
    -N C="http://www.opengis.net/gml/3.2" \
    -N D="http://www.opengis.net/eop/2.1" \
    -u  "${xpath}" \
    -v "${value}" \
    ${target_xml}
 
}

