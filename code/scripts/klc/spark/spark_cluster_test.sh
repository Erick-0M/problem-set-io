#!/bin/bash
#SBATCH --job-name=spark_test
#SBATCH --account=kellogg
#SBATCH --partition=kellogg
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=2
#SBATCH --mem=4G
#SBATCH --time=00:15:00
#SBATCH --output=spark_test_%j.out
# Feasibility test: standalone Spark 2.3.0 cluster on Slurm using only site modules/tools.
source /etc/profile >/dev/null 2>&1
module load spark/2.3.0
export PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.6-src.zip PYSPARK_PYTHON=python3
source ~/spark_test/initialize_spark_klc.sh   # sourced so the master stays alive
MASTER=spark://$(hostname -s):7077
cat > $SLURM_SUBMIT_DIR/spark_test_job.py <<PY
import socket
from pyspark.sql import SparkSession
s = SparkSession.builder.master("$MASTER").appName("klc_test").config("spark.cores.max","4").config("spark.executor.memory","1g").getOrCreate()
print("MASTER", s.sparkContext.master, "VERSION", s.version)
print("SUM", s.range(10000000).selectExpr("sum(id)").collect())
print("HOSTS", sorted(set(s.sparkContext.parallelize(range(8), 8).map(lambda _: socket.gethostname()).collect())))
PY
python3 $SLURM_SUBMIT_DIR/spark_test_job.py 2>&1 | grep -vE "WARN|INFO"
bash $SPARK_TOOLS/cleanup_spark.sh
pkill -u $USER -f org.apache.spark.deploy.master.Master
