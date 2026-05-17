# Plan the playground cluster

## Nodes

This cluster has 3 nodes:

1. One control node
2. Two agent nodes

## Basic services

Instead of the default traefik ingress it shoud have ingress-nginx deployed.
Instead of the default serviceLB it should metallb deployed
It should have a registry:2 deployed so we can keep images locally
It should have ArgoCD deployed and activated. All cluster configuration should use a gitops workflow.

## Order

After creating the cluster first create the ArgoCD deployment and let us create the github project for ArgoCD to use.

## Process

Please never execute any commands that manipulate the cluster. Always tell me what to do and i will do it manually to learn.
