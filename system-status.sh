#!/bin/bash

echo "System Status Information"
echo "-------------------------"

echo "CPU Activity Level:"
uptime

echo

echo "Free Memory:"
free -h

echo

echo "Free Disk Space:"
df -h
