#!/bin/bash
set -x -e
# AWS EMR bootstrap script 
# for installing SparkR & RStudio on on AWS EMR 5.25.0 with Spark 2.4.3 
#
# Adapted heavily from AWS Engineer Tom Zeng
# 
##############################

# Usage:
# --no-rstudio - don't install rstudio-server
# --no-sparklyr - install RStudio's sparklyr package
# --shiny - install Shiny server
# --no-tutorials - does not copy in Urban Institute SparkR Tutorials from GitHub
# --user - set user for rstudio, default "hadoop"
# --user-pw - set user-pw for user USER, default "hadoop"
# --rstudio-port - set rstudio port, default 8787
# --rhdfs - install rhdfs package, default false
# --plyrmr - install plyrmr package, default false
# --no-updateR - don't update latest R version
# --adrf - install a special tutorial for the ADRF environment

# check for master node
IS_MASTER=false
if grep isMaster /mnt/var/lib/info/instance.json | grep true;
then
  IS_MASTER=true
fi



# error message
error_msg ()
{
	echo 1>&2 "Error: $1"
}

# get input parameters
SPARKR=true
SPARKLYR=true
RSTUDIO=true
SHINY=false
SPARKR_TUTORIALS=true
PLYRMR=false
RHDFS=false
RSTUDIOPORT=8787
NOTIFY=""

USER="rstudio"
USERPW="rstudio"

ADRF=false

while [ $# -gt 0 ]; do
    case "$1" in
      --no-sparklyr)
        SPARKLYR=false
        ;;
      --no-rstudio)
        RSTUDIO=false
        ;;
      --shiny)
        SHINY=true
        ;;
      --no-tutorials)
        SPARKR_TUTORIALS=false
        ;;
      --plyrmr)
        PLYRMR=true
        ;;
      --rhdfs)
        RHDFS=true
        ;;
      --rstudio-port)
        shift
        RSTUDIOPORT=$1
        ;;
      --user)
        shift
        USER=$1
        ;;
      --user-pw)
        shift
        USERPW=$1
        ;;
      --adrf)
        ADRF=true
        ;; 
      --notify-name)
        shift
        NOTIFY=$1
        ;;
      -*)
        # do not exit out, just note failure
        error_msg "unrecognized option: $1"
        ;;
      *)
        break;
        ;;
      esac
      shift
done


sudo yum install -y xorg-x11-xauth.x86_64 xorg-x11-server-utils.x86_64 xterm libXt libX11-devel libXt-devel libcurl-devel git

export MAKE='make -j 8'

# install latest R version - Note AWS makes it difficult to upgrade R versions on EMR instances, currently on 3.4 on EMR
sudo yum install R-core R-base R-core-devel R-devel -y

# create rstudio user on all machines
# we need a unix user with home directory and password and hadoop permission
if [ "$USER" != "hadoop" ]; then
  sudo adduser $USER
fi
sudo sh -c "echo '$USERPW' | passwd $USER --stdin"

sudo mkdir /mnt/r-stuff
cd /mnt/r-stuff

sudo sed -i 's/make/make -j 8/g' /usr/lib64/R/etc/Renviron

# set unix environment variables
sudo su << EOF1
echo '
export HADOOP_HOME=/usr/lib/hadoop
export HADOOP_CMD=/usr/bin/hadoop
export HADOOP_STREAMING=/usr/lib/hadoop-mapreduce/hadoop-streaming.jar
export JAVA_HOME=/etc/alternatives/jre
' >> /etc/profile
EOF1
sudo sh -c "source /etc/profile"

# fix hadoop tmp permission
sudo chmod 777 -R /mnt/var/lib/hadoop/tmp

# RCurl package needs curl-config unix package
sudo yum install -y curl-devel

# fix java binding - R and packages have to be compiled with the same java version as hadoop
sudo R CMD javareconf

# Run like so in order to avoid the Rsession error, use restart_server || true in the script
restart_server () {
  sudo rstudio-server restart
}

# Install rstudio only run if master node
if [ "$IS_MASTER" = true -a "$RSTUDIO" = true ]; then
  # install Rstudio server
  # please check and update for latest RStudio version
    
  sudo wget https://download2.rstudio.org/server/centos6/x86_64/rstudio-server-rhel-1.2.1335-x86_64.rpm
  sudo yum install --nogpgcheck -y rstudio-server-rhel-1.2.1335-x86_64.rpm
  
  #wget https://download3.rstudio.org/centos5.9/x86_64/shiny-server-1.4.1.759-rh5-x86_64.rpm
  #sudo yum install --nogpgcheck -y shiny-server-1.4.1.759-rh5-x86_64.rpm
  
  # change port - 8787 will not work for many companies
  sudo sh -c "echo 'www-port=$RSTUDIOPORT' >> /etc/rstudio/rserver.conf"
  # Add a frame origin so it an be embedded in the ADRF site
  sudo sh -c "echo 'www-frame-origin=http://adrf-spark.urban.org/' >> /etc/rstudio/rserver.conf"
  sudo perl -p -i -e "s/= 5../= 100/g" /etc/pam.d/rstudio
fi

if [ "$IS_MASTER" = true -a "$SPARKR_TUTORIALS" = true ]; then
  sudo git clone https://github.com/UrbanInstitute/sparkr-tutorials.git
  cd sparkr-tutorials
  sudo mv * /home/$USER/.
  sudo chown $USER:$USER -Rf /home/$USER
fi

if [ "$IS_MASTER" = true -a "$ADRF" = true ]; then
  sudo wget https://s3.amazonaws.com/ui-spark-social-science-public/emr-util/00_ADRF-Introductory-Tutorial.R
  sudo wget https://s3.amazonaws.com/ui-spark-social-science-public/emr-util/00_ADRF-Introductory-Tutorial_Sparklyr.R
  sudo mv * /home/$USER/.
fi

# install required packages
sudo R --no-save << EOF
install.packages(c('RJSONIO', 'itertools', 'digest', 'Rcpp', 'functional', 'httr', 'plyr', 'stringr', 'reshape2', 'caTools', 'rJava', 'devtools','aws.s3'),
repos="http://cran.rstudio.com")
# here you can add your required packages which should be installed on ALL nodes
# install.packages(c(''), repos="http://cran.rstudio.com", INSTALL_opts=c('--byte-compile') )
EOF


# install rmr2 package
pushd .
rm -rf RHadoop
sudo mkdir RHadoop
cd RHadoop
curl --insecure -L https://github.com/RevolutionAnalytics/rmr2/releases/download/3.3.1/rmr2_3.3.1.tar.gz | sudo tar zx
sudo R CMD INSTALL --byte-compile rmr2
popd


# install rhdfs package
if [ "$RHDFS" = true ]; then
	curl --insecure -L https://raw.github.com/RevolutionAnalytics/rhdfs/master/build/rhdfs_1.0.8.tar.gz | tar zx
	sudo R CMD INSTALL --byte-compile --no-test-load rhdfs
fi


# install plyrmr package
if [ "$PLYRMR" = true ]; then
	# This takes a lot of time. Please remove if not required.
	sudo R --no-save << EOF
  install.packages(c('dplyr', 'R.methodsS3', 'Hmisc', 'memoise', 'rjson'),
  repos="http://cran.rstudio.com" )
EOF
	curl --insecure -L https://github.com/RevolutionAnalytics/plyrmr/releases/download/0.6.0/plyrmr_0.6.0.tar.gz | tar zx
	sudo R CMD INSTALL --byte-compile plyrmr 
fi

if [ "$SPARKR" = true ] || [ "$SPARKLYR" = true ]; then 
cat << 'EOF' > /tmp/Renvextra
JAVA_HOME="/etc/alternatives/jre"
HADOOP_HOME_WARN_SUPPRESS="true"
HADOOP_HOME="/usr/lib/hadoop"
HADOOP_PREFIX="/usr/lib/hadoop"
HADOOP_MAPRED_HOME="/usr/lib/hadoop-mapreduce"
HADOOP_YARN_HOME="/usr/lib/hadoop-yarn"
HADOOP_COMMON_HOME="/usr/lib/hadoop"
HADOOP_HDFS_HOME="/usr/lib/hadoop-hdfs"
YARN_HOME="/usr/lib/hadoop-yarn"
HADOOP_CONF_DIR="/usr/lib/hadoop/etc/hadoop/"
YARN_CONF_DIR="/usr/lib/hadoop/etc/hadoop/"
MAHOUT_HOME="/usr/lib/mahout"
MAHOUT_CONF_DIR="/usr/lib/mahout/conf"
MAHOUT_LOG_DIR="/mnt/var/log/mahout"

HIVE_HOME="/usr/lib/hive"
HIVE_CONF_DIR="/usr/lib/hive/conf"

HBASE_HOME="/usr/lib/hbase"
HBASE_CONF_DIR="/usr/lib/hbase/conf"

IMPALA_HOME="/usr/lib/impala"
IMPALA_CONF_DIR="/usr/lib/impala/conf"

SPARK_HOME="/usr/lib/spark"
SPARK_CONF_DIR="/usr/lib/spark/conf"

PATH=${PWD}:${PATH}
EOF
cat /tmp/Renvextra | sudo  tee -a /usr/lib64/R/etc/Renviron
fi


background_install_proc() {

# install SparkR 
if [ "$SPARKR" = true ]; then 

  # Wait for SparkR to be installed:
  while [ ! -d /usr/lib/spark/R/lib/SparkR ]
  do
    sleep 10
  done

  echo "Found /usr/lib/spark/R/lib/SparkR"


  ### Install additional jars - such as mysql-connector:
  sudo aws s3 cp s3://ui-spark-social-science/emr-util/mysql-connector-java-5.1.41.tar.gz .
  sudo tar -xvzf mysql-connector-java-5.1.41.tar.gz
  sudo mv mysql-connector-java-5.1.41/mysql-connector-java-5.1.41-bin.jar /usr/lib/spark/jars
  sudo rm -r mysql-connector-java-5.1.41
  ###

  sudo R --no-save << EOF
library(devtools)
install('/usr/lib/spark/R/lib/SparkR')

EOF
fi

if [ "$SPARKLYR" = true ]; then
	sudo R --no-save << EOF
  install.packages(c('sparklyr', 'dplyr', 'nycflights13', 'Lahman', 'R.methodsS3', 'Hmisc', 'memoise', 'rjson', 'data.table', 'ggplot2', 'DBI'),
  repos="http://cran.rstudio.com" )
EOF
fi


if [ "$SHINY" = true ]; then
  # install Shiny server
  sudo wget https://download3.rstudio.org/centos6.3/x86_64/shiny-server-1.5.9.923-x86_64.rpm
  sudo yum install --nogpgcheck -y shiny-server-1.5.9.923-x86_64.rpm
  
sudo R --no-save << EOF
install.packages(c('shiny'),
repos="http://cran.rstudio.com")
EOF

fi

if [ "$USER" != "hadoop" ]; then
  while [ ! -f /usr/bin/hdfs ]
  do
    sleep 5
  done
  sudo -u hdfs hadoop fs -mkdir /user/$USER
  sudo -u hdfs hadoop fs -chown root /user/$USER
  sudo -u hdfs hdfs dfs -chmod -R 777 /user/$USER
fi

if [ "$NOTIFY" != "" ]; then
  sudo touch ${NOTIFY}.json
  sudo aws s3 cp ${NOTIFY}.json s3://ui-research/emr_notify/${NOTIFY}.json
fi

sudo rstudio-server restart
echo "rstudio server and packages installation completed"

}

if [ "$IS_MASTER" = true ]; then 
  restart_server || true
  background_install_proc &
fi

if [ "$IS_MASTER" = false ]; then 
  echo "Bootstrap completed on worker nodes"
fi
