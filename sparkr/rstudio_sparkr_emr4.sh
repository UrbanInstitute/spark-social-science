#!/bin/bash
set -x -e
if grep isMaster /mnt/var/lib/info/instance.json | grep true;
then
	aws s3 cp s3://your-bucket-name-goes-here/rstudio_sparkr_emr4-proc.sh .
	sh ./rstudio_sparkr_emr4-proc.sh "$@" &
fi