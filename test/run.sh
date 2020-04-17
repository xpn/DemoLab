#!/bin/sh

USER='admin'
PASS='Password@1'

FIRST_DC_IP=$(cat ../terraform/output.json| jq -r '.["first-dc_ip"].value')
SECOND_DC_IP=$(cat ../terraform/output.json| jq -r '.["second-dc_ip"].value')

inspec exec first-dc -b winrm --user $USER --password $PASS -t "winrm://$FIRST_DC_IP"
inspec exec second-dc -b winrm --user $USER --password $PASS -t "winrm://$SECOND_DC_IP"
