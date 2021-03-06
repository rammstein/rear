# if KEEP_OLD_OUTPUT_COPY is not empty then move old OUTPUT_PREFIX directory to OUTPUT_PREFIX.old

[ -z "${KEEP_OLD_OUTPUT_COPY}" ] && return

# do not do this for tapes and special attention for file:///path
url="$( echo $stage | tr '[:lower:]' '[:upper:]')_URL"
local scheme=$(url_scheme ${!url})
local path=$(url_path ${!url})
local opath=$(output_path $scheme $path)

# if $opath is empty return silently (e.g. scheme tape)
[ -z "$opath" ] && return 0

if ! test -f "${opath}/.lockfile" ; then
        # lockfile made through workflow backup already (so output keep hands off)
        if test -d "${opath}" ; then
                rm -rf $v "${opath}.old" >&2
                StopIfError "Could not remove '${opath}.old'"
                mv -f $v "${opath}" "${opath}.old" >&2
                StopIfError "Could not move '${opath}'"
        fi
else
        Log "Lockfile '${opath}/.lockfile' found. Not keeping old backup data."
fi
# the ${BUILD_DIR}/outputfs/${OUTPUT_PREFIX} will be created by output/default/20_make_prefix_dir.sh
