#!/bin/bash

for i in {1..3}; do
    echo -e "\nStarting node $i ..."
    bash stop_vm.sh $i
done
