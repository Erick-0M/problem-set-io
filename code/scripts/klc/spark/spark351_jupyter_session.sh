#!/bin/bash
#SBATCH --job-name=spark351_lab
#SBATCH --account=kellogg
#SBATCH --partition=kellogg
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --output=spark351_lab_%j.out
# Spark 3.5.1 standalone cluster (site container) + JupyterLab as driver on the first node.
# Connect from the Mac: tunnel local 9003 -> <first node>:9003 through the KLC login node.
source /etc/profile >/dev/null 2>&1
module load singularityce/4.3.1-gcc-8.5.0
SX="singularity exec /software/spark/3.5.1/pyspark-notebook_spark-3.5.1.sif"
SH=/usr/local/spark
MASTER_HOST=$(hostname -s); MASTER=spark://$MASTER_HOST:7077
export SPARK_MASTER_HOST=$MASTER_HOST SPARK_LOCAL_DIRS=/tmp/spark_$USER SPARK_WORKER_DIR=/tmp/spark_$USER
mkdir -p $SPARK_WORKER_DIR
$SX $SH/bin/spark-class org.apache.spark.deploy.master.Master --host $MASTER_HOST > master.log 2>&1 &
sleep 8
srun --ntasks=$SLURM_NNODES --ntasks-per-node=1 --overlap bash -c "$SX $SH/bin/spark-class org.apache.spark.deploy.worker.Worker --cores $SLURM_CPUS_PER_TASK --memory 6g $MASTER" > workers.log 2>&1 &
sleep 5
export PYTHONPATH=$SH/python:$SH/python/lib/py4j-0.10.9.7-src.zip PYSPARK_PYTHON=python3 SPARK_MASTER_URL=$MASTER
echo "LAB_NODE=$MASTER_HOST MASTER=$MASTER"
$SX jupyter-lab --no-browser --ip=0.0.0.0 --port=9003 --ServerApp.token=klcspark
