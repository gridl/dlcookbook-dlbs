#!/bin/bash
unknown_params_action=set
. $DLBS_ROOT/scripts/parse_options.sh || exit 1;    # Parse command line options
. $DLBS_ROOT/scripts/utils.sh
loginfo "$0 $*"  >> ${exp_log_file}                 # Log command line arguments for debugging purposes
if [ "$exp_simulation" = "true" ]; then
    echo "${runtime_bind_proc} python ${mxnet_bench_path}/mxnet_benchmarks/benchmarks.py ${mxnet_args}"
    exit 0
fi
__framework__="mxnet"
__batch_file__="$(dirname ${exp_log_file})/${exp_framework_id}_${exp_device}_${exp_model}.batch"
is_batch_good "${__batch_file__}" "${exp_device_batch}" || {
  echo "Skipping experiment since the batch size seems to be too big for current configuration"
  exit 0
}
echo "__exp.framework_title__= \"${__framework__}\"" >> ${exp_log_file}
# This script is to be executed inside docker container or on a host machine.
# Thus, the environment must be initialized inside this scrip lazily.
[ -z "${runtime_limit_resources}" ] && runtime_limit_resources=":;"
script="\
    export ${mxnet_env};\
    echo ${mxnet_env};\
    echo -e \"__results.start_time__= \x22\$(date +%Y-%m-%d:%H:%M:%S:%3N)\x22\";\
    ${runtime_limit_resources}\
    ${runtime_bind_proc} python ${mxnet_bench_path}/mxnet_benchmarks/benchmarks.py ${mxnet_args} &\
    proc_pid=\$!;\
    [ "${resource_monitor_enabled}" = "true" ] && echo -e \"\${proc_pid}\" > ${resource_monitor_pid_file_folder}/proc.pid;\
    wait \${proc_pid};\
    echo -e \"__results.end_time__= \x22\$(date +%Y-%m-%d:%H:%M:%S:%3N)\x22\";\
    echo -e \"__results.proc_pid__= \${proc_pid}\";\
"
if [ "${exp_env}" = "docker" ]; then
    assert_docker_img_exists ${mxnet_docker_image}
    ${exp_docker_launcher} run ${mxnet_docker_args} /bin/bash -c "eval $script" >> ${exp_log_file} 2>&1
else
    eval $script >> ${exp_log_file} 2>&1
fi

if mxnet_error ${exp_log_file} ${exp_phase}; then
    logwarn "error in \"${exp_log_file}\" with effective batch ${exp_effective_batch} (per device batch ${exp_device_batch})";
    update_error_file "${__batch_file__}" "${exp_device_batch}";
fi
