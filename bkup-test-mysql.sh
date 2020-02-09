#!/usr/bin/env bash

`/usr/bin/mysql -s $1 -e'exit' >/dev/null 2>/dev/null ` 
if [ $? -ne 0 ]
then
    INFO="Credentials not OK."
    echo "Credentials not OK";
else
    INFO="Credentials OK."
    echo "Credentials OK";
fi

