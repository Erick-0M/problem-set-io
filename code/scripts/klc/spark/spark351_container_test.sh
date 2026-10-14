#!/bin/bash
#SBATCH --job-name=spark351_test
#SBATCH --account=kellogg
#SBATCH --partition=kellogg
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=2
#SBATCH --mem=4G
#SBATCH --time=00:20:00
#SBATCH --output=spark351_test_%j.out
# Feasibility test: standalone Spark 3.5.1 cluster from the site container, driven by a Jupyter notebook.
source /etc/profile >/dev/null 2>&1
module load singularityce/4.3.1-gcc-8.5.0
SIF=/software/spark/3.5.1/pyspark-notebook_spark-3.5.1.sif
SX="singularity exec $SIF"
export SPARK_HOME_C=/usr/local/spark
MASTER_HOST=$(hostname -s); MASTER=spark://$MASTER_HOST:7077
export SPARK_MASTER_HOST=$MASTER_HOST SPARK_WORKER_DIR=/tmp/spark_$USER SPARK_LOCAL_DIRS=/tmp/spark_$USER
mkdir -p $SPARK_WORKER_DIR
$SX $SPARK_HOME_C/bin/spark-class org.apache.spark.deploy.master.Master --host $MASTER_HOST > master.log 2>&1 &
sleep 8
# one worker per node, via srun (no ssh needed)
srun --ntasks=$SLURM_NNODES --ntasks-per-node=1 --overlap bash -c "export SPARK_WORKER_DIR=/tmp/spark_$USER; $SX $SPARK_HOME_C/bin/spark-class org.apache.spark.deploy.worker.Worker --cores 2 --memory 3g $MASTER" > workers.log 2>&1 &
sleep 12

cat > nb_test.ipynb <<NB
{"cells":[{"cell_type":"code","execution_count":null,"metadata":{},"outputs":[],"source":[
"import socket\nfrom pyspark.sql import SparkSession\n",
"s = SparkSession.builder.master('$MASTER').appName('nb_test').config('spark.cores.max','4').config('spark.executor.memory','1g').getOrCreate()\n",
"print('NBVERSION', s.version, s.sparkContext.master)\n",
"print('NBSUM', s.range(10000000).selectExpr('sum(id)').collect())\n",
"print('NBHOSTS', sorted(set(s.sparkContext.parallelize(range(8), 8).map(lambda _: socket.gethostname()).collect())))\n",
"s.stop()"]}],
"metadata":{"kernelspec":{"display_name":"Python 3","language":"python","name":"python3"}},"nbformat":4,"nbformat_minor":5}
NB
export PYTHONPATH=$SPARK_HOME_C/python:$SPARK_HOME_C/python/lib/py4j-0.10.9.7-src.zip PYSPARK_PYTHON=python3
echo "=== NOTEBOOK EXEC"
$SX jupyter nbconvert --to notebook --execute nb_test.ipynb --output nb_out.ipynb 2>&1 | tail -3
grep -o 'NB[A-Z]* [^"\\]*' nb_out.ipynb | head
echo "=== JUPYTERLAB on $MASTER_HOST"
$SX jupyter-lab --no-browser --ip=0.0.0.0 --port=9003 --ServerApp.token=testtoken > lab.log 2>&1 &
sleep 15
curl -s -o /dev/null -w "LAB_HTTP %{http_code}\n" http://$MASTER_HOST:9003/api?token=testtoken
grep -c "Registering worker" master.log
pkill -u $USER -f 'jupyter-lab|deploy.master|deploy.worker'
