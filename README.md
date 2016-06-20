# spark-social-science
Automated Spark Cluster Builds with RStudio or PySpark for Policy Research

The goal of this project is to deliver powerful and elastic Spark clusters to researchers and data analysts with as little setup time and effort possible. To do that, at the Urban Institute, we use two critical components: (1) a Amazon Web Services (AWS) CloudFormation script to launch AWS Elastic MapReduce (EMR) clusters (2) a bootstrap script that runs on the Master node of the new cluster to install statistical programs and development environments (RStudio and Jupyter Notebooks). 

This guide illustrates the (relatively) straight forward process to provide clusters for your analysts and researchers. For more information about using Spark via the R and Python APIs, see these repositories:

<ul>
	<li>https://github.com/UrbanInstitute/sparkr-tutorials</li>
	<li>https://github.com/UrbanInstitute/pyspark-tutorials</li>
</ul>

## Setup 

Just a few steps will get you to working Spark Clusters.

First, create an AWS S3 bucket for your EMR scripts and logs. There are two bootstrap scripts (.sh files) for each of the two environments. You only need to change one thing for these bootstrap scripts to work. Within the file that ends with '_emrv4.sh', simple replace the phrase 'your-bucket-name-goes-here' with the name of the bucket you just created. You then need to take both bootstrap scripts (the one that you just changed that ends in "_emrv4.sh" and the one that ends in "emrv4-proc.sh") for your preferred environment and upload them to your new bucket.

##


