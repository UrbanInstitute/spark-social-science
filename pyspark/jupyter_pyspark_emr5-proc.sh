#!/bin/bash
set -x -e

# AWS EMR bootstrap script 
# for installing Python and Jupyter Notebooks on AWS EMR 5.3 with Spark 2.1.0 
#
# Adapted heavily from AWS Engineer Tom Zeng
#
##############################

# Usage:
# --port - set the port for Jupyter notebook, default is 8192
# --password - set the password for Jupyter notebook
# --no-tutorials - stops git clone of Urban Institute PySpark tutorials
# --ssl - enable ssl, make sure to use your own cert and key files to get rid of the warning
# --copy-samples - copy sample notebooks to samples sub folder under the notebook folder


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

# Default parameters:
PYTHON_PACKAGES=""
DS_PACKAGES=true
JUPYTER_PORT=8194
JUPYTER_PASSWORD=""
PYSPARK_TUTORIALS=true
INTERPRETERS="SQL,PySpark"
USER_SPARK_OPTS=""


# get input parameters
while [ $# -gt 0 ]; do
    case "$1" in
    --python-packages)
      shift
      PYTHON_PACKAGES=$1
      ;;
    --no-ds-packages)
      DS_PACKAGES=false
      ;;
    --port)
      shift
      JUPYTER_PORT=$1
      ;;
    --password)
      shift
      JUPYTER_PASSWORD=$1
      ;;
    --no-tutorials )
      PYSPARK_TUTORIALS=false
      ;;
    --toree-interpreters)
      shift
      INTERPRETERS=$1
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

sudo bash -c 'echo "fs.file-max = 25129162" >> /etc/sysctl.conf'
sudo sysctl -p /etc/sysctl.conf
sudo bash -c 'echo "* soft    nofile          1048576" >> /etc/security/limits.conf'
sudo bash -c 'echo "* hard    nofile          1048576" >> /etc/security/limits.conf'
sudo bash -c 'echo "session    required   pam_limits.so" >> /etc/pam.d/su'


sudo puppet module install spantree-upstart

RELEASE=$(cat /etc/system-release)
REL_NUM=$(ruby -e "puts '$RELEASE'.split.last")


# move /usr/lib to /mnt/usr-moved/lib to avoid running out of space on /
if [ ! -d /mnt/usr-moved ]; then
  sudo mkdir /mnt/usr-moved
  sudo mv /usr/local /mnt/usr-moved/
  sudo ln -s /mnt/usr-moved/local /usr/
  sudo mv /usr/share /mnt/usr-moved/
  sudo ln -s /mnt/usr-moved/share /usr/
fi

export MAKE='make -j 8'

sudo yum install -y xorg-x11-xauth.x86_64 xorg-x11-server-utils.x86_64 xterm libXt libX11-devel libXt-devel libcurl-devel git graphviz cyrus-sasl cyrus-sasl-devel readline readline-devel
sudo yum install --enablerepo=epel -y nodejs npm zeromq3 zeromq3-devel
sudo yum install -y gcc-c++ patch zlib zlib-devel
sudo  yum install -y libyaml-devel libffi-devel openssl-devel make
sudo yum install -y bzip2 autoconf automake libtool bison iconv-devel sqlite devel


export NODE_PATH='/usr/lib/node_modules'


## Python installations and packages, including jupyter:
cd /mnt
sudo python -m pip install --upgrade pip
sudo ln -sf /usr/local/bin/pip2.7 /usr/bin/pip

sudo python -m pip install -U jupyter
sudo python -m pip install -U matplotlib seaborn bokeh cython networkx findspark
sudo python -m pip install -U mrjob pyhive sasl thrift thrift-sasl snakebite
sudo python -m pip install -U scikit-learn pandas numpy numexpr statsmodels scipy

sudo ln -sf /usr/local/bin/ipython /usr/bin/
sudo ln -sf /usr/local/bin/jupyter /usr/bin/

## User specified python packages go here:
if [ ! "$PYTHON_PACKAGES" = "" ]; then
  sudo python -m pip install -U $PYTHON_PACKAGES || true
fi


if [ "$IS_MASTER" = true ]; then

## Configure Jupyter Options:
mkdir -p ~/.jupyter
touch ls ~/.jupyter/jupyter_notebook_config.py

sed -i '/c.NotebookApp.open_browser/d' ~/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.open_browser = False" >> ~/.jupyter/jupyter_notebook_config.py

sed -i '/c.NotebookApp.port/d' ~/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.port = $JUPYTER_PORT" >> ~/.jupyter/jupyter_notebook_config.py

sed -i '/c.NotebookApp.ip/d' ~/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.ip = '*'" >> ~/.jupyter/jupyter_notebook_config.py

sed -i '/c.NotebookApp.MultiKernelManager.default_kernel_name/d' ~/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.MultiKernelManager.default_kernel_name = 'pyspark'" >> ~/.jupyter/jupyter_notebook_config.py

if [ ! "$JUPYTER_PASSWORD" = "" ]; then
  sed -i '/c.NotebookApp.password/d' ~/.jupyter/jupyter_notebook_config.py
  HASHED_PASSWORD=$(python -c "from notebook.auth import passwd; print(passwd('$JUPYTER_PASSWORD'))")
  echo "c.NotebookApp.password = u'$HASHED_PASSWORD'" >> ~/.jupyter/jupyter_notebook_config.py
else
  sed -i '/c.NotebookApp.token/d' ~/.jupyter/jupyter_notebook_config.py
  echo "c.NotebookApp.token = u''" >> ~/.jupyter/jupyter_notebook_config.py
fi

echo "c.Authenticator.admin_users = {'hadoop'}" >> ~/.jupyter/jupyter_notebook_config.py
echo "c.LocalAuthenticator.create_system_users = True" >> ~/.jupyter/jupyter_notebook_config.py


sudo python -m pip install -U notebook ipykernel
sudo python -m ipykernel install

sudo python -m pip install -U jupyter_contrib_nbextensions
sudo jupyter contrib nbextension install --system
sudo python -m pip install -U jupyter_nbextensions_configurator
sudo jupyter nbextensions_configurator enable --system
sudo python -m pip install -U ipywidgets
sudo jupyter nbextension enable --py --sys-prepwdfix widgetsnbextension
sudo python -m pip install -U gvmagic py_d3
sudo python -m pip install -U ipython-sql rpy2


if [[ $PYSPARK_TUTORIALS = true ]]; then
  git clone https://github.com/UrbanInstitute/pyspark-tutorials.git

  echo "c.NotebookApp.notebook_dir = 'pyspark-tutorials/'" >> ~/.jupyter/jupyter_notebook_config.py
  echo "c.ContentsManager.checkpoints_kwargs = {'root_dir': '.checkpoints'}" >> ~/.jupyter/jupyter_notebook_config.py
fi


cd /mnt
curl https://bintray.com/sbt/rpm/rpm | sudo tee /etc/yum.repos.d/bintray-sbt-rpm.repo
sudo yum install docker sbt -y

git clone https://github.com/apache/incubator-toree.git
cd incubator-toree/

make -j8 dist
make release || true 

background_install_proc() {
while [ ! -f /etc/spark/conf/spark-defaults.conf ]
do
  sleep 10
done
echo "Found /etc/spark/conf/spark-defaults.conf"
if ! grep "spark.jars.packages" /etc/spark/conf/spark-defaults.conf; then
  sudo bash -c "echo 'spark.jars.packages              $SPARK_PACKAGES' >> /etc/spark/conf/spark-defaults.conf"
fi

sudo python -m pip install /mnt/incubator-toree/dist/toree-pip
export SPARK_HOME="/usr/lib/spark/"

SPARK_PACKAGES="com.databricks:spark-csv_2.11:1.5.0"


if [ "$USER_SPARK_OPTS" = "" ]; then
  SPARK_OPTS="--packages $SPARK_PACKAGES"
else
  SPARK_OPTS=$USER_SPARK_OPTS
  SPARK_PACKAGES=$(ruby -e "opts='$SPARK_OPTS'.split;pkgs=nil;opts.each_with_index{|o,i| pkgs=opts[i+1] if o.start_with?('--packages')};puts pkgs || '$SPARK_PACKAGES'")
fi

export SPARK_OPTS
export SPARK_PACKAGES

sudo jupyter toree install --interpreters=$INTERPRETERS --spark_home=$SPARK_HOME --spark_opts="$SPARK_OPTS"


echo "Starting Jupyter notebook via pyspark"
cd ~

sudo puppet apply << PUPPET_SCRIPT
include 'upstart'
upstart::job { 'jupyter':
  description    => 'Jupyter',
  respawn        => true,
  respawn_limit  => '0 10',
  start_on       => 'runlevel [2345]',
  stop_on        => 'runlevel [016]',
  console        => 'output',
  chdir          => '/home/hadoop',
  script           => '
  sudo su - hadoop > /var/log/jupyter.log 2>&1 <<BASH_SCRIPT
  export NODE_PATH="$NODE_PATH"
  export PYSPARK_DRIVER_PYTHON="jupyter"
  export PYSPARK_DRIVER_PYTHON_OPTS="notebook --no-browser $SSL_OPTS_JUPYTER --log-level=INFO"
  export NOTEBOOK_DIR="$NOTEBOOK_DIR"
  pyspark
BASH_SCRIPT
  ',
}
PUPPET_SCRIPT
}

echo "Running background process to install Apacke Toree"
background_install_proc &
fi
echo "Bootstrap action foreground process finished"

