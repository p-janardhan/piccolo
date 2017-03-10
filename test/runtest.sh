#!/bin/bash

for testname in $(ls | grep -e '^Test[0-9][0-9][0-9]$'); do
  echo -n '[' $testname '] '
  head -n 1 $testname/$testname.pi
  rm -rf a.out
  echo -ne "Compilation:\t"
  piccolo $testname/$testname.pi > /dev/null 2> /dev/null
  if [ $? == 0 ]; then
    echo -ne "\e[0;32mOK\e[0m\t"
    echo -ne "Execution:\t"
    diff $testname/expected0 <(./a.out) --ignore-all-space > /dev/null
    if [ $? == 0 ]; then
      echo -ne "\e[0;32mOK\e[0m\t"
      if [ "$WITH_VALGRIND" == 1 ]; then
        echo -ne "With valgrind:\t"
        valgrind --leak-check=full --error-exitcode=2 ./a.out > /dev/null 2> /dev/null
        if [ $? == 0 ]; then
          echo -ne "\e[0;32mOK\e[0m\t"
        else
          echo -ne "\e[0;31mFAILED\e[0m\t"
        fi
      fi
    else
      echo -ne "\e[0;31mFAILED\e[0m\t"
    fi
  else
    echo -ne "\e[0;31mFAILED\e[0m\t"
  fi
  echo
  echo
  rm -rf a.out /tmp/piccolo-test
done
