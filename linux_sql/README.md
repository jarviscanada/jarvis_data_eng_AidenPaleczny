# Linux Cluster Monitoring Agent

### Introduction

This project is a lightweight monitoring agent for a cluster of Linux servers. Each server runs 2 scripts using Bash. The first records the systems hardware specs once, the other records resource usage (free memory, cpu idle, etc.) every minute. All the data is written to a single Postgres database, so a team could see what hardware each node has and how heavily each is being used over time. This can help with capacity planning, such as finding nodes that are commonly low on memory or disk space.

The database runs on Docker, in a container, to keep the setup repeatable and isolated from the host. The usage collection script is scheduled using crontab. All development was on Rocky Linux. Built with Bash, Docker, PostgreSQL, psql, cron, and Git (GitFlow).

### Quick Start


```
# 1. create and start the postgresql container, terminal at this directory
./scripts/psql_docker.sh create db_username db_password
./scripts/psql_docker.sh start

# 2. create the database and tables
psql -h localhost -U db_username -d postgres -c "CREATE DATABASE host_agent;"
psql -h localhost -U db_username -d host_agent -f sql/ddl.sql

# 3. record this host's hardware specs, run once per host
./scripts/host_info.sh localhost 5432 host_agent db_username db_password

# 4. record a usage sample manually, to optionally confirm it works
./scripts/host_usage.sh localhost 5432 host_agent db_username db_password

# 5. schedule a usage sample each minute
crontab -e

# add this line, then ":wq" to save and exit, make sure you replace the path
* * * * * bash /path/to/linux_sql/scripts/host_usage.sh localhost 5432 host_agent db_username db_password >> /tmp/host_usage.log 2>&1


```

### Implementation

The project was built in 4 stages. First the database was provisioned and set up, then the schema was defined, then the collection shell scripts were written, and finally the collection was automated with cron. Each stage was developed on its own feature branch which was merged into the develop branch. 

#### Architecture

Cluster:

Every host in the cluster runs the same 2 agent scripts. One host runs the postgreSQL container, and all the other agents send their data to it over the network. host_info.sh runs once when a host is set up. host_usage.sh is run every minute througfh cron.

#### Scripts

psql_docker.sh:
- Manages the postgreSQL container
- `create` flag makes a named volume so data survives if the container is removed, then starts postgres container named "jrvs-psql" on port 5432
- `start` and `stop` flags control an existing container
- The script starts the Docker service if it's not running, and exits with an error if you create a container that already exists, create one without credentials supplied, or start or stop one that doesn't exist

```
./scripts/psql_docker.sh create|start|stop [db_username] [db_password]
```

ddl.sql:
- Connects to the database "host_agent" and creates the "host_info" and "host_usage" tables
- Uses "CREATE TABLE IF NOT EXISTS", so that it's safe to run more than once without breaking anything

```
psql -h localhost -U db_username -d host_agent -f sql/ddl.sql
```

host_info.sh:
- Collects hardware specifications using shell commands (from lscpu, /proc/cpuinfo, /proc/meminfo), and inserts a row in the database to the host_info table with the resulting info
- Since hostnames are unique in the table (as a constraint in SQL), running this a second time on the same host is rejected

```
./scripts/host_info.sh psql_host psql_port db_name psql_user psql_password
```

host_usage.sh:
- Takes a 1 second vmstat sample, reads disk space with df, and inserts 1 row into the host_usage table
- It finds the host's id from a subquery on its hostname, so host_info.sh must be run on the host first

```
./scripts/host_usage.sh psql_host psql_port db_name psql_user psql_password
```

crontab runs host_usage.sh once per minute. The output and errors from it are appended to a log file in /tmp/host_usage.log, for debugging if anything fails

#### Database Modelling

host_info: 1 row per host, holds hardware data that's unlikely to be changed

|  Column   |  Type   | Description |
| --- | --- | --- |
|  id   | SERIAL    |  Primary key, assigned automatically   |
|  hostname   |  VARCHAR   |  Unique hostname   |
|  cpu_number   |  INT2   |  Number of CPUs   |
|  cpu_architecture   |  VARCHAR   |  Architecture of the CPU, such as x86_64   |
|  cpu_model   |  VARCHAR   |  CPU model name   |
|  cpu_mhz   |  FLOAT8   | CPU clock speed in MHz    |
|  l2_cache   |  INT4   |  L2 cache size in kb   |
|  timestamp   |  TIMESTAMP   |  When the row was recorded in UTC   |
|  total_mem   |   INT4  | Total memory in kB    |


host_usage: 1 row per host per minute

|  Column   |  Type   | Description |
| --- | --- | --- |
|  timestamp   |   TIMESTAMP  | When the sample was taken in UTC    |
| host_id | INT4 | Foreign key to host_info |
| memory_free | INT4 | Free memory in MB |
| cpu_idle | INT2 | Percent of CPU time spent idle |
| cpu_kernel | INT2 | Percent of CPU time spent in kernel mode |
| disk_io | INT4 | Disk I/O operations in progress, summed on all disks |
| disk_available | INT4 | Available disk space on root filesystem in MB |

All columns in both tables are required (NOT NULL)

### Test

- psql_docker.sh: 
    - Ran each command and check the output of each, checked the exit code of the script with echo $?
    - Checked: creating the container twice, creating it without credentials, passing an invalid command
- ddl.sql:
    - Ran the script twice. The second time it skipped the table creation correctly
    - Listed the tables after running this to check, with \dt
- host_info.sh and host_usage.sh:
    - Traced each step with `bash -x` to confirm each variable was parsed correctly before the insert
    - Check them against the actual values in the database, using SELECT to check the rows inserted
- crontab:
    - Let everything run for a few minutes and confirmed /tmp/host_usage.log showed a successful insert each minute
    - Checked that host_usage table had rows about 60 seconds apart

### Deployment

The source code is on GitHub and follows GitFlow. Each feature was developed on its own branch and was merged into develop, with a pull request to merge again from develop into main to be merged once everything is reviewed. The database runs in a Docker container with a named volume for persistent storage. The usage data collection is deployed on each host as a crontab entry.

### Improvements

- The script doesn't handle hardware changes. The host info is inserted once and fails if the script is attempted to be run a second time on the database insert. The script could be improved to check if any changes to the hardware are present, and update the row instead.
- Credentials could be kept out of commands. The database password is currently an argument and is stored as text in the crontab entry. A file to store the password with restricted permissions could be a more secure improvement.
- If the database can't be reached, the sample from that minute is lost. The agent could buffer and store samples locally until the database is reachable again.
- Both agent scripts repeat code, with the argument checks and the psql call. Moving these to share a function call would be better practice.