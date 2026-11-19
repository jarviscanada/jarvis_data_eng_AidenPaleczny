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
# Take a one second vm stat sample in mb
vmstat_mb=$(vmstat --unit M 1 2 | tail -n1)
hostname=$(hostname -f)
# Parse resource usage
memory_free=$(echo "$vmstat_mb" | awk '{print $4}' | xargs)
cpu_idle=$(echo "$vmstat_mb" | awk '{print $15}' | xargs)
cpu_kernel=$(echo "$vmstat_mb" | awk '{print $14}' | xargs)
disk_io=$(vmstat -d | awk 'NR > 2 {sum += $10} END {print sum + 0}' | xargs)
disk_available=$(df -BM / | awk 'NR == 2 {print $4}' | sed 's/M$//' | xargs)
# Current time in utc
timestamp=$(date -u '+%Y-%m-%d %H:%M:%S')
# Find matching id in host info
host_id="(SELECT id FROM host_info WHERE hostname='$hostname')"
# Construct insert
insert_stmt="INSERT INTO host_usage (\"timestamp\", host_id, memory_free, cpu_idle, cpu_kernel, disk_io, disk_available) VALUES ('$timestamp', $host_id, $memory_free, $cpu_idle, $cpu_kernel, $disk_io, $disk_available);"
# Execute sql
export PGPASSWORD=$psql_password
psql -h "$psql_host" -p "$psql_port" -d "$db_name" -U "$psql_user" -c "$insert_stmt"
exit $?