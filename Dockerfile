from alpine

run apk add postgresql15 ansible sudo

copy configure.yml .
copy vars.yml .
copy templates .
copy init.sh .

entrypoint [ "/bin/ash", "init.sh" ]
