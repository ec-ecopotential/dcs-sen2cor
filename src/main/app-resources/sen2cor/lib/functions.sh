#set -x
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
      ciop-log "INFO" "PROJ ${proj_win}"
      gdal_translate -of GTiff -projwin $( echo ${proj_win} | tr "," " " ) ${band} ${tif_name} 1>&2 
      #gdal_translate \
      #  -of GTiff \
      #  ${band} \
      #  ${tif_name} 1>&2    

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

    proj_win=$(get_projwin ${pa})

    ciop-log "INFO" "Conversion to GeoTiff using proj_win ${proj_win}"    

    convert ${local_1c}/${identifier}.SAFE ${local_1c}/${level_2a}.SAFE ${format} ${proj_win}

  } || {

    ciop-log "INFO" "Compression Level 2A in SAFE format  ${format}"

    tar cfz ${TMPDIR}/${level_2a}.tgz -C ${TMPDIR} "${level_2a}.SAFE" 1>&2 || return ${ERR_COMPRESSION}
    echo ${TMPDIR}/${level_2a}.tgz

  }

}

function get_projwin() {

  local pa="$1"
  local win

  ciop-log "INFO" "PA: ${pa}"
#  win="$( cat ${_CIOP_APPLICATION_PATH}/etc/pa.projwin | grep "${pa}" | cut -d "," -f 2- )"

  #Changing y coord to make it compatible with gdal_translate ulx uly lrx lry

  IFS=, read ulx lry lrx uly <<< "$( cat ${_CIOP_APPLICATION_PATH}/etc/pa.projwin | grep "${pa}" | cut -d "," -f 2- )"

  win="${ulx},${uly},${lrx},${lry}"

  ciop-log "INFO" "win: ${win}"

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
    ciop-log "INFO" "Processing input ${input}"

    ref="$( echo ${input} | cut -d "," -f 1)"

    read identifier online_resource startdate enddate orbit_number wrslon < <( opensearch-client -m EOP ${ref} identifier,enclosure,startdate,enddate,orbitNumber,wrsLongitudeGrid  | tr "," " " )

    granules="$( echo $input | cut -d "," -f 2- | tr "," "|")"

    [ "${ref}" == ${granules} ] && granules=""

    ciop-log "INFO" "Processing $( echo ${granules} | tr "|" "\n" | wc -l ) tiles of Sentinel-2 product ${identifier} in format ${format}"

    results="$( process_2A ${ref} ${resolution} ${format} "${pa}" ${granules} || return $? )"
    res=$?

    [ "${res}" != "0"  ] && return ${res}   

    for result in $( echo ${results} | tr " " "\n" | grep -v png )
    do
      echo "result: ${result}"
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
      
      ciop-log "DEBUG" "Checking creafdir"

      tree ${creaf_dir} 

      # set identifier
      metadata \
        "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:identifier" \
        "$( basename "${result}" )" \
        ${target_xml}

      metadata_iso \
        "//A:MD_Metadata/A:fileIdentifier/B:CharacterString" \
        "$( basename "${result}" )" \
        ${target_xml_md}
      # TODO
      # metadata_iso \
      #   "xpath expression" \
      #   "value" \
      #   ${target_xml_md}

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





     #format="$( gdalinfo -json ${result} | jq -r ".driverLongName" )"
     nw_corner="$( gdalinfo -json ${result} | jq -r ".cornerCoordinates | .upperLeft | tostring" | sed 's/\(\[\|\]\)//g' | tr "," " " )"
     se_corner="$( gdalinfo -json ${result} | jq -r ".cornerCoordinates | .lowerRight | tostring" | sed 's/\(\[\|\]\)//g' | tr "," " " )"
     epsg_code="http://www.opengis.net/def/crs/EPSG/0/$( gdalinfo -json ${result} | jq -r ".coordinateSystem | .wkt" | tail -n  1 | cut -d '"' -f 4 )"
     title="Sentinel 2 Surface Reflectance $( basename $result | cut -d "_" -f 6 )"
     abstract="Sentinel 2 Surface Reflectance $( basename $result | cut -d "_" -f 6 ) Product Data"
     min_lon="$( gdalinfo -json  ${result} | jq -r " .wgs84Extent | .coordinates | tostring" | sed 's/\(\[\|\]\)//g' | tr "," "\n" | sed -n 1~2p | awk 'NR == 1 { min=$1 }
        { if ($1<min) min=$1 }
        END { printf "%s", min }' )"
     min_lat="$( gdalinfo -json  ${result} | jq -r " .wgs84Extent | .coordinates | tostring" | sed 's/\(\[\|\]\)//g' | tr "," "\n" | sed -n 2~2p | awk 'NR == 1  { min=$1 }
        { if ($1<min) min=$1 }
        END { printf "%s", min }' )"
     max_lon="$( gdalinfo -json  ${result} | jq -r " .wgs84Extent | .coordinates | tostring" | sed 's/\(\[\|\]\)//g' | tr "," "\n" | sed -n 1~2p | awk 'NR == 1 { max=$1 }
        { if ($1>max) max=$1 }
        END { printf "%s", max }' )"
     max_lat="$( gdalinfo -json  ${result} | jq -r " .wgs84Extent | .coordinates | tostring" | sed 's/\(\[\|\]\)//g' | tr "," "\n" | sed -n 2~2p | awk 'NR == 1 { max=$1 }
        { if ($1>max) max=$1 }
        END { printf "%s", max }' )"
     row_size="$( gdalinfo -json ${result} | jq -r ".size | tostring" | sed 's/\(\[\|\]\)//g' | cut -d ',' -f1 )"
     column_size="$( gdalinfo -json ${result} | jq -r ".size | tostring" | sed 's/\(\[\|\]\)//g' | cut -d ',' -f2 )"
     pixel_size="$( gdalinfo -json ${result} | jq -r ".geoTransform | tostring" | sed 's/\(\[\|\]\)//g' | cut -d ',' -f2 )"

     #p_identifier=$( gdalinfo -json ${result} | jq -r ".files | tostring" | sed 's/\(\[\|\]\)//g' | tr "," " " )

     metadata_iso \
      "//A:MD_Metadata/A:fileIdentifier/B:CharacterString" \
      "${identifier}" \
      ${target_xml_md}

     metadata_iso \
      "//A:MD_Metadata/A:contact/A:CI_ResponsibleParty/A:organisationName/B:CharacterString" \
      "TERRADUE" \
      ${target_xml_md}
  

     metadata_iso \
      "//A:MD_Metadata/A:contact/A:CI_ResponsibleParty/A:contactInfo/A:CI_Contact/A:address/A:CI_Address/A:electronicMailAddress/B:CharacterString" \
      "info@terradue.com" \
      ${target_xml_md}

     metadata_iso \
      "//A:MD_Metadata/A:dateStamp/B:Date" \
      "$( date +%Y-%m-%d )" \
     ${target_xml_md}
  
     metadata_iso \
      "//A:MD_Metadata/A:spatialRepresentationInfo/A:MD_Georectified/A:axisDimensionProperties/A:MD_Dimension[A:dimensionName/A:MD_DimensionNameTypeCode/text()=\"Row\"]/A:dimensionSize/B:Integer" \
      "${row_size}" \
     ${target_xml_md}

     metadata_iso \
      "//A:MD_Metadata/A:spatialRepresentationInfo/A:MD_Georectified/A:axisDimensionProperties/A:MD_Dimension[A:dimensionName/A:MD_DimensionNameTypeCode/text()=\"Column\"]/A:dimensionSize/B:Integer" \
      "${column_size}" \
     ${target_xml_md}

     metadata_iso \
      "//A:MD_Metadata/A:spatialRepresentationInfo/A:MD_Georectified/A:axisDimensionProperties/A:MD_Dimension/A:resolution/B:Length" \
      "${pixel_size}" \
     ${target_xml_md}

     metadata_iso \
      "//A:MD_Metadata/A:spatialRepresentationInfo/A:MD_Georectified/A:cornerPoints/C:Point[@C:id=\"NW_corner\"]/C:pos" \
      "${nw_corner}" \
     ${target_xml_md}

     metadata_iso \
      "//A:MD_Metadata/A:spatialRepresentationInfo/A:MD_Georectified/A:cornerPoints/C:Point[@C:id=\"SE_corner\"]/C:pos" \
      "${se_corner}" \
     ${target_xml_md}

     metadata_iso \
      "//A:MD_Metadata/A:referenceSystemInfo/A:MD_ReferenceSystem/A:referenceSystemIdentifier/A:RS_Identifier/A:code/B:CharacterString" \
      "${epsg_code}" \
     ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:citation/A:CI_Citation/A:title/B:CharacterString" \
 "${title}" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:citation/A:CI_Citation/A:date/A:CI_Date/A:date/B:Date" \
 "$( date +%Y-%m-%d )" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:citation/A:CI_Citation/A:identifier/A:RS_Identifier/A:code/B:CharacterString" \
 "${identifier}" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:abstract/B:CharacterString" \
 "${abstract}" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:pointOfContact/A:CI_ResponsibleParty/A:organisationName/B:CharacterString" \
 "TERRADUE" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:pointOfContact/A:CI_ResponsibleParty/A:contactInfo/A:CI_Contact/A:address/A:CI_Address/A:electronicMailAddress/B:CharacterString" \
 "info@terradue.com" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:extent/A:EX_Extent/A:geographicElement/A:EX_GeographicBoundingBox/A:westBoundLongitude/B:Decimal" \
 "${min_lon}" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:extent/A:EX_Extent/A:geographicElement/A:EX_GeographicBoundingBox/A:eastBoundLongitude/B:Decimal" \
 "${max_lon}" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:extent/A:EX_Extent/A:geographicElement/A:EX_GeographicBoundingBox/A:southBoundLatitude/B:Decimal" \
 "${min_lat}" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:extent/A:EX_Extent/A:geographicElement/A:EX_GeographicBoundingBox/A:northBoundLatitude/B:Decimal" \
 "${max_lat}" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:extent/A:EX_Extent/A:temporalElement/A:EX_TemporalExtent/A:extent/C:TimePeriod/C:begin/C:TimeInstant/C:timePosition" \
 "${startdate}" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:extent/A:EX_Extent/A:temporalElement/A:EX_TemporalExtent/A:extent/C:TimePeriod/C:end/C:TimeInstant/C:timePosition" \
 "${enddate}" \
 ${target_xml_md}

metadata_iso \
 "//A:MD_Metadata/A:contentInfo/A:MD_CoverageDescription/A:dimension/A:MD_RangeDimension/A:sequenceIdentifier/B:MemberName/B:attributeType/B:TypeName/B:aName/B:CharacterString" \
 "unsigned integer" \
 ${target_xml_md}

     metadata_iso \
     "//A:MD_Metadata/A:distributionInfo/A:MD_Distribution/A:distributionFormat/A:MD_Format/A:name/B:CharacterString" \
     "JPEG2000" \
      ${target_xml_md}

     metadata_iso \
      "//A:MD_Metadata/A:distributionInfo/A:MD_Distribution/A:distributionFormat/A:MD_Format/A:name/B:CharacterString" \
      "JPEG2000" \
      ${target_xml_md}

     metadata_iso \
      "//A:MD_Metadata/A:distributionInfo/A:MD_Distribution/A:distributor/A:MD_Distributor/A:distributorContact/A:CI_ResponsibleParty/A:organisationName/B:CharacterString" \
      "CNR" \
      ${target_xml_md}
     
     values="Filters \ Median_Filter: 0
Atmospheric_Correction \ Look_Up_Tables \ Aerosol_Type: $( ciop-getparam aerosol_type )
Atmospheric_Correction \ Look_Up_Tables \ Mid_Latitude: $( ciop-getparam mid_latitude )
Atmospheric_Correction \ Look_Up_Tables \ Ozone_Content: $( ciop-getparam ozone_content )
Atmospheric_Correction \ Flags \ WV_Correction: $( ciop-getparam wv_correction )
Atmospheric_Correction \ Flags \ VIS_Update_Mode: $( ciop-getparam vis_update_mode )
Atmospheric_Correction \ Flags \ WV_Watermask: $( ciop-getparam wv_watermask )
Atmospheric_Correction \ Flags \ Cirrus_Correction: $( ciop-getparam cirrus_correction )
Atmospheric_Correction \ Flags \ BRDF_Correction: $( ciop-getparam brdf_correction )
Atmospheric_Correction \ Flags \ BRDF_Lower_Bound: $( ciop-getparam brdf_lower_bound )
Atmospheric_Correction \ Calibration \ DEM_Unit: $( ciop-getparam dem_unit )
Atmospheric_Correction \ Calibration \ Adj_Km: $( ciop-getparam adj_km )
Atmospheric_Correction \ Calibration \ Visibility: $( ciop-getparam visibility )
Atmospheric_Correction \ Calibration \ Altitude: $( ciop-getparam altitude )
Atmospheric_Correction \ Calibration \ Smooth_WV_Map: $( ciop-getparam smooth_wv_map )
Atmospheric_Correction \ Calibration \ WV_Threshold_Cirrus: $( ciop-getparam wv_threshold_cirrus )"

     metadata_iso \
      "//A:MD_Metadata/A:dataQualityInfo/A:DQ_DataQuality/A:lineage/A:LI_Lineage/A:statement/B:CharacterString" \
      "${values}" \
      ${target_xml_md}

     metadata_iso \
      "//A:MD_Metadata/A:identificationInfo/A:MD_DataIdentification/A:extent/A:EX_Extent/A:geographicElement/A:EX_GeographicDescription/A:geographicIdentifier/A:MD_Identifier/A:code/B:CharacterString" \
      "${pa}" \
      ${target_xml_md} 


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

function metadata_iso() {
  local xpath="$1"
  local value="$2"
  local target_xml="$3"

  # TODO 
  xmlstarlet ed -L \
   -N A="http://www.isotc211.org/2005/gmd" \
   -N B="http://www.isotc211.org/2005/gco" \
   -N C="http://www.opengis.net/gml" \
   -u  "${xpath}" \
   -v "${value}" \
   ${target_xml}

}
