#!/bin/bash 

# Requirements for this script
#  installed versions of: FSL, Connectome Workbench (wb_command)
#  environment: HCPPIPEDIR, FSLDIR, CARET7DIR

########################################## PIPELINE OVERVIEW ##########################################

# TODO

########################################## OUTPUT DIRECTORIES ##########################################

# TODO

################################################ SUPPORT FUNCTIONS ##################################################

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------

set -eu

pipedirguessed=0
if [[ "${HCPPIPEDIR:-}" == "" ]]
then
    pipedirguessed=1
    #fix this if the script is more than one level below HCPPIPEDIR
    export HCPPIPEDIR="$(dirname -- "$0")/.."
fi

source "${HCPPIPEDIR}/global/scripts/debug.shlib" "$@"         # Debugging functions; also sources log.shlib
source "$HCPPIPEDIR/global/scripts/newopts.shlib" "$@"
source "${HCPPIPEDIR}/global/scripts/processingmodecheck.shlib"  # Check processing mode requirements

opts_SetScriptDescription "Run fMRISurface processing HCP pipline on data processed by postfreesurfer"
opts_AddMandatory '--path' 'Path' "path to study folder" ""
opts_AddMandatory '--subject' 'Subject' 'subject ID' ""
opts_AddMandatory '--fmriname' 'NameOffMRI' 'name (prefix) to use for the output' ""
opts_AddMandatory '--lowresmesh' 'LowResMesh' 'low_res_mesh_number' ""
opts_AddMandatory '--fmrires' 'FinalfMRIResolution' 'final resolution (mm) of the output data' ""
opts_AddMandatory '--smoothingFWHM' 'SmoothingFWHM' 'smoothing_FWHM_(mm)' ""
opts_AddMandatory '--grayordinatesres' 'GrayordinatesResolution' 'grayordinates_res_(mm)' ""
opts_AddOptional '--regname' 'RegName' 'surface_registration_name' "The surface registeration name, defaults to 'MSMSulc'" "MSMSulc"
opts_AddOptional '--fmri-qc' 'QCMode' '"YES OR NO OR ONLY"' "Controls whether to generate a QC scene and snapshots (default=YES). ONLY executes *just* the QC script, skipping everything else (e.g., for previous data)" "YES"

opts_ParseArguments "$@"

if ((pipedirguessed))
then
    log_Err_Abort "HCPPIPEDIR is not set, you must first source your edited copy of Examples/Scripts/SetUpHCPPipeline.sh"
fi

opts_ShowValues

"$HCPPIPEDIR"/show_version

# ------------------------------------------------------------------------------
#  Verify required environment variables are set and log value
# ------------------------------------------------------------------------------

log_Check_Env_Var HCPPIPEDIR
log_Check_Env_Var FSLDIR
log_Check_Env_Var CARET7DIR

HCPPIPEDIR_fMRISurf=${HCPPIPEDIR}/fMRISurface/scripts

# ------------------------------------------------------------------------------
#  Parse Command Line Options
# ------------------------------------------------------------------------------

log_Msg "Platform Information Follows: "
uname -a

log_Msg "Parsing Command Line Options"

# # parse arguments
# Path=`opts_GetOpt1 "--path" $@`
# Subject=`opts_GetOpt1 "--subject" $@`
# NameOffMRI=`opts_GetOpt1 "--fmriname" $@`
# LowResMesh=`opts_GetOpt1 "--lowresmesh" $@`
# FinalfMRIResolution=`opts_GetOpt1 "--fmrires" $@`
# SmoothingFWHM=`opts_GetOpt1 "--smoothingFWHM" $@`
# GrayordinatesResolution=`opts_GetOpt1 "--grayordinatesres" $@`
# RegName=`opts_GetOpt1 "--regname" $@`
# RegName=`opts_DefaultOpt $RegName MSMSulc`
# QCMode=`opts_GetOpt1 "--fmri-qc" $@`
# QCMode=`opts_DefaultOpt $QCMode YES`
# QCMode="$(echo ${QCMode} | tr '[:upper:]' '[:lower:]')"  # Convert to all lowercase

doProcessing=1
doQC=1

log_Msg "Path: ${Path}"
log_Msg "Subject: ${Subject}"
log_Msg "NameOffMRI: ${NameOffMRI}"
log_Msg "LowResMesh: ${LowResMesh}"
log_Msg "FinalfMRIResolution: ${FinalfMRIResolution}"
log_Msg "SmoothingFWHM: ${SmoothingFWHM}"
log_Msg "GrayordinatesResolution: ${GrayordinatesResolution}"
log_Msg "RegName: ${RegName}"
log_Msg "QCMode: $QCMode"
case "$QCMode" in
    (yes)
        ;;
    (no)
        doQC=0
        ;;
    (only)
        doProcessing=0
		log_Warn "Only generating fMRI QC scene and snapshots from existing data (no other processing)"
        ;;
    (*)
        log_Err_Abort "unrecognized value '$QCMode' for --fmri-qc, use 'YES', 'NO', or 'ONLY'"
        ;;
esac

if [ "${RegName}" = "FS" ] ; then
    log_Warn "WARNING: FreeSurfer's surface registration (based on cortical folding) is deprecated in the"
    log_Warn "         HCP Pipelines as it results in poorer cross-subject functional and cortical areal "
    log_Warn "         alignment relative to MSMSulc. Additionally, FreeSurfer registration results in "
    log_Warn "         dramatically higher surface distortion (both isotropic and anisotropic). These things"
    log_Warn "         occur because FreeSurfer's registration has too little regularization of folding patterns"
    log_Warn "         that are imperfectly correlated with function and cortical areas, resulting in overfitting"
    log_Warn "         of folding patterns. See Robinson et al 2014, 2018 Neuroimage, and Coalson et al 2018 PNAS"
    log_Warn "         for more details."
fi

# Setup PATHS
PipelineScripts=${HCPPIPEDIR_fMRISurf}

#Naming Conventions
AtlasSpaceFolder="MNINonLinear"
T1wFolder="T1w"
NativeFolder="Native"
ResultsFolder="Results"
DownSampleFolder="fsaverage_LR${LowResMesh}k"
ROIFolder="ROIs"
OutputAtlasDenseTimeseries="${NameOffMRI}_Atlas"

AtlasSpaceFolder="$Path"/"$Subject"/"$AtlasSpaceFolder"
T1wFolder="$Path"/"$Subject"/"$T1wFolder"
ResultsFolder="$AtlasSpaceFolder"/"$ResultsFolder"/"$NameOffMRI"
ROIFolder="$AtlasSpaceFolder"/"$ROIFolder"

# ------------------------------------------------------------------------------
#  Start work
# ------------------------------------------------------------------------------

if ((doProcessing)); then
    #Make fMRI Ribbon
    #Noisy Voxel Outlier Exclusion
    #Ribbon-based Volume to Surface mapping and resampling to standard surface
    log_Msg "Make fMRI Ribbon"
    log_Msg "mkdir -p ${ResultsFolder}/RibbonVolumeToSurfaceMapping"
    mkdir -p "$ResultsFolder"/RibbonVolumeToSurfaceMapping
    "$PipelineScripts"/RibbonVolumeToSurfaceMapping.sh "$ResultsFolder"/RibbonVolumeToSurfaceMapping "$ResultsFolder"/"$NameOffMRI" "$Subject" "$AtlasSpaceFolder"/"$DownSampleFolder" "$LowResMesh" "$AtlasSpaceFolder"/"$NativeFolder" "${RegName}"

    #Surface Smoothing
    log_Msg "Surface Smoothing"
    "$PipelineScripts"/SurfaceSmoothing.sh "$ResultsFolder"/"$NameOffMRI" "$Subject" "$AtlasSpaceFolder"/"$DownSampleFolder" "$LowResMesh" "$SmoothingFWHM"

    #Subcortical Processing
    log_Msg "Subcortical Processing"
    "$PipelineScripts"/SubcorticalProcessing.sh "$AtlasSpaceFolder" "$ROIFolder" "$FinalfMRIResolution" "$ResultsFolder" "$NameOffMRI" "$SmoothingFWHM" "$GrayordinatesResolution"

    #Generation of Dense Timeseries
    log_Msg "Generation of Dense Timeseries"
    "$PipelineScripts"/CreateDenseTimeseries.sh "$AtlasSpaceFolder"/"$DownSampleFolder" "$Subject" "$LowResMesh" "$ResultsFolder"/"$NameOffMRI" "$SmoothingFWHM" "$ROIFolder" "$ResultsFolder"/"$OutputAtlasDenseTimeseries" "$GrayordinatesResolution"
fi

if ((doQC)); then
    log_Msg "Generating fMRI QC scene and snapshots"
    "$PipelineScripts"/GenerateFMRIScenes.sh \
        --study-folder="$Path" \
        --subject="$Subject" \
        --fmriname="$NameOffMRI" \
        --output-folder="$ResultsFolder/fMRIQC"
fi

log_Msg "Completed!"
