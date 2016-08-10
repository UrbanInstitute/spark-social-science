#!/bin/bash
set -x -e

# AWS EMR bootstrap script 
# for installing Python and Jupyter Notebooks on AWS EMR 5.0
# with Spark 2.0 
#
##############################

cd /home/hadoop

#mkdir IPythonNB
#cd IPythonNB
mkdir JupyterNB
cd JupyterNB

python /usr/lib/python2.7/dist-packages/virtualenv.py -p /usr/bin/python2.7 venv
source venv/bin/activate


#Install ipython and dependency
pip install --upgrade pip
pip install jupyter
pip install requests
pip install numpy
pip install matplotlib
pip install pandas
pip install statsmodels

#Create profile   
ipython profile create default

#Run on master /slave based on configuration
echo "c = get_config()" >  /home/hadoop/.ipython/profile_default/ipython_notebook_config.py
echo "c.NotebookApp.ip = '*'" >>  /home/hadoop/.ipython/profile_default/ipython_notebook_config.py
echo "c.NotebookApp.open_browser = False"  >>  /home/hadoop/.ipython/profile_default/ipython_notebook_config.py
echo "c.NotebookApp.port = 8192" >>  /home/hadoop/.ipython/profile_default/ipython_notebook_config.py

#starting ipython notebook with pyspark interactive support.
export JUPYTER_HOME=/home/hadoop/JupyterNB/venv/
export PATH=$PATH:$JUPYTER_HOME/bin
export PYSPARK_DRIVER_PYTHON=jupyter
export PYSPARK_DRIVER_PYTHON_OPTS="notebook --no-browser"
export MASTER=yarn-client
nohup /usr/lib/spark/bin/pyspark --master yarn-client &
