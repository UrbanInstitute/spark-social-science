#!/bin/bash
set -x -e

# AWS EMR bootstrap script - largely written by Tom Zeng of Amazon Web Services
# for installing open-source R (www.r-project.org) with RHadoop packages and RStudio on AWS EMR
#
##############################

# Usage:
# --no-rstudio - don't install rstudio-server
# --sparklyr - install RStudio's sparklyr package
# --sparkr - install SparkR package
# --shiny - install Shiny server
#
# --user - set user for rstudio, default "hadoop"
# --user-pw - set user-pw for user USER, default "hadoop"
# --rstudio-port - set rstudio port, default 8787
#
# --rexamples - add R examples to the user home dir, default false
# --rhdfs - install rhdfs package, default false
# --plyrmr - install plyrmr package, default false
# --no-updateR - don't update latest R version
# --latestR - install latest R version, default false (build from source - caution, may cause problem with RStudio)
#


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
RSTUDIO=true
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
SPARKLYR=false
while [ $# -gt 0 ]; do
	case "$1" in
		--sparklyr)
			SPARKLYR=true
			;;
  	--rstudio)
      RSTUDIO=true
  		;;
		--no-rstudio)
			RSTUDIO=false
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
		--no-updateR)
			UPDATER=false
			;;
		--latestR)
			LATEST_R=true
			UPDATER=false
			;;
    --sparkr)
    	SPARKR=true
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

export MAKE='make -j 8'

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
	sudo yum install -y gcc gcc-c++ gcc-gfortran
	sudo yum install -y readline-devel cairo-devel libpng-devel libjpeg-devel libtiff-devel
	cd R-3*
	./configure --with-readline=yes --enable-R-profiling=no --enable-memory-profiling=no --enable-R-shlib --with-pic --prefix=/usr --without-x --with-libpng --with-jpeglib --with-cairo --enable-R-shlib --with-recommended-packages=yes
	make -j 8
	sudo make install
  sudo su << EOF1
echo '
export PATH=${PWD}/bin:$PATH
' >> /etc/profile
EOF1
  popd
fi

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
  #sudo rstudio-server restart
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
repos="http://cran.rstudio.com")
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

# wait SparkR file to show up
while [ ! -d /usr/lib/spark/R/lib/SparkR ]
do
  sleep 5
done
sleep 5
fi

# install SparkR
if [ "$SPARKR" = true ]; then 
  #the following are needed only if not login in as hadoop
  sudo mkdir /mnt/spark
  sudo chmod a+rwx /mnt/spark
  if [ -d /mnt1 ]; then
    sudo mkdir /mnt1/spark
    sudo chmod a+rwx /mnt1/spark
  fi
  
  sudo R --no-save << EOF
    library(devtools)
    install('/usr/lib/spark/R/lib/SparkR')
    # here you can add your required packages which should be installed on ALL nodes
    # install.packages(c(''), repos="http://cran.rstudio.com", INSTALL_opts=c('--byte-compile') )
    EOF

fi

if [ "$SPARKLYR" = true ]; then
	sudo R --no-save << EOF
  install.packages(c('sparklyr', 'dplyr', 'nycflights13', 'Lahman', 'R.methodsS3', 'Hmisc', 'memoise', 'rjson', 'data.table', 'ggplot2', 'DBI'),
  repos="http://cran.rstudio.com" )
EOF
fi


if [ "$IS_MASTER" = true -a "$SHINY" = true ]; then
  # install Shiny server
  wget https://download3.rstudio.org/centos5.9/x86_64/shiny-server-1.4.1.759-rh5-x86_64.rpm
  sudo yum install --nogpgcheck -y shiny-server-1.4.1.759-rh5-x86_64.rpm
  
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

sudo rstudio-server restart
echo "rstudio server and packages installation completed"
