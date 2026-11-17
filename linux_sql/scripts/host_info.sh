#!/bin/bash
# Setup arguments
psql_host=$1
psql_port=$2
db_name=$3
psql_user=$4
psql_password=$5
# Validate arguments
if [ "$#" -ne 5 ]; then
  echo "Illegal number of parameters"
  echo "Usage: $0 psql_host psql_port db_name psql_user psql_password"
  exit 1
fi
# Save lscpu output once so all fields are parseds from the same snapshot
lscpu_out=$(lscpu)
# Parse
hostname=$(hostname -f)
cpu_number=$(echo "$lscpu_out" | grep -E "^CPU\(s\):" | awk '{print $2}' | xargs)
cpu_architecture=$(echo "$lscpu_out" | grep -E "^Architecture:" | awk '{print $2}' | xargs)
cpu_model=$(echo "$lscpu_out" | grep -E "^Model name:" | awk -F: '{print $2}' | xargs)
cpu_mhz=$(grep -m1 "^cpu MHz" /proc/cpuinfo | awk -F: '{print $2}' | xargs)
l2_cache=$(lscpu --caches=NAME,ONE-SIZE --bytes | awk '$1 == "L2" {print $2 / 1024}' | xargs)
total_mem=$(grep -E "^MemTotal:" /proc/meminfo | awk '{print $2}' | xargs)
# Current time in utc
timestamp=$(date -u '+%Y-%m-%d %H:%M:%S')
# Construct insert
insert_stmt="INSERT INTO host_info (hostname, cpu_number, cpu_architecture, cpu_model, cpu_mhz, l2_cache, \"timestamp\", total_mem) VALUES ('$hostname', $cpu_number, '$cpu_architecture', '$cpu_model', $cpu_mhz, $l2_cache, '$timestamp', $total_mem);"
# Execute insert
export PGPASSWORD=$psql_password
psql -h "$psql_host" -p "$psql_port" -d "$db_name" -U "$psql_user" -c "$insert_stmt"
exit $?