#!/bin/bash
set -x -e

# AWS EMR bootstrap script 
# for installing Python and Jupyter Notebooks on AWS EMR
#
##############################


cd /home/hadoop

mkdir IPythonNB
cd IPythonNB
python /usr/lib/python2.7/dist-packages/virtualenv.py -p /usr/bin/python2.7 venv
source venv/bin/activate


#Install ipython and dependency
sudo pip install --upgrade pip
pip install "ipython[notebook]"
pip install requests numpy
pip install matplotlib

#Create profile   
ipython profile create default

#Run on master /slave based on configuration
echo "c = get_config()" >  /home/hadoop/.ipython/profile_default/ipython_notebook_config.py
echo "c.NotebookApp.ip = '*'" >>  /home/hadoop/.ipython/profile_default/ipython_notebook_config.py
echo "c.NotebookApp.open_browser = False"  >>  /home/hadoop/.ipython/profile_default/ipython_notebook_config.py
echo "c.NotebookApp.port = 8192" >>  /home/hadoop/.ipython/profile_default/ipython_notebook_config.py

#starting ipython notebook with pyspark interactive support.
export IPYTHON_HOME=/home/hadoop/IPythonNB/venv/
export PATH=$PATH:$IPYTHON_HOME/bin
export IPYTHON_OPTS="notebook --no-browser"
export MASTER=yarn-client
nohup /usr/lib/spark/bin/pyspark  --master yarn-client  > /mnt/var/log/python_notebook.log &