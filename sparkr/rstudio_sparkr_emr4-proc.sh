#!/bin/bash
set -x -e

# AWS EMR bootstrap script 
# for installing open-source R (www.r-project.org) with RHadoop packages and RStudio on AWS EMR
#
##############################


# Usage:
# --rstudio - installs rstudio-server default false
# --rexamples - adds R examples to the user home dir, default false
# --rhdfs - installs rhdfs package, default false
# --plyrmr - installs plyrmr package, default false
# --updateR - installs latest R version, default true (use yum update) 
# --latestR - installs latest R version, default false (build from source)
# --user - sets user for rstudio, default "rstudio"
# --user-pw - sets user-pw for user USER, default "rstudio"
# --rstudio-port - sets rstudio port, default 80
# --sparkr - install SparkR package
# --sparkr-pkg - install deprecated SparkR-pkg package (has RDD API)


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
RSTUDIO=false
SHINY=false
REXAMPLES=false
USER="hadoop"
USERPW="hadoop"
PLYRMR=false
RHDFS=false
UPDATER=true
LATEST_R=false
RSTUDIOPORT=8787
SPARKR=false
SPARKR_PKG=false
while [ $# -gt 0 ]; do
	case "$1" in
		--rstudio)
			RSTUDIO=true
			;;
		--shiny)
			SHINY=true
			;;
		--rexamples)
			REXAMPLES=true
			;;
		--plyrmr)
			PLYRMR=true
			;;
		--rhdfs)
			RHDFS=true
			;;
		--updateR)
			UPDATER=true
			;;
		--latestR)
			LATEST_R=true
			UPDATER=false
			;;
    --sparkr)
    	SPARKR=true
    	;;
    --sparkr-pkg)
    	SPARKR_PKG=true
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

# install latest R version from AWS Repo
if [ "$UPDATER" = true ]; then
sudo yum update R-core R-base R-core-devel R-devel -y
fi

# create rstudio user on all machines
# we need a unix user with home directory and password and hadoop permission
if [ "$USER" != "hadoop" ]; then
sudo adduser $USER
fi
sudo sh -c "echo '$USERPW' | passwd $USER --stdin"

mkdir /mnt/r-stuff
cd /mnt/r-stuff


# update to latest R version
if [ "$LATEST_R" = true ]; then
  pushd .
	mkdir R-latest
	cd R-latest
	wget http://cran.r-project.org/src/base/R-latest.tar.gz
	tar -xzf R-latest.tar.gz
	sudo yum install -y gcc
	sudo yum install -y gcc-c++
	sudo yum install -y gcc-gfortran
	sudo yum install -y readline-devel
	cd R-3*
	#./configure --with-x=no --with-readline=no --enable-R-profiling=no --enable-memory-profiling=no --enable-R-shlib --with-pic --prefix=/usr --with-x --with-libpng --with-jpeglib
  ./configure --with-recommended-packages=yes --without-x --with-cairo --with-libpng --with-libtiff --with-jpeglib --enable-R-shlib --prefix=/usr --enable-R-profiling=no --enable-memory-profiling=no
	make
	sudo make install
  sudo su << EOF1
echo '
export PATH=${PWD}/bin:$PATH
' >> /etc/profile
EOF1
  popd
fi

# set unix environment variables
sudo su << EOF1
echo '
export HADOOP_HOME=/usr/lib/hadoop vimlike
export HADOOP_CMD=/usr/bin/hadoop vimlike
export HADOOP_STREAMING=/usr/lib/hadoop-mapreduce/hadoop-streaming.jar vimlike
export JAVA_HOME=/etc/alternatives/jre vimlike
' >> /etc/profile
EOF1
sudo sh -c "source /etc/profile"

# fix hadoop tmp permission
sudo chmod 777 -R /mnt/var/lib/hadoop/tmp

# RCurl package needs curl-config unix package
sudo yum install -y curl-devel

# fix java binding - R and packages have to be compiled with the same java version as hadoop
sudo R CMD javareconf


# install rstudio
# only run if master node
if [ "$IS_MASTER" = true -a "$RSTUDIO" = true ]; then
  # install Rstudio server
  # please check and update for latest RStudio version
    
  wget https://download2.rstudio.org/rstudio-server-rhel-0.99.491-x86_64.rpm
  sudo yum install --nogpgcheck -y rstudio-server-rhel-0.99.491-x86_64.rpm
  
  #wget https://download3.rstudio.org/centos5.9/x86_64/shiny-server-1.4.1.759-rh5-x86_64.rpm
  #sudo yum install --nogpgcheck -y shiny-server-1.4.1.759-rh5-x86_64.rpm
  
  # change port - 8787 will not work for many companies
  sudo sh -c "echo 'www-port=$RSTUDIOPORT' >> /etc/rstudio/rserver.conf"
  sudo perl -p -i -e "s/= 5../= 100/g" /etc/pam.d/rstudio
  sudo rstudio-server restart
fi

if [ "$IS_MASTER" = true -a "$SHINY" = true ]; then
  # install Shiny server
  wget https://download3.rstudio.org/centos5.9/x86_64/shiny-server-1.4.1.759-rh5-x86_64.rpm
  sudo yum install --nogpgcheck -y shiny-server-1.4.1.759-rh5-x86_64.rpm
  sudo shiny-server restart
fi


# add examples to user
# only run if master node
if [ "$IS_MASTER" = true -a "$REXAMPLES" = true ]; then
  # and copy R example scripts to user's home dir amd set permission
  wget --no-check-certificate https://raw.githubusercontent.com/tomz/emr-bootstrap-actions/master/R/Hadoop/examples/rmr2_example.R
  wget --no-check-certificate https://raw.githubusercontent.com/tomz/emr-bootstrap-actions/master/R/Hadoop/examples/biganalyses_example.R
  wget --no-check-certificate https://raw.githubusercontent.com/tomz/emr-bootstrap-actions/master/R/Hadoop/examples/change_pw.R
  #sudo cp -p *.R /home/$USER/.
  sudo mv *.R /home/$USER/.
  sudo chown $USER:$USER -Rf /home/$USER
fi


# install required packages
sudo R --no-save << EOF
install.packages(c('RJSONIO', 'itertools', 'digest', 'Rcpp', 'functional', 'httr', 'plyr', 'stringr', 'reshape2', 'caTools', 'rJava', 'devtools'),
repos="http://cran.rstudio.com", INSTALL_opts=c('--byte-compile') )
# here you can add your required packages which should be installed on ALL nodes
# install.packages(c(''), repos="http://cran.rstudio.com", INSTALL_opts=c('--byte-compile') )
EOF


# install rmr2 package
pushd .
rm -rf RHadoop
mkdir RHadoop
cd RHadoop
curl --insecure -L https://github.com/RevolutionAnalytics/rmr2/releases/download/3.3.1/rmr2_3.3.1.tar.gz | tar zx
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
  repos="http://cran.rstudio.com", INSTALL_opts=c('--byte-compile') )
EOF
	curl --insecure -L https://github.com/RevolutionAnalytics/plyrmr/releases/download/0.6.0/plyrmr_0.6.0.tar.gz | tar zx
	sudo R CMD INSTALL --byte-compile plyrmr 
fi


# install SparkR or the out-dated SparkR-pkg
if [ "$SPARKR" = true ] || [ "$SPARKR_PKG" = true ]; then 
  #the following are needed only if not login in as hadoop
  sudo mkdir /mnt/spark
  sudo chmod a+rwx /mnt/spark
  if [ -d /mnt1 ]; then
    sudo mkdir /mnt1/spark
    sudo chmod a+rwx /mnt1/spark
  fi
  
  if [ "$SPARKR" = true ]; then
    #wait file to show up
    while [ ! -d /usr/lib/spark/R/lib/SparkR ]
    do
      sleep 10
    done
    sleep 15
  	sudo R --no-save << EOF
library(devtools)
install('/usr/lib/spark/R/lib/SparkR')
# here you can add your required packages which should be installed on ALL nodes
# install.packages(c(''), repos="http://cran.rstudio.com", INSTALL_opts=c('--byte-compile') )
EOF
  else
    pushd . 
    git clone https://github.com/amplab-extras/SparkR-pkg.git
    cd SparkR-pkg
    git checkout sparkr-sql # Spark 1.4 support is in this branch
    
    sudo su << EOF
echo '
export PATH=${PWD}:$PATH
' >> /etc/profile
EOF
    #wait file to show up
    while [ ! -f /usr/lib/hadoop-lzo/lib/hadoop-lzo.jar -o ! -d /usr/lib/hadoop/client ]
    do
      sleep 10
    done
    sleep 15
    # copy the emr dependencies to the SBT unmanaged jars directory
    mkdir pkg/src/lib
    cp /usr/lib/hadoop-lzo/lib/hadoop-lzo.jar pkg/src/lib
    cp /usr/lib/hadoop/client/hadoop-mapreduce-client-core-2.6.0-amzn-*.jar pkg/src/lib
    wget http://central.maven.org/maven2/com/typesafe/sbt/sbt-launcher/0.13.6/sbt-launcher-0.13.6.jar
    # fix the corrupted sbt-launch-0.13.6.jar in the github repo
    cp sbt-launcher-0.13.6.jar pkg/src/sbt/sbt-launch-0.13.6.jar
    # build againt Spark 1.4 and YARN/Hadoop 2.6
    USE_YARN=1 SPARK_VERSION=1.4.0 SPARK_YARN_VERSION=2.6.0 SPARK_HADOOP_VERSION=2.6.0 ./install-dev.sh
  	sudo R --no-save << EOF
    install.packages('testthat',repos="http://cran.rstudio.com") 
  	library(devtools)
  	install('${PWD}/pkg/R/SparkR')
  	# here you can add your required packages which should be installed on ALL nodes
  	# install.packages(c(''), repos="http://cran.rstudio.com", INSTALL_opts=c('--byte-compile') )
  	install.packages('randomForest',repos="http://cran.rstudio.com")
  	install.packages('caret',repos="http://cran.rstudio.com")
  	install.packages('pROC',repos="http://cran.rstudio.com")
EOF
    popd
  fi


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

