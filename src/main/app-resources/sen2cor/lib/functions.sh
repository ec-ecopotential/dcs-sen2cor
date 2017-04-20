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

  export SEN2COR_CONF=$SEN2COR_HOME/cfg/L2A_GIPP.xml
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

function prep_conf() {

  local aerosol_type="$( ciop-getparam aerosol_type )"
  local mid_latitude="$( ciop-getparam mid_latitude )"
  local ozone_content="$( ciop-getparam ozone_content )"
  local wv_correction="$( ciop-getparam wv_correction )"
  local vis_update_mode="$( ciop-getparam vis_update_mode )"
  local wv_watermask="$( ciop-getparam wv_watermask )"
  local cirrus_correction="$( ciop-getparam cirrus_correction )"
  local brdf_correction="$( ciop-getparam brdf_correction )"
  local brdf_lower_bound="$( ciop-getparam brdf_lower_bound )"
  local dem_unit="$( ciop-getparam dem_unit )"
  local adj_km="$( ciop-getparam adj_km )"
  local visibility="$( ciop-getparam visibility )"
  local altitude="$( ciop-getparam altitude )"
  local smooth_wv_map="$( ciop-getparam smooth_wv_map )"
  local wv_threshold_cirrus="$( ciop-getparam wv_threshold_cirrus )"

  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Look_Up_Tables/Aerosol_Type" \
    -v "${aerosol_type}" \
    ${SEN2COR_CONF}
 
  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Look_Up_Tables/Mid_Latitude" \
    -v "${mid_latitude}" \
    ${SEN2COR_CONF}

  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Look_Up_Tables/Ozone_Content" \
    -v "${ozone_content}" \
    ${SEN2COR_CONF}

  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Flags/WV_Correction" \
    -v "${wv_correction}" \
    ${SEN2COR_CONF}

  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Flags/VIS_Update_Mode" \
    -v "${vis_update_mode}" \
    ${SEN2COR_CONF}

  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Flags/WV_Watermask" \
    -v "${wv_watermask}" \
    ${SEN2COR_CONF}
    
  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Flags/Cirrus_Correction" \
    -v "${cirrus_correction}" \
    ${SEN2COR_CONF}
    
    
  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Flags/BRDF_Correction" \
    -v "${brdf_correction}" \
    ${SEN2COR_CONF}
    
  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Flags/BRDF_Lower_Bound" \
    -v "${brdf_lower_bound}" \
    ${SEN2COR_CONF}
    
  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Calibration/DEM_Unit" \
    -v "${dem_unit}" \
    ${SEN2COR_CONF}
    
  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Calibration/Adj_Km" \
    -v "${adj_km}" \
    ${SEN2COR_CONF}
    
  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Calibration/Visibility" \
    -v "${visibility}" \
    ${SEN2COR_CONF}
    
  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Calibration/Altitude" \
    -v "${altitude}" \
    ${SEN2COR_CONF}
    
  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Calibration/Smooth_WV_Map" \
    -v "${smooth_wv_map}" \
    ${SEN2COR_CONF}
    
  xmlstarlet \
    ed -L \
    -u "//Level-2A_Ground_Image_Processing_Parameter/Atmospheric_Correction/Calibration/WV_Threshold_Cirrus" \
    -v "${wv_threshold_cirrus}" \
    ${SEN2COR_CONF}

}

function process_2A() {

  local ref=$1
  local resolution=$2
  local format=$3
  local pa=$4
  local granules=$5
  local online_resource=""

  read identifier online_resource startdate enddate orbit_number wrslon < <( opensearch-client -m EOP ${ref} identifier,enclosure,startdate,enddate,orbitNumber,wrsLongitudeGrid  | tr "," " " )

  [ -z ${online_resource} ] && return ${ERR_NO_RESOLUTION}

  local_1c="$( echo "${online_resource}" | ciop-copy -O ${TMPDIR} - )"

  [ ! -d ${local_1c} ] && return ${ERR_DOWNLOAD_1C}

  cd ${local_1c}

  # check if dem is needed
  local dem
  [ "$( ciop-getparam dem )" == "Yes" ] && {

    ciop-log "INFO" "A DEM will be used"  
    # set dem path in ${SEN2COR_CONF}
    SEN2COR_DEM=${local_1c}/DEM
    mkdir -p ${SEN2COR_DEM}
    
    # xmlstartlet
     xmlstarlet ed -L -u \
       "//Level-2A_Ground_Image_Processing_Parameter/Common_Section/DEM_Directory" \
       -v "${SEN2COR_DEM}" \
       ${SEN2COR_CONF} 
  }

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

    ciop-log "INFO" "Conversion to GeoTiff"    

    convert ${local_1c}/${identifier}.SAFE ${local_1c}/${level_2a}.SAFE ${format} ${proj_win}

  } || {

    ciop-log "INFO" "Compression Level 2A in SAFE format"

    tar cfz ${TMPDIR}/${level_2a}.tgz -C ${TMPDIR} "${level_2a}.SAFE" 1>&2 || return ${ERR_COMPRESSION}
    echo ${TMPDIR}/${level_2a}.tgz

  }

}

function get_projwin() {

  local pa="$1"
  local win

  win="$( cat ${_CIOP_APPLICATION_PATH}/etc/pa.projwin | grep "${pa}" | cut -d "," -f 2- )"

  [ -z "${win}" ] && return ${ERR_PROJWIN}

  echo "${win}"

}

function get_short_pa() {

  local pa="$1"
  local short_pa

  short_pa="$( cat ${_CIOP_APPLICATION_PATH}/etc/pa.bbox | grep "${pa}" | cut -d "," -f 1 )"

  [ -z "${short_pa}" ] && return ${ERR_NO_PA}

  echo "${short_pa}"

}

function main() {

  sen2cor_env
  setGDALEnv

  local resolution="$( ciop-getparam resolution)"
  local format="$( ciop-getparam format )"
  local pa="$( ciop-getparam pa )"
  local dem
  
  # create sen2cor generic configuration 
  prep_conf

  local short_pa="$( get_short_pa ${pa} )"

  while read input
  do
    ciop-log "INFO" "Processing ${input}"

    ref="$( echo ${input} | cut -d "," -f 1)"

    read identifier online_resource startdate enddate orbit_number wrslon < <( opensearch-client -m EOP ${ref} identifier,enclosure,startdate,enddate,orbitNumber,wrsLongitudeGrid  | tr "," " " )

    granules="$( echo $input | cut -d "," -f 2- | tr "," "|")"

    [ "${ref}" == ${granules} ] && granules=""

    ciop-log "INFO" "Processsing $( echo ${granules} | tr "|" "\n" | wc -l ) tiles of Sentinel-2 product ${identifier}"

    results="$( process_2A ${ref} ${resolution} ${format} "${short_pa}" ${granules} || return $? )"
    res=$?

    [ "${res}" != "0"  ] && return ${res}   

    for result in $( echo ${results} | tr " " "\n" | grep -v png )
    do
      mission=$( echo ${identifier} | cut -c 1-3 )
      tile=$( basename ${result} | cut -d "_" -f 2 )
      acq_time=$( basename ${result} | cut -d "_" -f 3 )
      creaf_tail=$( basename ${result} | cut -d "_" -f 3- )
      creaf_name=${mission}_MSIL2A_${tile}_${short_pa}_${creaf_tail}

      creaf_dir=${TMPDIR}/${mission}_MSIL2A_${tile}_${short_pa}_${acq_time}
      ciop-log "DEBUG" "creaf dir ${creaf_dir}"
      mkdir -p ${creaf_dir}

      echo ${creaf_dir} >> ${TMPDIR}/results

      ciop-log "DEBUG" "creaf name: ${creaf_name}"
      mv ${result} ${creaf_dir}/${creaf_name}
      result=${creaf_dir}/${creaf_name}

      # update metadata
      target_xml=${result}_eop.xml
      target_xml_md=${result}.xml
      cp /application/sen2cor/etc/eop-template.xml ${target_xml}
      cp /application/sen2cor/etc/md-template.xml ${target_xml_md}

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

   done
 
    # compress and publish
    cd ${TMPDIR}
    for res_dir in $( cat ${TMPDIR}/results | sort -u )
    do
      # copy sen2cor configuration
      cp ${SEN2COR_CONF} ${res_dir}/$( basename ${res_dir} )_L2A_GIPP.xml

      ciop-log "INFO" "Compress ${res_dir}"
      tar -czf ${res_dir}.tgz -C ${TMPDIR} $( basename ${res_dir} ) 
      ciop-log "INFO" "Publish ${res_dir}.tgz"
      ciop-publish -m ${res_dir}.tgz || return ${ERR_PUBLISH}
      
      rm -fr ${res_dir} ${res_dir}.tgz

    done
   
    rm -f ${TMPDIR}/results 
    rm -fr ${TMPDIR}/${identifier}

    tree ${TMPDIR}   

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

