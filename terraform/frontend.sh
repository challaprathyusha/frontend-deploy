#!/bin/bash
component=$1
environment=$2
app_Version=$3
dnf install ansible -y
pip3.9 install botocore boto3 #ansible to connect to aws we need to install this pipmodules
ansible-pull -i localhost, -U https://github.com/challaprathyusha/expenses-ansible-roles-tf.git main.yaml -e COMPONENT=$component -e env=$environment -e appVersion=$app_Version