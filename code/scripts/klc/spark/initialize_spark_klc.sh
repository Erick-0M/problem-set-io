#!/bin/bash
# Copy of /software/spark/tools/initialize_spark.sh; only change: workers get JAVA_HOME/SPARK_HOME/PATH (ssh drops the module env).
#
# Starts spark master on execution host, then
# starts spark slaves on all hosts listed in PBS_NODEFILE.
#

echo "###################################"
echo "#####   INITIALIZING SPARK    #####"
echo "###################################"

SPARK_WORKER_CORES=${SLURM_NTASKS_PER_NODE}
SPARK_WORKER_MEMORY=${SLURM_MEM_PER_NODE}
echo $SPARK_WORKER_MEMORY

# Global behavioral variables.
#SPARK_WORKER_DIR=${SPARK_WORKER_DIR:-$PBS_O_WORKDIR}
SPARK_WORKER_DIR=${SPARK_WORKER_DIR:-$SLURM_SUBMIT_DIR}
echo "***********************************"
echo "SPARK_WORKER_DIR= $SPARK_WORKER_DIR"
echo "***********************************"
#SPARK_LOCAL_DIRS=${SPARK_LOCAL_DIRS:-/local/spark_work_local}

# Start Spark master at master
MASTER_HOST=`hostname -s`
echo "***********************************"
echo "-- Starting SPARK Master at $MASTER_HOST"
echo "***********************************"
$SPARK_HOME/bin/spark-class org.apache.spark.deploy.master.Master &
sleep 5

# Start Spark workers at nodes
echo "***********************************"
echo "SLURM_JOB_NODELIST= $SLURM_JOB_NODELIST"
echo "***********************************"
NODE_LIST=$( scontrol show hostnames $SLURM_JOB_NODELIST )
echo -- Node List: $NODE_LIST
echo "***********"
for SLAVE_NODE in $NODE_LIST; do
  echo "-- Starting SPARK Slave at host $SLAVE_NODE, connecting to spark://$MASTER_HOST:7077"
  timeout 5 ssh $SLAVE_NODE "export JAVA_HOME=$JAVA_HOME SPARK_HOME=$SPARK_HOME PATH=$JAVA_HOME/bin:$PATH; export SPARK_WORKER_DIR=$SPARK_WORKER_DIR; export SPARK_WORKER_CORES=${SPARK_WORKER_CORES}; export SPARK_WORKER_MEMORY="${SPARK_WORKER_MEMORY}m" ; cd /tmp; nohup $SPARK_HOME/bin/spark-class org.apache.spark.deploy.worker.Worker spark://$MASTER_HOST:7077 &"
done

echo "-- WAIT FOR STARTUP --"
sleep 10

# Set up recommended allocation for jobs.
# EXEC_CORES=$(echo "${SLURM_NTASKS_PER_NODE} - 1" | bc)
# - need 2 cores for exec with large jobs - jon

EXEC_CORES=4
NUM_EXEC=10
EXEC_MEM=8
#EXEC_CORES=$(echo "${SLURM_NTASKS_PER_NODE} - 2" | bc)
#EXEC_MEM=$(echo "${SLURM_MEM_PER_CPU} * ${EXEC_CORES}" | bc)
#EXEC_RES_LIST="--executor-cores=${EXEC_CORES} --executor-memory=${EXEC_MEM}MB"
EXEC_RES_LIST="--num-executors=${NUM_EXEC} --executor-cores=${EXEC_CORES} --executor-memory=${EXEC_MEM}G"
echo "***********************************"
echo HPC cores per node: $SLURM_NTASKS_PER_NODE
#echo HPC memory per core: $SLURM_MEM_PER_CPU
echo HPC memory per core: $SLURM_MEM_PER_NODE
echo SPARK executor resources per node: $EXEC_RES_LIST
echo "***********************************"

echo "###################################"
