#!/bin/bash
set -x -e

aws s3 cp s3://ui-spark-social-science/emr-scripts/rstudio_sparkr_emr5lyr-proc.sh .
sh ./rstudio_sparkr_emr5lyr-proc.sh "$@"