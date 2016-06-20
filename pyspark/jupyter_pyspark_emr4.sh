#!/bin/bash
set -x -e
if grep isMaster /mnt/var/lib/info/instance.json | grep true;
then
	aws s3 cp s3://ui-emr-util/jupyter_pyspark_emr4_v2-proc.sh .
	sh ./jupyter_pyspark_emr4_v2-proc.sh &
fi