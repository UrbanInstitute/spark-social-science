#!/bin/bash
set -x -e

# Usage:
# --no-rstudio - don't install rstudio-server
# --sparklyr - install RStudio's sparklyr package
# --sparkr - install SparkR package
# --shiny - install Shiny server
# --no-tutorials - does not copy in Urban Institute SparkR Tutorials from GitHub#
#
# --user - set user for rstudio, default "hadoop"
# --user-pw - set user-pw for user USER, default "hadoop"
# --rstudio-port - set rstudio port, default 8787
#
# --rhdfs - install rhdfs package, default false
# --plyrmr - install plyrmr package, default false
# --no-updateR - don't update latest R version

IS_MASTER=false
if grep isMaster /mnt/var/lib/info/instance.json | grep true;
then
  IS_MASTER=true
fi

if [ "$IS_MASTER" = true ] then
	aws s3 cp s3://u-spark-social-science/emr-scripts/rstudio_sparkr_emr5lyr-proc.sh .
	sh ./rstudio_sparkr_emr5lyr-proc.sh "$@"
fi