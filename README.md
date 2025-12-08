# rancher_caffeine

This repo is for the Caffeinate and Collaboriate Webinar.

https://www.purestorage.com/events/webinars/caffeinate-and-collaborate-pure-partner-webinar-series.html


**Pure + Rancher: Containers without Complexity**
Andy Clemenko, Systems Engineer Federal Defense Pure Storage and Greg Carl, Principal Technologist Pure Storage

In this session, you will learn how to simplify Kubernetes and container adoption using Pure Storage Portworx and SUSE Rancher. We’ll cover how the joint solution delivers enterprise-grade data services including high availability, encryption, automated scaling, and compliance with standards like FIPS 140-2 across bare-metal, hybrid, and multi-cloud environments. You will leave enabled with the messaging and use cases that show how agencies can modernize applications quickly and securely while reducing operational overhead.

## Deploy Harvester

Your mileage may vary. ISO install is the simplest way. https://docs.harvesterhci.io/v1.6/install/index

I prefer PXE since it is reproducible. https://youtu.be/UA_GVZaoSfQ

## Add PX-CSI to Harvester

Check out : https://github.com/clemenko/px-harvester

## Build VMs on Harvester

secret sauce, or the `pure_harvester.sh` command. could go either way.

## Deploy rke2/Rancher on vms

This script `pure_harvester.sh` has the orders of operation. Worth a look.

## Other videos

Check out https://andyc.info/tubes